defmodule SvgSpriteEx.OptionalDependencies.LocalPath.HologramSvg do
  @moduledoc false

  require SvgSpriteEx.OptionalDependencies
  SvgSpriteEx.OptionalDependencies.track_local_dependency(:hologram)
end

if :hologram in Mix.Project.deps_apps() and
     Code.ensure_loaded?(Hologram.Component) do
  defmodule SvgSpriteEx.Hologram.Svg do
    @moduledoc """
    Hologram component for a compiled `SvgSpriteEx.SpriteRef`.

    The component accepts `class`, `width`, `height`, `color`, `fill`, `stroke`,
    and `aria_label` props. A non-nil `aria_label` gives the rendered SVG an
    image role; otherwise it is hidden from assistive technology.

    This component is sprite-only and does not accept `SvgSpriteEx.InlineRef`.
    Use `SvgSpriteEx.LiveView.Svg` when inline rendering is required.

    To build the `<use>` href, the component strips exactly one leading slash
    from `SvgSpriteEx.SpriteRef.sheet_public_path`, when present, and resolves
    the result through Hologram's asset registry. The registry has no fallback:
    it raises `Hologram.AssetNotFoundError` when the path is not registered.
    The component then appends `#` and the ref's sprite ID to the resolved path.
    """

    use Hologram.Component

    alias SvgSpriteEx.SpriteRef

    prop(:ref, :any)
    prop(:class, :string, default: nil)
    prop(:width, [:integer, :string], default: nil)
    prop(:height, [:integer, :string], default: nil)
    prop(:color, :string, default: nil)
    prop(:fill, :string, default: nil)
    prop(:stroke, :string, default: nil)
    prop(:aria_label, :string, default: nil)

    @impl Hologram.Component
    def template do
      ~HOLO"""
      <svg
        class={@class}
        width={@width}
        height={@height}
        color={@color}
        fill={@fill}
        stroke={@stroke}
        role={role(@aria_label)}
        aria-label={@aria_label}
        aria-hidden={aria_hidden(@aria_label)}
      >
        <use href={sprite_href(@ref)} />
      </svg>
      """
    end

    defp sprite_href(%SpriteRef{sheet_public_path: "/" <> asset_path, sprite_id: sprite_id}) do
      asset_path(asset_path) <> "#" <> sprite_id
    end

    defp sprite_href(%SpriteRef{sheet_public_path: asset_path, sprite_id: sprite_id}) do
      asset_path(asset_path) <> "#" <> sprite_id
    end

    defp role(nil), do: nil
    defp role(_aria_label), do: "img"

    defp aria_hidden(nil), do: "true"
    defp aria_hidden(_aria_label), do: nil
  end
end
