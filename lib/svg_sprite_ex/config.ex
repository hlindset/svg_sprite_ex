defmodule SvgSpriteEx.Config do
  @moduledoc false

  @source_root Application.compile_env(:svg_sprite_ex, :source_root)
  @build_path Application.compile_env(:svg_sprite_ex, :build_path)
  @public_path Application.compile_env(:svg_sprite_ex, :public_path)
  @default_sheet Application.compile_env(:svg_sprite_ex, :default_sheet, "sprites")

  @doc """
  Returns the source root used to resolve SVG assets.

  This now validates early that the configured path is nonblank and points to an
  existing directory.
  """
  def source_root! do
    fetch_directory!(@source_root, ":source_root")
  end

  @doc "Returns the build directory used for generated sprite sheets."
  def build_path! do
    fetch_binary!(@build_path, ":build_path")
  end

  @doc "Returns the public path used to reference generated sprite sheets."
  def public_path! do
    fetch_binary!(@public_path, ":public_path")
  end

  @doc "Returns the default sprite sheet name."
  def default_sheet! do
    fetch_binary!(@default_sheet, ":default_sheet")
  end

  @doc """
  Resolves a compiled public sprite path through the configured runtime static
  asset resolver.

  When no resolver is configured, the path is returned unchanged.
  """
  def resolve_public_path!(public_path) when is_binary(public_path) do
    case Application.get_env(:svg_sprite_ex, :static_path_resolver) do
      nil -> public_path
      resolver -> invoke_static_path_resolver!(resolver, public_path)
    end
  end

  def resolve_public_path!(public_path) do
    raise ArgumentError,
          "resolve_public_path!/1 expects a binary public_path, got: #{inspect(public_path)}"
  end

  defp invoke_static_path_resolver!(resolver, public_path) do
    resolved_path =
      case resolver do
        module when is_atom(module) ->
          apply_resolver!(module, :static_path, [public_path], resolver)

        {module, function} when is_atom(module) and is_atom(function) ->
          apply_resolver!(module, function, [public_path], resolver)

        {module, function, extra_args}
        when is_atom(module) and is_atom(function) and is_list(extra_args) ->
          apply_resolver!(module, function, [public_path | extra_args], resolver)

        other ->
          raise ArgumentError,
                "invalid config :svg_sprite_ex, :static_path_resolver must be a module, {module, function}, or {module, function, extra_args}, got: #{inspect(other)}"
      end

    if is_binary(resolved_path) do
      resolved_path
    else
      raise ArgumentError,
            "svg static path resolver #{inspect(resolver)} must return a binary path, got: #{inspect(resolved_path)}"
    end
  end

  defp apply_resolver!(module, function, args, resolver) do
    if function_exported?(module, function, length(args)) do
      apply(module, function, args)
    else
      raise ArgumentError,
            "svg static path resolver #{inspect(resolver)} must export #{inspect(module)}.#{function}/#{length(args)}"
    end
  end

  defp fetch_binary!(value, key) when is_binary(value) do
    if String.trim(value) == "" do
      raise ArgumentError, "invalid config :svg_sprite_ex, #{key} must not be blank"
    end

    value
  end

  defp fetch_binary!(_value, key) do
    raise ArgumentError, "missing config :svg_sprite_ex, #{key}"
  end

  defp fetch_directory!(value, key) when is_binary(value) do
    cond do
      String.trim(value) == "" ->
        raise ArgumentError, "invalid config :svg_sprite_ex, #{key} must not be blank"

      File.dir?(Path.expand(value)) ->
        value

      true ->
        raise ArgumentError,
              "invalid config :svg_sprite_ex, #{key} must point to an existing directory: #{inspect(value)}"
    end
  end

  defp fetch_directory!(_value, key) do
    raise ArgumentError, "missing config :svg_sprite_ex, #{key}"
  end
end
