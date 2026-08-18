defmodule AdapterConsumer.MixProject do
  use Mix.Project

  @modes ~w(none live_view hologram both)

  def project do
    mode = mode!()
    temp_root = Path.join(System.tmp_dir!(), "svg_sprite_ex_adapter_consumer/#{mode}")

    [
      app: :adapter_consumer,
      version: "0.1.0",
      elixir: "~> 1.19",
      build_path: Path.join(temp_root, "_build"),
      deps_path: Path.join(temp_root, "deps"),
      lockfile: Path.join(temp_root, "mix.lock"),
      compilers: compilers(mode),
      deps: deps(mode)
    ]
  end

  def application, do: [extra_applications: [:logger]]

  def cli, do: [preferred_envs: [do: :test]]

  defp deps(mode) do
    [{:svg_sprite_ex, path: Path.expand("../../..", __DIR__)} | adapter_deps(mode)]
  end

  defp adapter_deps("none"), do: []
  defp adapter_deps("live_view"), do: [{:phoenix_live_view, "~> 1.0"}]
  defp adapter_deps("hologram"), do: [{:hologram, "~> 0.11"}]

  defp adapter_deps("both") do
    [{:phoenix_live_view, "~> 1.0"}, {:hologram, "~> 0.11"}]
  end

  defp compilers(mode) when mode in ["hologram", "both"] do
    [:svg_sprite_ex_assets] ++ Mix.compilers() ++ [:hologram]
  end

  defp compilers(_mode), do: [:svg_sprite_ex_assets] ++ Mix.compilers()

  defp mode! do
    mode = System.get_env("SVG_SPRITE_EX_ADAPTERS", "none")

    if mode in @modes do
      mode
    else
      raise "SVG_SPRITE_EX_ADAPTERS must be one of #{Enum.join(@modes, ", ")}, got: #{inspect(mode)}"
    end
  end
end
