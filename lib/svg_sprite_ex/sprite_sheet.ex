defmodule SvgSpriteEx.SpriteSheet do
  @moduledoc false

  require Record

  alias Phoenix.HTML
  alias Phoenix.HTML.Safe
  alias SvgSpriteEx.Source
  alias SvgSpriteEx.SpriteSheet.CSSRewriter
  alias SvgSpriteEx.SpriteSheet.Fragment
  alias SvgSpriteEx.Xmerl

  Record.defrecordp(
    :xml_attribute,
    Record.extract(:xmlAttribute, from_lib: "xmerl/include/xmerl.hrl")
  )

  Record.defrecordp(
    :xml_element,
    Record.extract(:xmlElement, from_lib: "xmerl/include/xmerl.hrl")
  )

  Record.defrecordp(
    :xml_text,
    Record.extract(:xmlText, from_lib: "xmerl/include/xmerl.hrl")
  )

  @passthrough_attribute_exclusions MapSet.new(["height", "viewBox", "width", "xmlns"])
  @local_fragment_href_attrs MapSet.new(["href", "xlink:href"])
  @id_reference_attrs MapSet.new([
                        "aria-activedescendant",
                        "aria-controls",
                        "aria-describedby",
                        "aria-details",
                        "aria-errormessage",
                        "aria-flowto",
                        "aria-labelledby",
                        "aria-owns",
                        "for"
                      ])

  @smil_timing_attrs MapSet.new(["begin", "end"])
  @smil_animation_elements MapSet.new([
                             "animate",
                             "animateColor",
                             "animateMotion",
                             "animateTransform",
                             "set"
                           ])
  @smil_animation_value_attrs MapSet.new(["by", "from", "to", "values"])

  @url_reference_attrs MapSet.new([
                         "clip-path",
                         "color-profile",
                         "cursor",
                         "fill",
                         "filter",
                         "marker",
                         "marker-end",
                         "marker-mid",
                         "marker-start",
                         "mask",
                         "stroke",
                         "style"
                       ])

  @doc """
  Builds a deterministic `<svg>` sprite sheet from logical SVG asset paths.
  """
  def build(paths, opts \\ []) when is_list(paths) do
    source_root = Keyword.fetch!(opts, :source_root)

    paths
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.map(&Source.read!(&1, source_root))
    |> Enum.uniq_by(& &1.name)
    |> ensure_unique_sprite_ids!()
    |> Enum.map(&build_symbol!/1)
    |> wrap_sprite_sheet()
  end

  @doc """
  Returns the source attributes that should be copied through to `<symbol>`.

  Enforced sprite attributes such as `viewBox`, `width`, `height`, and `xmlns`
  are excluded.
  """
  def symbol_attributes(attributes) when is_map(attributes) do
    attributes
    |> Enum.reject(fn {name, _value} ->
      MapSet.member?(@passthrough_attribute_exclusions, name)
    end)
    |> Enum.into(%{})
  end

  defp build_symbol!(%Source{
         name: normalized_name,
         attributes: attributes,
         content_nodes: content_nodes
       }) do
    view_box = resolve_view_box!(attributes, normalized_name)
    sprite_id = Source.sprite_id_from_normalized(normalized_name)
    id_map = build_local_id_map(attributes, content_nodes, sprite_id, normalized_name)
    rewritten_attributes = rewrite_symbol_attributes!(attributes, normalized_name, id_map)
    rendered_symbol_attrs = render_symbol_attrs(rewritten_attributes)

    escaped_view_box = escape_xml_attr(view_box)
    rewritten_content = rewrite_content_nodes!(normalized_name, content_nodes, id_map)

    """
    <symbol id="#{sprite_id}" viewBox="#{escaped_view_box}"#{rendered_symbol_attrs}>
    #{rewritten_content}
    </symbol>
    """
  end

  defp wrap_sprite_sheet([]) do
    "<svg xmlns=\"http://www.w3.org/2000/svg\">\n</svg>\n"
  end

  defp wrap_sprite_sheet(symbols) do
    IO.iodata_to_binary([
      "<svg xmlns=\"http://www.w3.org/2000/svg\">\n",
      Enum.join(symbols, "\n"),
      "\n</svg>\n"
    ])
  end

  defp ensure_unique_sprite_ids!(sources) do
    collisions =
      sources
      |> Enum.group_by(&Source.sprite_id_from_normalized(&1.name))
      |> Enum.filter(fn {_sprite_id, sprite_sources} -> length(sprite_sources) > 1 end)
      |> Enum.sort_by(&elem(&1, 0))

    case collisions do
      [] ->
        sources

      _collisions ->
        details =
          Enum.map_join(collisions, "; ", fn {sprite_id, sprite_sources} ->
            file_paths =
              sprite_sources |> Enum.map(& &1.file_path) |> Enum.sort() |> Enum.join(", ")

            "#{sprite_id}: #{file_paths}"
          end)

        raise ArgumentError, "sprite ID collisions detected: #{details}"
    end
  end

  defp build_local_id_map(attributes, content_nodes, sprite_id, normalized_name) do
    root_id = Map.get(attributes, "id")

    content_nodes
    |> collect_local_id_occurrences(collect_root_id_occurrence(attributes))
    |> Enum.reverse()
    |> validate_local_id_occurrences!(normalized_name)
    |> Map.new(fn %{id: id} ->
      {id, rewritten_local_id(id, root_id, sprite_id)}
    end)
  end

  defp rewrite_symbol_attributes!(attributes, normalized_name, id_map) do
    attributes
    |> symbol_attributes()
    |> Map.drop(["id"])
    |> Enum.map(fn {name, value} ->
      {name, rewrite_attribute_value!(name, value, normalized_name, id_map)}
    end)
    |> Enum.into(%{})
  end

  defp rewrite_content_nodes!(normalized_name, content_nodes, id_map) do
    content_nodes
    |> rewrite_nodes!(normalized_name, id_map)
    |> render_content_nodes()
  end

  defp collect_root_id_occurrence(attributes) do
    case Map.fetch(attributes, "id") do
      {:ok, id} -> [%{id: id, location: "root <svg>"}]
      :error -> []
    end
  end

  defp collect_local_id_occurrences([], occurrences), do: occurrences

  defp collect_local_id_occurrences([node | rest], occurrences) do
    occurrences = collect_element_id_occurrences(node, occurrences)
    collect_local_id_occurrences(rest, occurrences)
  end

  defp collect_element_id_occurrences(node, occurrences) do
    case xml_element_node?(node) do
      true ->
        occurrences =
          node
          |> xml_element(:attributes)
          |> collect_id_occurrence(element_id_location(node), occurrences)

        collect_local_id_occurrences(xml_element(node, :content), occurrences)

      false ->
        occurrences
    end
  end

  defp collect_id_occurrence(attributes, location, occurrences) do
    Enum.reduce(attributes, occurrences, fn attribute, collected_occurrences ->
      case {attribute_name(attribute), attribute_value(attribute)} do
        {"id", id} -> [%{id: id, location: location} | collected_occurrences]
        _other -> collected_occurrences
      end
    end)
  end

  defp element_id_location(node) do
    element_name = node |> xml_element(:name) |> Atom.to_string()
    "<#{element_name}> at child position #{xml_element(node, :pos)}"
  end

  defp validate_local_id_occurrences!(occurrences, normalized_name) do
    Enum.each(occurrences, &validate_local_id!(&1, normalized_name))

    occurrences
    |> Enum.group_by(& &1.id)
    |> Enum.filter(fn {_id, id_occurrences} -> length(id_occurrences) > 1 end)
    |> Enum.sort_by(&elem(&1, 0))
    |> case do
      [] ->
        occurrences

      [{id, id_occurrences} | _rest] ->
        locations = Enum.map_join(id_occurrences, ", ", & &1.location)

        raise ArgumentError,
              "svg asset #{inspect(normalized_name)} contains duplicate local id #{inspect(id)} at #{locations}"
    end
  end

  defp validate_local_id!(%{id: "", location: location}, normalized_name) do
    raise ArgumentError,
          "svg asset #{inspect(normalized_name)} contains a local id at #{location} that must not be empty"
  end

  defp validate_local_id!(%{id: id, location: location}, normalized_name) do
    case Regex.match?(~r/\s/u, id) do
      true ->
        raise ArgumentError,
              "svg asset #{inspect(normalized_name)} contains local id #{inspect(id)} at #{location}; local ids must not contain whitespace"

      false ->
        :ok
    end
  end

  defp rewritten_local_id(id, id, sprite_id), do: sprite_id
  defp rewritten_local_id(id, _root_id, sprite_id), do: "#{sprite_id}-#{id}"

  defp rewrite_nodes!(nodes, normalized_name, id_map) do
    Enum.map(nodes, &rewrite_node!(&1, normalized_name, id_map))
  end

  defp rewrite_node!(node, normalized_name, id_map) do
    cond do
      style_element_node?(node) ->
        rewrite_style_node!(node, normalized_name, id_map)

      xml_element_node?(node) ->
        updated_attributes = rewrite_element_attributes!(node, normalized_name, id_map)

        updated_content =
          node
          |> xml_element(:content)
          |> rewrite_nodes!(normalized_name, id_map)

        xml_element(node, attributes: updated_attributes, content: updated_content)

      true ->
        node
    end
  end

  defp rewrite_attribute!(attribute, normalized_name, id_map) do
    name = attribute_name(attribute)
    value = attribute_value(attribute)

    rewritten_value = rewrite_attribute_value!(name, value, normalized_name, id_map)

    update_attribute_value(attribute, value, rewritten_value)
  end

  defp rewrite_element_attributes!(node, normalized_name, id_map) do
    attributes = xml_element(node, :attributes)
    animation_target = smil_animation_target(node, attributes)

    Enum.map(
      attributes,
      &rewrite_element_attribute!(&1, animation_target, normalized_name, id_map)
    )
  end

  defp rewrite_element_attribute!(attribute, nil, normalized_name, id_map) do
    rewrite_attribute!(attribute, normalized_name, id_map)
  end

  defp rewrite_element_attribute!(attribute, animation_target, normalized_name, id_map) do
    name = attribute_name(attribute)
    value = attribute_value(attribute)

    rewritten_value =
      case MapSet.member?(@smil_animation_value_attrs, name) do
        true ->
          rewrite_smil_animation_value!(name, value, animation_target, normalized_name, id_map)

        false ->
          rewrite_attribute_value!(name, value, normalized_name, id_map)
      end

    update_attribute_value(attribute, value, rewritten_value)
  end

  defp update_attribute_value(attribute, value, rewritten_value) do
    case rewritten_value == value do
      true -> attribute
      false -> xml_attribute(attribute, value: String.to_charlist(rewritten_value))
    end
  end

  defp smil_animation_target(node, attributes) do
    element_name = node |> xml_element(:name) |> Atom.to_string()
    animation_element? = MapSet.member?(@smil_animation_elements, element_name)

    resolve_smil_animation_target(animation_element?, attributes)
  end

  defp resolve_smil_animation_target(false, _attributes), do: nil

  defp resolve_smil_animation_target(true, attributes) do
    attribute_values = Map.new(attributes, &{attribute_name(&1), attribute_value(&1)})

    normalize_smil_animation_target(
      attribute_values["attributeName"],
      attribute_values["attributeType"]
    )
  end

  defp normalize_smil_animation_target(nil, _attribute_type), do: nil

  defp normalize_smil_animation_target(attribute_name, attribute_type) do
    attribute_name
    |> String.trim()
    |> normalize_smil_animation_target_type(attribute_type)
  end

  defp normalize_smil_animation_target_type("", _attribute_type), do: nil

  defp normalize_smil_animation_target_type(attribute_name, attribute_type) do
    case attribute_type |> to_string() |> String.trim() |> String.downcase() do
      "css" -> String.downcase(attribute_name)
      _other -> attribute_name
    end
  end

  defp rewrite_smil_animation_value!("values", value, target, normalized_name, id_map) do
    value
    |> String.split(";", trim: false)
    |> Enum.map_join(";", &rewrite_attribute_value!(target, &1, normalized_name, id_map))
  end

  defp rewrite_smil_animation_value!(_name, value, target, normalized_name, id_map) do
    rewrite_attribute_value!(target, value, normalized_name, id_map)
  end

  defp rewrite_attribute_value!(name, value, normalized_name, id_map) do
    cond do
      name == "id" ->
        rewrite_local_id!(value, normalized_name, id_map)

      MapSet.member?(@local_fragment_href_attrs, name) ->
        rewrite_fragment_href!(value, name, normalized_name, id_map)

      MapSet.member?(@id_reference_attrs, name) ->
        rewrite_known_id_references(value, id_map)

      MapSet.member?(@smil_timing_attrs, name) ->
        rewrite_smil_timing_references(value, id_map)

      MapSet.member?(@url_reference_attrs, name) ->
        CSSRewriter.rewrite_urls!(value, normalized_name, id_map, name)

      true ->
        value
    end
  end

  defp rewrite_local_id!("", _normalized_name, _id_map), do: ""

  defp rewrite_local_id!(value, normalized_name, id_map) do
    case Map.fetch(id_map, value) do
      {:ok, rewritten_id} ->
        rewritten_id

      :error ->
        raise ArgumentError,
              "svg asset #{inspect(normalized_name)} references unknown local id #{inspect(value)}"
    end
  end

  defp rewrite_fragment_href!(value, attr_name, normalized_name, id_map) do
    trimmed_value = String.trim(value)

    cond do
      trimmed_value in ["", "#"] ->
        value

      String.starts_with?(trimmed_value, "#") ->
        target = binary_part(trimmed_value, 1, byte_size(trimmed_value) - 1)

        case Fragment.decode(target) do
          {:ok, decoded_target} ->
            rewritten_target =
              rewrite_reference_target!(decoded_target, attr_name, normalized_name, id_map)

            replace_trimmed_value(value, "##{rewritten_target}")

          :malformed ->
            value
        end

      true ->
        value
    end
  end

  defp replace_trimmed_value(value, replacement) do
    leading_size = byte_size(value) - byte_size(String.trim_leading(value))
    trailing_size = byte_size(value) - byte_size(String.trim_trailing(value))

    leading = binary_part(value, 0, leading_size)
    trailing = binary_part(value, byte_size(value) - trailing_size, trailing_size)

    IO.iodata_to_binary([leading, replacement, trailing])
  end

  defp rewrite_known_id_references(value, id_map) do
    value
    |> String.split(~r/(\s+)/u, include_captures: true, trim: false)
    |> Enum.map_join(&Map.get(id_map, &1, &1))
  end

  defp rewrite_smil_timing_references(value, id_map) do
    ids = id_map |> Map.keys() |> Enum.sort_by(&byte_size/1, :desc)

    value
    |> String.split(";", trim: false)
    |> Enum.map_join(";", &rewrite_smil_timing_reference(&1, ids, id_map))
  end

  defp rewrite_smil_timing_reference(value, ids, id_map) do
    trimmed_value = String.trim_leading(value)

    case Enum.find(ids, &String.starts_with?(trimmed_value, &1 <> ".")) do
      nil ->
        value

      id ->
        leading_size = byte_size(value) - byte_size(trimmed_value)
        leading = binary_part(value, 0, leading_size)
        rewritten = String.replace_prefix(trimmed_value, id, Map.fetch!(id_map, id))
        leading <> rewritten
    end
  end

  defp rewrite_style_node!(node, normalized_name, id_map) do
    updated_attributes =
      node
      |> xml_element(:attributes)
      |> Enum.map(&rewrite_attribute!(&1, normalized_name, id_map))

    updated_content =
      node
      |> xml_element(:content)
      |> Enum.map(&rewrite_style_content_node!(&1, normalized_name, id_map))

    xml_element(node, attributes: updated_attributes, content: updated_content)
  end

  defp rewrite_style_content_node!(node, normalized_name, id_map) do
    cond do
      xml_text_node?(node) ->
        rewrite_style_text_node!(node, normalized_name, id_map)

      xml_element_node?(node) ->
        rewrite_node!(node, normalized_name, id_map)

      true ->
        node
    end
  end

  defp rewrite_style_text_node!(node, normalized_name, id_map) do
    rewritten_content =
      node
      |> xml_text(:value)
      |> Xmerl.characters_to_binary()
      |> rewrite_style_content!(normalized_name, id_map)

    xml_text(node, value: String.to_charlist(rewritten_content))
  end

  defp rewrite_style_content!(content, normalized_name, id_map) do
    CSSRewriter.rewrite_stylesheet!(content, normalized_name, id_map)
  end

  defp rewrite_reference_target!(target, attr_name, normalized_name, id_map) do
    case Map.fetch(id_map, target) do
      {:ok, rewritten_target} ->
        rewritten_target

      :error ->
        raise ArgumentError,
              "svg asset #{inspect(normalized_name)} references unknown local id #{inspect(target)} " <>
                "from #{attr_name}"
    end
  end

  defp resolve_view_box!(attributes, normalized_name) do
    case normalize_view_box(Map.get(attributes, "viewBox")) do
      nil ->
        derive_view_box_from_dimensions!(attributes, normalized_name)

      view_box ->
        view_box
    end
  end

  defp normalize_view_box(nil), do: nil

  defp normalize_view_box(view_box) do
    case String.trim(view_box) do
      "" -> nil
      normalized_view_box -> normalized_view_box
    end
  end

  defp derive_view_box_from_dimensions!(attributes, normalized_name) do
    with {:ok, width} <- parse_view_box_dimension(Map.get(attributes, "width")),
         {:ok, height} <- parse_view_box_dimension(Map.get(attributes, "height")) do
      "0 0 #{width} #{height}"
    else
      _ ->
        raise ArgumentError,
              "svg asset #{inspect(normalized_name)} is missing a viewBox and usable width/height"
    end
  end

  defp parse_view_box_dimension(nil), do: :error

  defp parse_view_box_dimension(value) when is_binary(value) do
    case Regex.run(~r/^\s*(\d+(?:\.\d+)?)\s*(px)?\s*$/i, value) do
      [_, dimension, _unit] -> {:ok, dimension}
      [_, dimension] -> {:ok, dimension}
      _ -> :error
    end
  end

  defp parse_view_box_dimension(_value), do: :error

  defp render_content_nodes(nodes) do
    nodes
    |> :xmerl.export_simple_content(:xmerl_xml)
    |> Xmerl.characters_to_binary()
    |> String.trim()
  end

  defp render_symbol_attrs(attributes) do
    attributes
    |> symbol_attributes()
    |> Enum.sort_by(fn {name, _value} -> name end)
    |> Enum.map_join("", fn {name, value} -> ~s( #{name}="#{escape_xml_attr(value)}") end)
  end

  defp attribute_name(attribute) do
    attribute
    |> xml_attribute(:name)
    |> Atom.to_string()
  end

  defp attribute_value(attribute) do
    attribute
    |> xml_attribute(:value)
    |> Xmerl.characters_to_binary()
  end

  defp xml_element_node?(node) do
    is_tuple(node) and tuple_size(node) > 0 and elem(node, 0) == :xmlElement
  end

  defp style_element_node?(node) do
    xml_element_node?(node) and xml_element(node, :name) == :style
  end

  defp xml_text_node?(node) do
    is_tuple(node) and tuple_size(node) > 0 and elem(node, 0) == :xmlText
  end

  defp escape_xml_attr(value) do
    value
    |> HTML.html_escape()
    |> Safe.to_iodata()
    |> IO.iodata_to_binary()
  end
end
