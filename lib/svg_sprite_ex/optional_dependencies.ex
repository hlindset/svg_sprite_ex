defmodule SvgSpriteEx.OptionalDependencies do
  @moduledoc false

  @doc false
  defmacro track_local_dependency(app) when is_atom(app) do
    active? = app in Mix.Project.deps_apps()

    quote do
      @optional_dependency_active unquote(active?)

      # Mix reaches dependency compiler callbacks only after selecting the
      # dependency for compilation. This supports local path transitions;
      # fetchable dependencies require the documented clean rebuild.
      @doc false
      def __mix_recompile__? do
        unquote(app) in Mix.Project.deps_apps() != @optional_dependency_active
      end
    end
  end
end
