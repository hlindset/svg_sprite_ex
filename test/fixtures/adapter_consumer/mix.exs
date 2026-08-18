defmodule AdapterConsumer.MixProject do
  use Mix.Project

  @modes ~w(none live_view hologram both)

  def project do
    mode = mode!()
    build_scope = System.get_env("SVG_SPRITE_EX_ADAPTER_BUILD_SCOPE", mode)
    temp_root = Path.join(System.tmp_dir!(), "svg_sprite_ex_adapter_consumer/#{build_scope}")

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
    [svg_sprite_ex_dep() | adapter_deps(mode)]
  end

  defp svg_sprite_ex_dep do
    case System.get_env("SVG_SPRITE_EX_ADAPTER_DEPENDENCY_SOURCE", "path") do
      "path" ->
        {:svg_sprite_ex, path: Path.expand("../../..", __DIR__)}

      "git" ->
        {:svg_sprite_ex,
         git:
           System.get_env(
             "SVG_SPRITE_EX_ADAPTER_GIT_REPOSITORY",
             "file://#{Path.expand("../../..", __DIR__)}"
           ),
         ref: System.fetch_env!("SVG_SPRITE_EX_ADAPTER_GIT_REF")}

      source ->
        raise "unknown svg_sprite_ex dependency source: #{inspect(source)}"
    end
  end

  defp adapter_deps(mode) do
    case System.get_env("SVG_SPRITE_EX_ADAPTER_DEPENDENCY_STYLE", "direct") do
      "direct" -> direct_adapter_deps(mode)
      "transitive" -> [{:adapter_frameworks, path: Path.expand("../adapter_frameworks", __DIR__)}]
      style -> raise "unknown adapter dependency style: #{inspect(style)}"
    end
  end

  defp direct_adapter_deps("none"), do: []
  defp direct_adapter_deps("live_view"), do: [{:phoenix_live_view, "~> 1.0"}]
  defp direct_adapter_deps("hologram"), do: [{:hologram, "~> 0.11"}]

  defp direct_adapter_deps("both") do
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
