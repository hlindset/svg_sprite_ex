defmodule AdapterFrameworks.MixProject do
  use Mix.Project

  def project do
    [
      app: :adapter_frameworks,
      version: "0.1.0",
      elixir: "~> 1.19",
      deps: deps(System.get_env("SVG_SPRITE_EX_ADAPTERS", "none"))
    ]
  end

  def application, do: []

  defp deps("none"), do: []
  defp deps("live_view"), do: [{:phoenix_live_view, "~> 1.0"}]
  defp deps("hologram"), do: [{:hologram, "~> 0.11"}]
  defp deps("both"), do: [{:phoenix_live_view, "~> 1.0"}, {:hologram, "~> 0.11"}]
end
