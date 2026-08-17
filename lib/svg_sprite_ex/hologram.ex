if Code.ensure_loaded?(Hologram.Component) do
  defmodule SvgSpriteEx.Hologram do
    @moduledoc ~S'''
    Hologram setup for compile-time sprite refs.

    Use this module with `Hologram.Component` and render refs through the
    `SvgSpriteEx.Hologram.Svg` module component:

    ```elixir
    defmodule MyApp.Components do
      use Hologram.Component
      use SvgSpriteEx.Hologram

      @impl Hologram.Component
      def template do
        ~HOLO"""
        <SvgSpriteEx.Hologram.Svg
          ref={sprite_ref("regular/search")}
          class="size-4"
          aria_label="Search"
        />
        """
      end
    end
    ```

    This adapter imports only `SvgSpriteEx.Ref.sprite_ref/1` and
    `SvgSpriteEx.Ref.sprite_ref/2`. Hologram does not accept
    `SvgSpriteEx.InlineRef`.
    '''

    defmacro __using__(_opts) do
      quote do
        use SvgSpriteEx.Ref, only: :sprite
      end
    end
  end
end
