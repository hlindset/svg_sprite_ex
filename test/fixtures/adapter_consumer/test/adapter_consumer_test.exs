defmodule AdapterConsumerTest do
  use ExUnit.Case, async: true

  test "only selected framework adapters are compiled" do
    mode = System.get_env("SVG_SPRITE_EX_ADAPTERS", "none")

    assert Code.ensure_loaded?(AdapterConsumer.Core)
    assert Code.ensure_loaded?(SvgSpriteEx.LiveView) == mode in ["live_view", "both"]
    assert Code.ensure_loaded?(SvgSpriteEx.LiveView.Svg) == mode in ["live_view", "both"]
    assert Code.ensure_loaded?(SvgSpriteEx.Hologram) == mode in ["hologram", "both"]
    assert Code.ensure_loaded?(SvgSpriteEx.Hologram.Svg) == mode in ["hologram", "both"]
  end
end
