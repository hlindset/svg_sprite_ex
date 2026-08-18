defmodule SvgSpriteEx.OptionalDependencies.LocalPath.LiveView do
  @moduledoc false

  require SvgSpriteEx.OptionalDependencies
  SvgSpriteEx.OptionalDependencies.track_local_dependency(:phoenix_live_view)
end

if :phoenix_live_view in Mix.Project.deps_apps() and
     Code.ensure_loaded?(Phoenix.Component) do
  defmodule SvgSpriteEx.LiveView do
    @moduledoc ~S'''
    Phoenix LiveView setup for SvgSpriteEx refs and the `<.svg>` component.

    Use this module in a Phoenix component, LiveView, or HTML module to import
    `SvgSpriteEx.Ref` and `SvgSpriteEx.LiveView.Svg`:

        defmodule MyAppWeb.IconComponents do
          use Phoenix.Component
          use SvgSpriteEx.LiveView

          def search_icon(assigns) do
            ~H"""
            <.svg ref={sprite_ref("regular/search")} class="size-4" />
            """
          end
        end
    '''

    defmacro __using__(_opts) do
      quote do
        use SvgSpriteEx.Ref
        import SvgSpriteEx.LiveView.Svg
      end
    end
  end
end
