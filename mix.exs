defmodule SvgSpriteEx.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/hlindset/svg_sprite_ex"

  def project do
    [
      app: :svg_sprite_ex,
      version: @version,
      name: "SvgSpriteEx",
      description: description(),
      package: package(),
      docs: docs(),
      source_url: @source_url,
      homepage_url: @source_url,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      test_coverage: [tool: ExCoveralls]
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.cobertura": :test
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :xmerl]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_view, "~> 1.1.0"},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:floki, "~> 0.38", only: :test},
      {:excoveralls, "~> 0.18", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false}
    ]
  end

  defp description do
    "Compile-time SVG sprite sheets and inline icon rendering for Phoenix components and LiveView."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
      },
      files: ~w(CHANGELOG.md LICENSE README.md lib mix.exs)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: ["README.md", "CHANGELOG.md"],
      groups_for_modules: [
        "Primary API": [SvgSpriteEx, SvgSpriteEx.Ref, SvgSpriteEx.Svg],
        "Ref Types": [SvgSpriteEx.InlineRef, SvgSpriteEx.SpriteRef],
        "Metadata Types": [
          SvgSpriteEx.InlineSvgMeta,
          SvgSpriteEx.SpriteMeta,
          SvgSpriteEx.SpriteSheetMeta
        ]
      ]
    ]
  end
end
