defmodule VerifyFetchableTransition do
  @moduledoc false

  @adapter_beams %{
    "live_view" => [
      "Elixir.SvgSpriteEx.LiveView.beam",
      "Elixir.SvgSpriteEx.LiveView.Svg.beam"
    ],
    "hologram" => [
      "Elixir.SvgSpriteEx.Hologram.beam",
      "Elixir.SvgSpriteEx.Hologram.Svg.beam"
    ]
  }
  @all_adapter_beams @adapter_beams |> Map.values() |> List.flatten()

  @doc false
  @spec run!([String.t()]) :: :ok
  def run!([from, to, no_clean_expected]) do
    verify_mode!(from)
    verify_mode!(to)
    verify_mode!(no_clean_expected)

    prepare_retained_lock!(from, to)
    run_mix!(["deps.get"], from)
    run_mix!(["compile", "--warnings-as-errors"], from)
    assert_adapter_beams!(from, "initial fetchable build")

    run_mix!(["deps.get"], to)
    run_mix_allow_failure!(["compile", "--warnings-as-errors"], to)
    assert_adapter_beams!(no_clean_expected, "no-clean fetchable transition")

    run_mix!(["deps.clean", "svg_sprite_ex", "--build"], to)
    assert_cleaned!()
    run_mix!(["compile", "--warnings-as-errors"], to)
    assert_adapter_beams!(to, "clean fetchable transition")
  end

  def run!(args) do
    raise "expected FROM, TO, and NO_CLEAN_EXPECTED adapter modes, got: #{inspect(args)}"
  end

  defp verify_mode!(mode) when mode in ["none", "live_view", "hologram", "both"], do: :ok
  defp verify_mode!(mode), do: raise("unknown adapter mode: #{inspect(mode)}")

  defp prepare_retained_lock!("none", "both"), do: run_mix!(["deps.get"], "both")
  defp prepare_retained_lock!(_from, _to), do: :ok

  defp run_mix!(args, mode) do
    case run_mix(args, mode) do
      0 -> :ok
      status -> raise "mix #{Enum.join(args, " ")} failed with status #{status}"
    end
  end

  defp run_mix_allow_failure!(args, mode) do
    status = run_mix(args, mode)
    IO.puts("no-clean compile exited with status #{status}; checking the dependency BEAMs")
  end

  defp run_mix(args, mode) do
    build_scope = System.fetch_env!("SVG_SPRITE_EX_ADAPTER_BUILD_SCOPE")

    env = [
      {"HEX_HOME",
       Path.join([System.tmp_dir!(), "svg_sprite_ex_adapter_consumer", build_scope, "hex"])},
      {"HOLOGRAM_START", "1"},
      {"MIX_ENV", "test"},
      {"SVG_SPRITE_EX_ADAPTERS", mode}
    ]

    {_output, status} =
      System.cmd("mix", args,
        env: env,
        into: IO.stream(:stdio, :line),
        stderr_to_stdout: true
      )

    status
  end

  defp assert_adapter_beams!(mode, stage) do
    expected = expected_beams(mode)
    actual = Enum.filter(@all_adapter_beams, &File.regular?(Path.join(adapter_ebin(), &1)))

    case actual do
      ^expected -> :ok
      _other -> raise "#{stage}: expected #{inspect(expected)}, got #{inspect(actual)}"
    end
  end

  defp expected_beams("none"), do: []
  defp expected_beams("live_view"), do: @adapter_beams["live_view"]
  defp expected_beams("hologram"), do: @adapter_beams["hologram"]
  defp expected_beams("both"), do: @all_adapter_beams

  defp assert_cleaned! do
    case File.dir?(adapter_ebin()) do
      false -> :ok
      true -> raise "mix deps.clean svg_sprite_ex --build left the dependency ebin directory"
    end
  end

  defp adapter_ebin do
    build_scope = System.fetch_env!("SVG_SPRITE_EX_ADAPTER_BUILD_SCOPE")

    Path.join([
      System.tmp_dir!(),
      "svg_sprite_ex_adapter_consumer",
      build_scope,
      "_build",
      "test",
      "lib",
      "svg_sprite_ex",
      "ebin"
    ])
  end
end

VerifyFetchableTransition.run!(System.argv())
