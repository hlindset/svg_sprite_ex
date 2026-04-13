defmodule Test.Support.CompileHelpers do
  import ExUnit.Assertions, only: [flunk: 1]
  import ExUnit.CaptureIO, only: [capture_io: 1]

  def compile_fixture_modules!(manifest_path, source_dir, compile_path) do
    override = compiler_state_path(manifest_path)
    previous_override = Application.get_env(:svg_sprite_ex, :compiler_state_path_override)
    Application.put_env(:svg_sprite_ex, :compiler_state_path_override, override)

    try do
      {result, output} =
        capture_result(fn ->
          # Note: This intentionally uses Mix's internal compile/7 API for test
          # infrastructure. If the signature changes on Elixir upgrade, update this
          # helper.
          Mix.Compilers.Elixir.compile(
            manifest_path,
            [source_dir],
            compile_path,
            {:svg_sprite_ex_test, source_dir},
            [],
            [],
            []
          )
        end)

      case result do
        {:ok, _diagnostics} ->
          :ok

        {:noop, _diagnostics} ->
          :ok

        {:error, diagnostics} ->
          flunk("""
          fixture modules failed to compile: #{inspect(diagnostics)}

          #{output}
          """)
      end
    after
      if is_nil(previous_override) do
        Application.delete_env(:svg_sprite_ex, :compiler_state_path_override)
      else
        Application.put_env(:svg_sprite_ex, :compiler_state_path_override, previous_override)
      end
    end
  end

  def compiler_state_path(manifest_path) do
    manifest_path
    |> Path.dirname()
    |> Path.join("svg_sprite_ex")
  end

  def capture_result(fun) do
    parent = self()
    ref = make_ref()

    output =
      capture_io(fn ->
        send(parent, {:captured_result, ref, fun.()})
      end)

    result =
      receive do
        {:captured_result, ^ref, result} -> result
      end

    {result, output}
  end
end
