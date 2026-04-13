defmodule Mix.Tasks.Compile.SvgSpriteExAssets do
  @moduledoc false

  use Mix.Task.Compiler

  @recursive true
  @shortdoc "Builds application SVG sprite sheets"

  alias Mix.Task.Compiler, as: TaskCompiler
  alias SvgSpriteEx.Compiler

  @impl Mix.Task.Compiler
  def run(_args) do
    register_after_elixir_hook(Compiler.default_compile_opts())
    :noop
  end

  @doc false
  def register_after_elixir_hook(opts) do
    TaskCompiler.after_compiler(:elixir, after_elixir_callback(opts))
  end

  @doc false
  def after_elixir_callback(opts) do
    fn
      {:error, diagnostics} ->
        {:error, diagnostics}

      {status, diagnostics} ->
        Compiler.compile_sprite_artifacts!(opts)
        {status, diagnostics}
    end
  end

  @impl Mix.Task.Compiler
  def manifests do
    [Compiler.manifest_path()]
  end

  @impl Mix.Task.Compiler
  def clean do
    Compiler.clean()
  end

  def compile_sprite_artifacts!(opts) do
    Compiler.compile_sprite_artifacts!(opts)
  end
end
