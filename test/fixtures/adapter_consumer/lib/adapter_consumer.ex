defmodule AdapterConsumer.Core do
  @moduledoc false

  use SvgSpriteEx.Ref, only: :sprite

  def ref, do: sprite_ref("regular/xmark")
end

mode = System.get_env("SVG_SPRITE_EX_ADAPTERS", "none")

if mode in ["live_view", "both"] do
  defmodule AdapterConsumer.LiveView do
    use Phoenix.Component
    use SvgSpriteEx.LiveView

    def render(assigns) do
      ~H"""
      <.svg ref={sprite_ref("regular/xmark")} class="size-4" />
      """
    end
  end
end

if mode in ["hologram", "both"] do
  defmodule AdapterConsumer.Hologram do
    @moduledoc false

    use Hologram.Component
    use SvgSpriteEx.Hologram

    @impl Hologram.Component
    def template do
      ~HOLO"""
      <SvgSpriteEx.Hologram.Svg ref={sprite_ref("regular/xmark")} class="size-4" />
      """
    end
  end
end
