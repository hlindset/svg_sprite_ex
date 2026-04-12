defmodule SvgSpriteEx do
  @moduledoc """
  Public entrypoint for SvgSpriteEx in Phoenix component modules.

  `use SvgSpriteEx` imports:

  - the `<.svg>` component from `SvgSpriteEx.Svg`
  - the `sprite_ref/1`, `sprite_ref/2`, and `inline_ref/1` macros from
    `SvgSpriteEx.Ref`

  It also exposes runtime metadata APIs for compiled sprite sheets and inline
  SVGs.
  """

  alias SvgSpriteEx.Config
  alias SvgSpriteEx.InlineRef
  alias SvgSpriteEx.InlineSvgMeta
  alias SvgSpriteEx.Ref
  alias SvgSpriteEx.RuntimeData
  alias SvgSpriteEx.Source
  alias SvgSpriteEx.SpriteMeta
  alias SvgSpriteEx.SpriteRef

  @doc ~S'''
  Imports the SvgSpriteEx component and compile-time ref helpers into the caller.

  ## Examples

  ```elixir
  defmodule MyAppWeb.IconComponents do
    use Phoenix.Component
    use SvgSpriteEx

    def close_icon(assigns) do
      ~H"""
      <.svg ref={sprite_ref("regular/xmark")} class="size-4" />
      """
    end
  end
  ```
  '''
  defmacro __using__(_opts) do
    quote do
      import SvgSpriteEx.Svg
      use SvgSpriteEx.Ref
    end
  end

  @doc """
  Returns metadata for all compiled sprite sheets.
  """
  @spec sprite_sheets() :: [SvgSpriteEx.SpriteSheetMeta.t()]
  def sprite_sheets do
    with_runtime_data(:sprite_sheets, [], [])
  end

  @doc """
  Returns metadata for one compiled sprite sheet by name.
  """
  @spec sprite_sheet(String.t() | atom() | nil) :: SvgSpriteEx.SpriteSheetMeta.t() | nil
  def sprite_sheet(sheet) do
    normalized_sheet = Ref.normalize_sheet!(sheet, Config.default_sheet!())

    with_runtime_data(:sprite_sheet, [normalized_sheet], nil)
  end

  @doc """
  Returns metadata for the sprites compiled into one sprite sheet.
  """
  @spec sprites_in_sheet(String.t() | atom() | nil) :: [SvgSpriteEx.SpriteMeta.t()]
  def sprites_in_sheet(sheet) do
    normalized_sheet = Ref.normalize_sheet!(sheet, Config.default_sheet!())

    with_runtime_data(:sprites_in_sheet, [normalized_sheet], [])
  end

  @doc """
  Returns metadata for all compiled inline SVGs.
  """
  @spec inline_svgs() :: [SvgSpriteEx.InlineSvgMeta.t()]
  def inline_svgs do
    with_runtime_data(:inline_svgs, [], [])
  end

  @doc """
  Returns metadata for one compiled inline SVG by name.
  """
  @spec inline_svg(String.t()) :: SvgSpriteEx.InlineSvgMeta.t() | nil
  def inline_svg(name) do
    normalized_name = Source.normalize_name!(name, Config.source_root!())

    with_runtime_data(:inline_svg, [normalized_name], nil)
  end

  @doc """
  Converts compiled metadata into a render-time ref.
  """
  @spec to_ref(SpriteMeta.t() | InlineSvgMeta.t()) :: SpriteRef.t() | InlineRef.t()
  def to_ref(%SpriteMeta{} = sprite_meta) do
    %SpriteRef{
      name: sprite_meta.name,
      sheet: sprite_meta.sheet,
      sprite_id: sprite_meta.sprite_id,
      href: sprite_meta.href
    }
  end

  def to_ref(%InlineSvgMeta{} = inline_svg_meta) do
    %InlineRef{
      name: inline_svg_meta.name
    }
  end

  defp with_runtime_data(function_name, args, default) do
    case Code.ensure_loaded(RuntimeData) do
      {:module, RuntimeData} ->
        apply(RuntimeData, function_name, args)

      {:error, _reason} ->
        default
    end
  end
end
