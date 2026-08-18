defmodule SvgSpriteEx.Svg do
  @moduledoc """
  SVG rendering component.

  Use `ref={sprite_ref("regular/xmark")}` to render from a generated sprite
  sheet or `ref={inline_ref("regular/xmark")}` to inline compiled SVG data.

  Sprite refs render only the caller-provided SVG attributes. Inline refs merge
  caller attributes onto the compiled root SVG attributes and render the
  serialized child markup captured at compile time. That inner markup is passed
  through `Phoenix.HTML.raw/1` only because it is produced by the compile-time
  inline SVG pipeline and must remain a trusted boundary.
  """

  use Phoenix.Component

  alias SvgSpriteEx.Config
  alias SvgSpriteEx.InlineAsset
  alias SvgSpriteEx.InlineRef
  alias SvgSpriteEx.RuntimeData
  alias SvgSpriteEx.SpriteRef

  attr :ref, :any, default: nil
  attr :rest, :global

  @doc """
  Renders an SVG from a SvgSpriteEx ref.

  Pass a `SvgSpriteEx.SpriteRef` from `sprite_ref/1` or `sprite_ref/2` to render
  a `<use>` tag backed by a generated sprite sheet. Pass a
  `SvgSpriteEx.InlineRef` from `inline_ref/1` to inline the compiled SVG markup.

  ## Examples

      <.svg ref={sprite_ref("regular/xmark")} class="size-4" />

      <.svg ref={sprite_ref("regular/xmark", sheet: "dashboard")} class="size-4" />

      <.svg ref={sprite_ref("regular/xmark", sheet: :dashboard)} class="size-6" />

      <.svg ref={inline_ref("regular/xmark")} class="size-4" />
  """
  def svg(%{ref: %SpriteRef{}} = assigns) do
    assigns
    |> assign(:href, resolve_sprite_href!(assigns.ref))
    |> assign(:svg_attrs, assigns.rest)
    |> sprite_svg()
  end

  def svg(%{ref: %InlineRef{name: name}} = assigns) do
    {svg_attrs, inner_content} =
      name
      |> fetch_inline_asset!()
      |> inline_svg_parts(assigns.rest)

    assigns
    |> assign(:svg_attrs, svg_attrs)
    |> assign(:inner_content, inner_content)
    |> inline_svg()
  end

  def svg(%{ref: ref}) do
    raise ArgumentError,
          "svg expects ref={sprite_ref(...)} or ref={inline_ref(...)}, got ref=#{inspect(ref)}"
  end

  defp sprite_svg(assigns) do
    ~H"""
    <svg {@svg_attrs}>
      <use href={@href} />
    </svg>
    """
  end

  defp inline_svg(assigns) do
    # `@inner_content` comes from the compile-time inline SVG pipeline, so it is trusted serialized markup.
    ~H"""
    <svg {@svg_attrs}>
      {Phoenix.HTML.raw(@inner_content)}
    </svg>
    """
  end

  defp inline_svg_parts(
         %InlineAsset{attributes: attributes, inner_content: inner_content},
         svg_attrs
       ) do
    merged_attrs =
      attributes
      |> Map.put_new("xmlns", "http://www.w3.org/2000/svg")
      |> merge_attrs(svg_attrs)

    {Enum.sort_by(merged_attrs, fn {key, _value} -> key end), inner_content}
  end

  defp merge_attrs(attributes, svg_attrs) do
    Enum.reduce(svg_attrs, attributes, fn {key, value}, merged_attrs ->
      Map.put(merged_attrs, attr_key(key), value)
    end)
  end

  defp attr_key(key) when is_atom(key) do
    key
    |> Atom.to_string()
    |> String.replace("_", "-")
  end

  defp attr_key(key), do: key

  defp fetch_inline_asset!(name) do
    case RuntimeData.fetch_inline_asset(name) do
      {:ok, %InlineAsset{} = asset} ->
        asset

      :error ->
        raise ArgumentError,
              "inline svg #{inspect(name)} was compiled but could not be fetched at runtime"

      other ->
        raise ArgumentError,
              "inline svg runtime data returned an invalid result for #{inspect(name)}: #{inspect(other)}"
    end
  end

  defp resolve_sprite_href!(%SpriteRef{
         sheet_public_path: sheet_public_path,
         sprite_id: sprite_id
       })
       when is_binary(sheet_public_path) and sheet_public_path != "" and is_binary(sprite_id) and
              sprite_id != "" do
    Config.resolve_public_path!(sheet_public_path) <> "#" <> sprite_id
  end

  defp resolve_sprite_href!(%SpriteRef{} = ref) do
    raise ArgumentError,
          "sprite ref #{inspect(ref)} is missing sheet_public_path or sprite_id"
  end
end
