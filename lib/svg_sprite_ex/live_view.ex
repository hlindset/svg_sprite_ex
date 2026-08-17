if Code.ensure_loaded?(Phoenix.Component) do
  defmodule SvgSpriteEx.LiveView do
    @moduledoc """
    Phoenix LiveView setup for SvgSpriteEx refs and the `<.svg>` component.
    """

    defmacro __using__(_opts) do
      quote do
        use SvgSpriteEx.Ref
        import SvgSpriteEx.LiveView.Svg
      end
    end
  end
end
