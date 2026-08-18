defmodule AdapterConsumerTest do
  use ExUnit.Case, async: true

  @mode System.get_env("SVG_SPRITE_EX_ADAPTERS", "none")

  test "only selected framework adapters are compiled" do
    assert Code.ensure_loaded?(AdapterConsumer.Core)
    assert Code.ensure_loaded?(SvgSpriteEx.LiveView) == @mode in ["live_view", "both"]
    assert Code.ensure_loaded?(SvgSpriteEx.LiveView.Svg) == @mode in ["live_view", "both"]
    assert Code.ensure_loaded?(SvgSpriteEx.Hologram) == @mode in ["hologram", "both"]
    assert Code.ensure_loaded?(SvgSpriteEx.Hologram.Svg) == @mode in ["hologram", "both"]
    assert Code.ensure_loaded?(AdapterConsumer.HologramLayout) == @mode in ["hologram", "both"]
    assert Code.ensure_loaded?(AdapterConsumer.HologramPage) == @mode in ["hologram", "both"]
  end

  if @mode in ["hologram", "both"] do
    alias Hologram.Router.Helpers, as: HologramRouterHelpers

    test "Hologram compiles the sprite asset and a page bundle" do
      sprite_path = Path.join(Mix.Project.app_path(), "priv/static/assets/sprites/sprites.svg")
      page_bundle_pattern = Path.join(Mix.Project.app_path(), "priv/static/hologram/page-*.js")

      assert File.stat!(sprite_path).size > 0

      assert HologramRouterHelpers.asset_path("assets/sprites/sprites.svg") ==
               "/assets/sprites/sprites.svg"

      assert [page_bundle] = Path.wildcard(page_bundle_pattern)
      assert File.stat!(page_bundle).size > 0

      page_bundle_js = File.read!(page_bundle)

      assert page_bundle_js =~ ~s("SvgSpriteEx.Hologram.Svg")
      assert page_bundle_js =~ "regular/xmark"
      assert page_bundle_js =~ "/assets/sprites/sprites.svg"
    end
  end
end
