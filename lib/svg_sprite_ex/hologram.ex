if Code.ensure_loaded?(Hologram.Component) do
  defmodule SvgSpriteEx.Hologram do
    @moduledoc """
    Hologram setup for compile-time sprite refs.
    """

    defmacro __using__(_opts) do
      quote do
        use SvgSpriteEx.Ref, only: :sprite
      end
    end
  end
end
