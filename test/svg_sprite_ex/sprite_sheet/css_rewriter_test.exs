defmodule SvgSpriteEx.SpriteSheet.CSSRewriterTest do
  use ExUnit.Case, async: true

  alias SvgSpriteEx.SpriteSheet.CSSRewriter

  @asset_name "icons/css_references"
  @id_map %{
    "-1" => "sprite--1",
    "123" => "sprite-123",
    "paint" => "sprite-paint",
    "café" => "sprite-café",
    "shape" => "sprite-shape",
    "shape.icon" => "sprite-shape.icon",
    "shape{part" => "sprite-shape{part",
    "shape;part" => "sprite-shape;part",
    "shape[part" => "sprite-shape[part",
    "shape}part" => "sprite-shape}part"
  }

  describe "rewrite_stylesheet!/3 URL tokens" do
    test "rewrites decoded URL function names and decoded fragment targets" do
      css =
        ~S|a { first: u\72l(#paint); second: url("\23 paint"); third: url(\23 paint); }|

      expected =
        ~S|a { first: u\72l(#sprite-paint); second: url("#sprite-paint"); third: url(#sprite-paint); }|

      assert rewrite(css) == expected
    end

    test "reports an unknown decoded local fragment target" do
      assert_raise ArgumentError,
                   ~r/svg asset "icons\/css_references" references unknown local id "missing" from style/,
                   fn ->
                     rewrite(~S|a { fill: url("\23 missing"); }|)
                   end

      assert_raise ArgumentError,
                   ~r/svg asset "icons\/css_references" references unknown local id "missing" from style/,
                   fn ->
                     rewrite(~S|a { fill: url(\23 missing); }|)
                   end
    end

    test "decodes quoted URL string line continuations" do
      Enum.each(["\n", "\r", "\f", "\r\n"], fn newline ->
        css = "a { fill: url(\"#pa\\#{newline}int\"); }"

        assert rewrite(css) == ~S|a { fill: url("#sprite-paint"); }|
      end)
    end

    test "does not treat whitespace-separated identifiers or at-keywords as URL functions" do
      css =
        ~S|a { first: url (#paint); second: @url(#paint); third: u\72l (#paint); fourth: @u\72l(#paint); fifth: url(#paint); }|

      expected =
        ~S|a { first: url (#paint); second: @url(#paint); third: u\72l (#paint); fourth: @u\72l(#paint); fifth: url(#sprite-paint); }|

      assert rewrite(css) == expected
    end

    test "preserves bad URLs, non-CSS whitespace, and trailing invalid escapes" do
      escaped_newline = "a { fill: url(#paint\\\n); }"
      non_css_whitespace = "a { fill: url(#paint\u00A0); }"
      invalid_character = ~S|a { fill: url(#paint"suffix); }|
      trailing_escape = "a { fill: url(#paint\\"

      assert rewrite(escaped_newline) == escaped_newline
      assert rewrite(non_css_whitespace) == non_css_whitespace
      assert rewrite(invalid_character) == invalid_character
      assert rewrite(trailing_escape) == trailing_escape
    end

    test "treats comment-looking bytes as unquoted URL data" do
      css = """
      a{fill:url(/*x*/#paint)}
      a{fill:url(/**/"#paint")}
      a{fill:url(#paint/**/)}
      """

      assert rewrite(css) == css
    end

    test "does not diagnose comment-bearing unquoted URLs as local fragments" do
      css = """
      a{fill:url(/*x*/#missing)}
      a{fill:url(/**/"#missing")}
      a{fill:url(#missing/**/)}
      """

      assert rewrite(css) == css
    end

    test "recovers from a bad URL before rewriting later rules" do
      css = """
      a{fill:url(#paint"bad)} #shape{color:#fff}
      a{fill:url(#paint"bad\\)still-bad)} #shape{color:#fff}
      """

      expected = """
      a{fill:url(#paint"bad)} #sprite-shape{color:#fff}
      a{fill:url(#paint"bad\\)still-bad)} #sprite-shape{color:#fff}
      """

      assert rewrite(css) == expected
    end

    test "preserves comment trivia in a quoted URL function" do
      css = ~S|a{fill:url("#paint"/**/)}|

      assert rewrite(css) == ~S|a{fill:url("#sprite-paint"/**/)}|
    end

    test "decodes percent-encoded local URL fragments" do
      css = ~S|a{fill:url(#shape%2Eicon)} b{fill:url("#shape%2eicon")} c{fill:url(#caf%C3%A9)}|

      expected =
        ~S|a{fill:url(#sprite-shape\.icon)} b{fill:url("#sprite-shape.icon")} c{fill:url(#sprite-café)}|

      assert rewrite(css) == expected
    end

    test "preserves malformed percent encodings as non-local URL data" do
      css = ~S|a{fill:url(#paint%2)} b{fill:url("#paint%GG")}|

      assert rewrite(css) == css
    end
  end

  describe "rewrite_stylesheet!/3 bad string tokens" do
    test "recovers after an unescaped newline in a quoted URL" do
      Enum.each(["\n", "\r", "\f"], fn newline ->
        css = "a{fill:url(\"#paint#{newline})} #shape{color:#fff}"
        expected = "a{fill:url(\"#paint#{newline})} #sprite-shape{color:#fff}"

        assert rewrite(css) == expected
      end)
    end

    test "recovers after an unescaped newline in an ordinary string" do
      Enum.each(["\n", "\r", "\f"], fn newline ->
        css = "a{content:\"literal#{newline}} #shape{color:#fff}"
        expected = "a{content:\"literal#{newline}} #sprite-shape{color:#fff}"

        assert rewrite(css) == expected
      end)
    end
  end

  describe "rewrite_stylesheet!/3 selector tokens" do
    test "consumes escaped structural delimiters before classifying rule structure" do
      css = """
      #shape\\{part { color:#fff; }
      #shape\\;part { color:#fff; }
      #shape\\[part { color:#fff; }
      #shape\\}part { color:#fff; }
      """

      expected = """
      #sprite-shape\\{part { color:#fff; }
      #sprite-shape\\;part { color:#fff; }
      #sprite-shape\\[part { color:#fff; }
      #sprite-shape\\}part { color:#fff; }
      """

      assert rewrite(css) == expected
    end

    test "rewrites href selectors with namespace syntax and comment trivia" do
      css = """
      @namespace xlink url(http://www.w3.org/1999/xlink);
      [xlink|href="#shape"]{color:#fff}
      [href/**/="#shape"]{color:#fff}
      [href /*a*/ = /*b*/ "#shape"]{color:#fff}
      """

      expected = """
      @namespace xlink url(http://www.w3.org/1999/xlink);
      [xlink|href="#sprite-shape"]{color:#fff}
      [href/**/="#sprite-shape"]{color:#fff}
      [href /*a*/ = /*b*/ "#sprite-shape"]{color:#fff}
      """

      assert rewrite(css) == expected
    end

    test "rewrites escaped selector function names only at function-token boundaries" do
      css = """
      @supports sel\\65 ctor(#shape) { #shape { color:#fff; } }
      @supports selector (#shape) { #shape { color:#fff; } }
      @supports @selector(#shape) { #shape { color:#fff; } }
      @supports sel\\65 ctor (#shape) { #shape { color:#fff; } }
      @supports @sel\\65 ctor(#shape) { #shape { color:#fff; } }
      """

      expected = """
      @supports sel\\65 ctor(#sprite-shape) { #sprite-shape { color:#fff; } }
      @supports selector (#shape) { #sprite-shape { color:#fff; } }
      @supports @selector(#shape) { #sprite-shape { color:#fff; } }
      @supports sel\\65 ctor (#shape) { #sprite-shape { color:#fff; } }
      @supports @sel\\65 ctor(#shape) { #sprite-shape { color:#fff; } }
      """

      assert rewrite(css) == expected
    end

    test "preserves malformed adjacent hashes and invalid trailing escapes" do
      adjacent_hashes = "##shape { color:#fff; }"
      comment_separated_hashes = "#/**/#shape { color:#fff; }"
      invalid_escape = "#shape\\\n { color:#fff; }"

      assert rewrite(adjacent_hashes) == adjacent_hashes
      assert rewrite(comment_separated_hashes) == comment_separated_hashes
      assert rewrite(invalid_escape) == invalid_escape
    end

    test "rewrites only hash tokens with the CSS id flag" do
      css = ~S|#123{color:#fff} #-1{color:#fff} #\31 23{color:#fff} #\-1{color:#fff}|

      expected =
        ~S|#123{color:#fff} #-1{color:#fff} #sprite-123{color:#fff} #sprite--1{color:#fff}|

      assert rewrite(css) == expected
    end

    test "preserves comments around an attribute namespace separator" do
      css = """
      [xlink/**/|/**/href="#shape"]{x:y}
      [xlink |href="#shape"]{x:y}
      [xlink| href="#shape"]{x:y}
      """

      expected = """
      [xlink/**/|/**/href="#sprite-shape"]{x:y}
      [xlink |href="#shape"]{x:y}
      [xlink| href="#shape"]{x:y}
      """

      assert rewrite(css) == expected
    end

    test "decodes percent-encoded href selector fragments" do
      css = ~S([href="#shape%2Eicon"], [xlink|href='#caf%c3%a9']{color:#fff})

      expected = ~S([href="#sprite-shape.icon"], [xlink|href='#sprite-café']{color:#fff})

      assert rewrite(css) == expected
    end

    test "preserves balanced blocks inside custom property values" do
      css = """
      #shape { --tokens: #shape {}; color: #shape; }
      @media (width > 1px) { #shape { --tokens: #shape { nested: #shape; }; color: #shape; } }
      @keyframes pulse { from { --tokens: #shape {}; color: #shape; } }
      """

      expected = """
      #sprite-shape { --tokens: #shape {}; color: #shape; }
      @media (width > 1px) { #sprite-shape { --tokens: #shape { nested: #shape; }; color: #shape; } }
      @keyframes pulse { from { --tokens: #shape {}; color: #shape; } }
      """

      assert rewrite(css) == expected
    end
  end

  defp rewrite(css), do: CSSRewriter.rewrite_stylesheet!(css, @asset_name, @id_map)
end
