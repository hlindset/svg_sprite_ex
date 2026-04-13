defmodule SvgSpriteEx.Source do
  @moduledoc false

  require Record

  @enforce_keys [:name, :file_path, :attributes, :inner_content, :content_nodes]
  defstruct [:name, :file_path, :attributes, :inner_content, :content_nodes]

  @type t :: %__MODULE__{
          name: String.t(),
          file_path: String.t(),
          attributes: %{optional(String.t()) => String.t()},
          inner_content: String.t(),
          content_nodes: [term()]
        }

  Record.defrecordp(
    :xml_attribute,
    Record.extract(:xmlAttribute, from_lib: "xmerl/include/xmerl.hrl")
  )

  Record.defrecordp(
    :xml_element,
    Record.extract(:xmlElement, from_lib: "xmerl/include/xmerl.hrl")
  )

  @sprite_id_prefix "icon-"
  @sprite_id_hash_length 12
  @xmerl_scan_opts [quiet: true]

  @doc """
  Reads and parses an SVG asset from `source_root`.

  `name` must be a logical sprite name, not a filesystem path. The name is
  trimmed, slash-normalized, validated to stay within the source root, and then
  resolved to an existing `.svg` file.
  """
  @spec read!(String.t(), String.t()) :: t()
  def read!(name, source_root) when is_binary(name) and is_binary(source_root) do
    source_root = validate_source_root_directory!(source_root)
    normalized_name = normalize_name!(name, source_root)
    file_path = source_file_path_from_normalized!(normalized_name, source_root)

    %{attributes: attributes, inner_content: inner_content, content_nodes: content_nodes} =
      parse_svg_file!(file_path)

    %__MODULE__{
      name: normalized_name,
      file_path: file_path,
      attributes: attributes,
      inner_content: inner_content,
      content_nodes: content_nodes
    }
  end

  def read!(name, source_root) do
    raise ArgumentError,
          "read!/2 expects binary name and source_root, got: #{inspect(name)} and #{inspect(source_root)}"
  end

  @doc """
  Normalizes and validates a logical SVG asset name.

  The returned name is trimmed, uses forward slashes, and is guaranteed to stay
  within `source_root`. `source_root` is only checked for presence here; the
  file lookup entrypoints also require it to be an existing directory. Dots are
  allowed in path segments; only a trailing `.svg` suffix is rejected.
  """
  @spec normalize_name!(String.t(), String.t()) :: String.t()
  def normalize_name!(name, source_root) when is_binary(name) and is_binary(source_root) do
    validate_source_root_present!(source_root)

    normalized_name =
      name
      |> String.trim()
      |> String.replace("\\", "/")

    cond do
      normalized_name == "" ->
        raise ArgumentError, "svg asset name cannot be blank"

      String.contains?(normalized_name, ["?", "#"]) ->
        raise ArgumentError,
              "svg asset name must not include query params or fragments: #{inspect(name)}"

      trailing_svg_extension?(normalized_name) ->
        raise ArgumentError,
              "svg asset names must omit the trailing .svg extension: #{inspect(name)}"

      true ->
        safe_name!(normalized_name, source_root, name)
    end
  end

  def normalize_name!(name, source_root) do
    raise ArgumentError,
          "normalize_name!/2 expects binary name and source_root, got: #{inspect(name)} and #{inspect(source_root)}"
  end

  @doc """
  Resolves a logical SVG asset name to an existing file path under `source_root`.

  This accepts raw logical names or already normalized logical names.
  """
  @spec source_file_path!(String.t(), String.t()) :: String.t()
  def source_file_path!(name, source_root) when is_binary(name) and is_binary(source_root) do
    source_root = validate_source_root_directory!(source_root)
    normalized_name = normalize_name!(name, source_root)
    source_file_path_from_normalized!(normalized_name, source_root)
  end

  def source_file_path!(name, source_root) do
    raise ArgumentError,
          "source_file_path!/2 expects binary name and source_root, got: #{inspect(name)} and #{inspect(source_root)}"
  end

  defp source_file_path_from_normalized!(normalized_name, source_root)
       when is_binary(normalized_name) and is_binary(source_root) do
    source_file_path_from_normalized_impl!(normalized_name, source_root)
  end

  defp source_file_path_from_normalized!(normalized_name, source_root) do
    raise ArgumentError,
          "source_file_path_from_normalized!/2 expects binary normalized_name and source_root, got: #{inspect(normalized_name)} and #{inspect(source_root)}"
  end

  @doc """
  Returns the stable sprite id for a logical SVG asset name.
  """
  @spec sprite_id(String.t(), String.t()) :: String.t()
  def sprite_id(name, source_root) when is_binary(name) and is_binary(source_root) do
    normalized_name = normalize_name!(name, source_root)
    sprite_id_from_normalized(normalized_name)
  end

  def sprite_id(name, source_root) do
    raise ArgumentError,
          "sprite_id/2 expects binary name and source_root, got: #{inspect(name)} and #{inspect(source_root)}"
  end

  @doc false
  @spec sprite_id_from_normalized(String.t()) :: String.t()
  def sprite_id_from_normalized(normalized_name) when is_binary(normalized_name) do
    hash =
      :crypto.hash(:sha256, normalized_name)
      |> Base.encode16(case: :lower)
      |> binary_part(0, @sprite_id_hash_length)

    @sprite_id_prefix <> hash
  end

  def sprite_id_from_normalized(normalized_name) do
    raise ArgumentError,
          "sprite_id_from_normalized/1 expects a binary normalized_name, got: #{inspect(normalized_name)}"
  end

  defp source_file_path_from_normalized_impl!(normalized_name, source_root) do
    file_path = Path.join(source_root, normalized_name <> ".svg")

    if File.regular?(file_path) do
      file_path
    else
      raise ArgumentError,
            "svg asset could not be resolved under the configured source root: #{inspect(normalized_name)}"
    end
  end

  defp parse_svg_file!(file_path) do
    file_path
    |> File.read!()
    |> parse_svg_document!(file_path)
  end

  defp parse_svg_document!(svg_document, file_path) do
    root = parse_xml_document!(svg_document, file_path)

    if xml_element(root, :name) == :svg do
      %{
        attributes: parse_attributes(xml_element(root, :attributes)),
        inner_content: render_inner_content(root),
        content_nodes: xml_element(root, :content)
      }
    else
      raise ArgumentError, "svg asset #{inspect(file_path)} does not contain a valid <svg> root"
    end
  end

  defp parse_xml_document!(svg_document, file_path) do
    svg_document
    |> String.to_charlist()
    |> :xmerl_scan.string(@xmerl_scan_opts)
    |> elem(0)
  catch
    :exit, {:fatal, reason} ->
      raise ArgumentError,
            "svg asset #{inspect(file_path)} does not contain valid XML: #{inspect(reason)}"
  end

  defp parse_attributes(attributes) do
    Enum.reduce(attributes, %{}, fn attribute, parsed_attrs ->
      Map.put(
        parsed_attrs,
        attribute_name(attribute),
        attribute_value(attribute)
      )
    end)
  end

  defp render_inner_content(root) do
    root
    |> xml_element(:content)
    |> :xmerl.export_simple_content(:xmerl_xml)
    |> IO.iodata_to_binary()
    |> String.trim()
  end

  defp attribute_name(attribute) do
    attribute
    |> xml_attribute(:name)
    |> Atom.to_string()
  end

  defp attribute_value(attribute) do
    attribute
    |> xml_attribute(:value)
    |> IO.iodata_to_binary()
  end

  defp safe_name!(name, source_root, original_name) do
    case Path.safe_relative(name, source_root) do
      {:ok, safe_name} when safe_name != "" ->
        String.replace(safe_name, "\\", "/")

      _ ->
        raise ArgumentError,
              "svg asset name must stay within the configured source root: #{inspect(original_name)}"
    end
  end

  defp trailing_svg_extension?(name) when is_binary(name) do
    String.ends_with?(String.downcase(name), ".svg")
  end

  defp validate_source_root_present!(source_root) do
    if String.trim(source_root) == "" do
      raise ArgumentError, "svg source_root cannot be blank"
    end

    source_root
  end

  defp validate_source_root_directory!(source_root) do
    cond do
      String.trim(source_root) == "" ->
        raise ArgumentError, "svg source_root cannot be blank"

      File.dir?(Path.expand(source_root)) ->
        source_root

      true ->
        raise ArgumentError,
              "svg source_root must point to an existing directory: #{inspect(source_root)}"
    end
  end
end
