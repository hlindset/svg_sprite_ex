defmodule SvgSpriteEx.MixProjectTest do
  use ExUnit.Case, async: true

  alias SvgSpriteEx.MixProject

  test "declares the supported toolchain and optional framework ranges" do
    project = MixProject.project()
    deps = project[:deps]

    assert project[:elixir] == "~> 1.19"

    assert {:phoenix_live_view, "~> 1.0", live_view_opts} =
             Enum.find(deps, &(elem(&1, 0) == :phoenix_live_view))

    assert live_view_opts[:optional]

    assert {:hologram, "~> 0.11", hologram_opts} =
             Enum.find(deps, &(elem(&1, 0) == :hologram))

    assert hologram_opts[:optional]
  end
end
