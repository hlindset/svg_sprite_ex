defmodule SvgSpriteEx.SpriteSheet.LocalUrlRewriterTest do
  use ExUnit.Case, async: true

  alias SvgSpriteEx.SpriteSheet.LocalUrlRewriter

  @asset "icons/styled"
  @id_map %{"paint" => "icon-abc-paint", "café" => "icon-abc-café"}

  test "rewrites canonical local URL fragments without interpreting declarations" do
    input =
      ~S|fill:URL( #paint );stroke:url('#paint');--paint:url("#caf%C3%A9");content:"url(#missing)";color:#fff|

    expected =
      ~S|fill:URL( #icon-abc-paint );stroke:url('#icon-abc-paint');--paint:url("#icon-abc-caf%C3%A9");content:"url(#missing)";color:#fff|

    assert rewrite(input) == expected
  end

  test "preserves non-local and empty URL values" do
    input = ~S|a:url(icons.svg#paint);b:url("data:image/svg+xml,%3Csvg%3E");c:url()|

    assert rewrite(input) == input
  end

  test "matches only a whole URL function name without intervening whitespace" do
    input = ~S|a:myurl(#paint);b:url (#paint);c:URL(#paint);d:éurl(#paint)|

    assert rewrite(input) ==
             ~S|a:myurl(#paint);b:url (#paint);c:URL(#icon-abc-paint);d:éurl(#paint)|
  end

  test "preserves mixed ASCII whitespace around URL values" do
    input = "fill:url(\t#paint \r\n)"

    assert rewrite(input) == "fill:url(\t#icon-abc-paint \r\n)"
  end

  test "reports unknown local fragment targets" do
    assert_raise ArgumentError,
                 ~r/svg asset "icons\/styled" references unknown local id "missing" from style/,
                 fn -> rewrite("fill:url(#missing)") end
  end

  test "rejects CSS comments" do
    assert_unsupported("fill:/* comment */url(#paint)", "CSS comments")
    assert_unsupported(~S|content:"/* still a comment token */"|, "CSS comments")
  end

  test "rejects CSS backslash escapes" do
    assert_unsupported(~S|fill:u\72l(#paint)|, "backslash escapes")
    assert_unsupported(~S|fill:url(\23 paint)|, "backslash escapes")
    assert_unsupported(~S|content:"escaped\ string"|, "backslash escapes")
  end

  test "rejects malformed strings and URL functions" do
    assert_unsupported(~S|content:"unclosed|, "unclosed string")
    assert_unsupported("content:\"line\nbreak\"", "malformed string")
    assert_unsupported("fill:url(#paint", "unclosed url()")
    assert_unsupported(~S|fill:url("#paint" extra)|, "malformed url()")
    assert_unsupported(~S|fill:url(#paint"extra)|, "malformed url()")
    assert_unsupported("fill:url(foo(bar))", "malformed url()")
  end

  test "rejects ambiguous or malformed local fragments" do
    assert_unsupported("fill:url(#)", "ambiguous local fragment")
    assert_unsupported("fill:url(##paint)", "ambiguous local fragment")
    assert_unsupported("fill:url(#paint%23suffix)", "ambiguous local fragment")
    assert_unsupported("fill:url(#paint%GG)", "malformed local fragment")
  end

  defp rewrite(content) do
    LocalUrlRewriter.rewrite!(content, @asset, @id_map, "style")
  end

  defp assert_unsupported(content, reason) do
    assert_raise ArgumentError, ~r/unsupported CSS in style: #{Regex.escape(reason)}.*SVGO/, fn ->
      rewrite(content)
    end
  end
end
