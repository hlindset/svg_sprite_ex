defmodule SvgSpriteEx.SpriteSheetTest do
  use ExUnit.Case, async: true

  alias SvgSpriteEx.Source
  alias SvgSpriteEx.SpriteSheet

  test "build escapes viewBox values in generated symbols" do
    svg_source_root = unique_tmp_dir!("view-box")
    File.mkdir_p!(Path.join(svg_source_root, "icons"))

    File.write!(
      Path.join(svg_source_root, "icons/alert.svg"),
      """
      <svg viewBox="0 0 24 24 &quot; onclick=&quot;alert(1)">
        <path d="M0 0h24v24H0z" />
      </svg>
      """
    )

    sprite_sheet = SpriteSheet.build(["icons/alert"], source_root: svg_source_root)

    assert sprite_sheet =~ "viewBox=\"0 0 24 24 &quot; onclick=&quot;alert(1)\""
    refute sprite_sheet =~ "viewBox=\"0 0 24 24 \" onclick=\"alert(1)\""
  end

  test "build escapes non-viewBox symbol attributes" do
    svg_source_root = unique_tmp_dir!("symbol-attrs")
    File.mkdir_p!(Path.join(svg_source_root, "icons"))

    File.write!(
      Path.join(svg_source_root, "icons/badge.svg"),
      """
      <svg viewBox="0 0 24 24" data-label="Tom &amp; Jerry &lt;tag&gt; &quot;double&quot; &apos;single&apos;">
        <path d="M0 0h24v24H0z" />
      </svg>
      """
    )

    sprite_sheet = SpriteSheet.build(["icons/badge"], source_root: svg_source_root)

    assert sprite_sheet =~
             "data-label=\"Tom &amp; Jerry &lt;tag&gt; &quot;double&quot; &#39;single&#39;\""

    refute sprite_sheet =~ "data-label=\"Tom & Jerry <tag> \"double\" 'single'\""
  end

  test "build returns an empty sprite sheet for empty input" do
    assert SpriteSheet.build([], source_root: unique_tmp_dir!("empty")) ==
             "<svg xmlns=\"http://www.w3.org/2000/svg\">\n</svg>\n"
  end

  test "build sorts and de-duplicates source paths" do
    svg_source_root = unique_tmp_dir!("sorted")
    File.mkdir_p!(Path.join(svg_source_root, "icons"))

    File.write!(
      Path.join(svg_source_root, "icons/alpha.svg"),
      """
      <svg viewBox="0 0 24 24">
        <path d="M1 1h22v22H1z" />
      </svg>
      """
    )

    File.write!(
      Path.join(svg_source_root, "icons/beta.svg"),
      """
      <svg viewBox="0 0 24 24" width="24" height="24" xmlns="http://www.w3.org/2000/svg">
        <path d="M2 2h20v20H2z" />
      </svg>
      """
    )

    sprite_sheet =
      SpriteSheet.build(["icons/beta", "icons/alpha", "icons/beta"],
        source_root: svg_source_root
      )

    alpha_id = Source.sprite_id("icons/alpha", svg_source_root)
    beta_id = Source.sprite_id("icons/beta", svg_source_root)

    assert count_occurrences(sprite_sheet, "<symbol id=") == 2
    assert String.contains?(sprite_sheet, ~s(<symbol id="#{alpha_id}"))
    assert String.contains?(sprite_sheet, ~s(<symbol id="#{beta_id}"))
    assert symbol_position(sprite_sheet, alpha_id) < symbol_position(sprite_sheet, beta_id)
    refute sprite_sheet =~ ~s( width="24")
    refute sprite_sheet =~ ~s( height="24")
    refute sprite_sheet =~ ~r/<symbol[^>]* xmlns=/
  end

  test "build raises for colliding generated sprite IDs before constructing symbols" do
    svg_source_root = unique_tmp_dir!("sprite-id-collision")
    first_name = "I owe Bob 14304.55 Euros. Alice."
    second_name = "I owe Bob 3632210 Euros. Alice."
    first_path = Path.join(svg_source_root, first_name <> ".svg")
    second_path = Path.join(svg_source_root, second_name <> ".svg")

    File.write!(first_path, "<svg viewBox=\"0 0 24 24\" />")
    File.write!(second_path, "<svg viewBox=\"0 0 24 24\" />")

    assert_raise ArgumentError,
                 "sprite ID collisions detected: icon-c7dee1bb8675: #{first_path}, #{second_path}",
                 fn ->
                   SpriteSheet.build([second_name, first_name], source_root: svg_source_root)
                 end
  end

  test "build de-duplicates slash, backslash, and surrounding-whitespace source aliases" do
    svg_source_root = unique_tmp_dir!("normalized-source-aliases")
    File.mkdir_p!(Path.join(svg_source_root, "icons"))

    File.write!(
      Path.join(svg_source_root, "icons/alpha.svg"),
      "<svg viewBox=\"0 0 24 24\" />"
    )

    sprite_sheet =
      SpriteSheet.build([" icons/alpha ", "icons\\alpha", "icons/alpha"],
        source_root: svg_source_root
      )

    assert count_occurrences(sprite_sheet, "<symbol id=") == 1
    assert sprite_sheet =~ ~s(<symbol id="#{Source.sprite_id("icons/alpha", svg_source_root)}")
  end

  test "build derives a viewBox from width and height when missing" do
    svg_source_root = unique_tmp_dir!("derived-viewbox")
    File.mkdir_p!(Path.join(svg_source_root, "icons"))

    File.write!(
      Path.join(svg_source_root, "icons/sized.svg"),
      """
      <svg width="24" height="16px">
        <path d="M0 0h24v16H0z" />
      </svg>
      """
    )

    sprite_sheet = SpriteSheet.build(["icons/sized"], source_root: svg_source_root)
    sprite_id = Source.sprite_id("icons/sized", svg_source_root)

    assert sprite_sheet =~ ~s(<symbol id="#{sprite_id}" viewBox="0 0 24 16")
    refute sprite_sheet =~ ~s( width="24")
    refute sprite_sheet =~ ~s( height="16px")
  end

  test "build raises when a source svg is missing a viewBox and usable width/height" do
    svg_source_root = unique_tmp_dir!("missing-viewbox")
    File.mkdir_p!(Path.join(svg_source_root, "icons"))

    File.write!(
      Path.join(svg_source_root, "icons/no_viewbox.svg"),
      """
      <svg>
        <path d="M0 0h24v24H0z" />
      </svg>
      """
    )

    assert_raise ArgumentError, ~r/is missing a viewBox and usable width\/height/, fn ->
      SpriteSheet.build(["icons/no_viewbox"], source_root: svg_source_root)
    end
  end

  test "build namespaces local ids and rewrites url-based references inside each symbol" do
    svg_source_root = unique_tmp_dir!("rewritten-refs")
    File.mkdir_p!(Path.join(svg_source_root, "icons"))

    File.write!(
      Path.join(svg_source_root, "icons/complex.svg"),
      """
      <svg viewBox="0 0 24 24">
        <defs>
          <linearGradient id="paint">
            <stop offset="0%" />
          </linearGradient>
          <clipPath id="clipper">
            <rect x="0" y="0" width="24" height="24" />
          </clipPath>
          <mask id="masker">
            <rect x="0" y="0" width="24" height="24" fill="white" />
          </mask>
          <filter id="blur">
            <feGaussianBlur stdDeviation="1" />
          </filter>
          <marker id="arrow" viewBox="0 0 10 10" refX="5" refY="5" markerWidth="6" markerHeight="6">
            <path d="M0 0 L10 5 L0 10z" />
          </marker>
        </defs>
        <path
          fill="url(#paint)"
          clip-path="url(#clipper)"
          mask="url(#masker)"
          filter="url(#blur)"
          marker-end="url(#arrow)"
          d="M2 2h20v20H2z"
        />
      </svg>
      """
    )

    sprite_sheet = SpriteSheet.build(["icons/complex"], source_root: svg_source_root)
    sprite_id = Source.sprite_id("icons/complex", svg_source_root)

    assert sprite_sheet =~ ~s(id="#{sprite_id}-paint")
    assert sprite_sheet =~ ~s(id="#{sprite_id}-clipper")
    assert sprite_sheet =~ ~s(id="#{sprite_id}-masker")
    assert sprite_sheet =~ ~s(id="#{sprite_id}-blur")
    assert sprite_sheet =~ ~s(id="#{sprite_id}-arrow")
    assert sprite_sheet =~ ~s|fill="url(##{sprite_id}-paint)"|
    assert sprite_sheet =~ ~s|clip-path="url(##{sprite_id}-clipper)"|
    assert sprite_sheet =~ ~s|mask="url(##{sprite_id}-masker)"|
    assert sprite_sheet =~ ~s|filter="url(##{sprite_id}-blur)"|
    assert sprite_sheet =~ ~s|marker-end="url(##{sprite_id}-arrow)"|
  end

  test "build rewrites root svg attributes against namespaced local ids" do
    svg_source_root = unique_tmp_dir!("root-attrs")
    File.mkdir_p!(Path.join(svg_source_root, "icons"))

    File.write!(
      Path.join(svg_source_root, "icons/root_attrs.svg"),
      """
      <svg id="root-shape" viewBox="0 0 24 24" clip-path="url(#clipper)">
        <defs>
          <clipPath id="clipper">
            <rect x="0" y="0" width="24" height="24" />
          </clipPath>
        </defs>
        <path d="M0 0h24v24H0z" />
      </svg>
      """
    )

    sprite_sheet = SpriteSheet.build(["icons/root_attrs"], source_root: svg_source_root)
    sprite_id = Source.sprite_id("icons/root_attrs", svg_source_root)

    assert sprite_sheet =~
             ~s|<symbol id="#{sprite_id}" viewBox="0 0 24 24" clip-path="url(##{sprite_id}-clipper)"|

    refute sprite_sheet =~ ~s( id="root-shape")
    assert sprite_sheet =~ ~s(id="#{sprite_id}-clipper")
  end

  test "build rewrites quoted and whitespace-padded local url references" do
    svg_source_root = unique_tmp_dir!("quoted-url-refs")
    File.mkdir_p!(Path.join(svg_source_root, "icons"))

    File.write!(
      Path.join(svg_source_root, "icons/quoted.svg"),
      """
      <svg viewBox="0 0 24 24">
        <defs>
          <linearGradient id="paint">
            <stop offset="0%" />
          </linearGradient>
          <filter id="blur">
            <feGaussianBlur stdDeviation="1" />
          </filter>
        </defs>
        <path
          fill="url('#paint')"
          stroke="url(&quot;#paint&quot;)"
          filter="url(  '#blur'  )"
          d="M2 2h20v20H2z"
        />
      </svg>
      """
    )

    sprite_sheet = SpriteSheet.build(["icons/quoted"], source_root: svg_source_root)
    sprite_id = Source.sprite_id("icons/quoted", svg_source_root)

    assert sprite_sheet =~ ~s|fill="url('##{sprite_id}-paint')"|
    assert sprite_sheet =~ ~s|stroke="url(&quot;##{sprite_id}-paint&quot;)"|
    assert sprite_sheet =~ ~s|filter="url('##{sprite_id}-blur')"|
  end

  test "build rewrites local href fragments" do
    svg_source_root = unique_tmp_dir!("href-refs")
    File.mkdir_p!(Path.join(svg_source_root, "icons"))

    File.write!(
      Path.join(svg_source_root, "icons/links.svg"),
      [
        ["<svg xmlns", ?:, "xlink=\"http://www.w3.org/1999/xlink\" viewBox=\"0 0 24 24\">\n"],
        "  <defs>\n",
        "    <g id=\"shape\">\n",
        "      <path d=\"M0 0h24v24H0z\" />\n",
        "    </g>\n",
        "  </defs>\n",
        ["  <use href=\"", ?#, "shape\" />\n"],
        ["  <use xlink", ?:, "href=\"", ?#, "shape\" />\n"],
        "</svg>\n"
      ]
    )

    sprite_sheet = SpriteSheet.build(["icons/links"], source_root: svg_source_root)
    sprite_id = Source.sprite_id("icons/links", svg_source_root)

    assert sprite_sheet =~ ~s(id="#{sprite_id}-shape")
    assert sprite_sheet =~ ~s(href="##{sprite_id}-shape")
    assert sprite_sheet =~ ~s(xlink:href="##{sprite_id}-shape")
  end

  test "build rewrites known ARIA, for, and SMIL timing ID references" do
    svg_source_root = unique_tmp_dir!("idrefs-and-timing")
    File.mkdir_p!(Path.join(svg_source_root, "icons"))

    File.write!(
      Path.join(svg_source_root, "icons/references.svg"),
      """
      <svg viewBox="0 0 24 24">
        <g id="active" />
        <g id="control" />
        <g id="description" />
        <g id="details" />
        <g id="error" />
        <g id="flow" />
        <g id="label" />
        <g id="owner" />
        <path
          id="shape"
          aria-activedescendant="active"
          aria-controls="control   external-control"
          aria-describedby="description"
          aria-details="details"
          aria-errormessage="error"
          aria-flowto="flow"
          aria-labelledby="label   description"
          aria-owns="owner"
          for="label"
        />
        <animate
          begin="shape.click; 2s; accessKey(a); shape.begin+250ms"
          end="shape.end-1s; indefinite; wallclock(2026-08-18T12:00:00Z)"
        />
      </svg>
      """
    )

    sprite_sheet = SpriteSheet.build(["icons/references"], source_root: svg_source_root)
    sprite_id = Source.sprite_id("icons/references", svg_source_root)

    assert sprite_sheet =~ ~s(aria-activedescendant="#{sprite_id}-active")
    assert sprite_sheet =~ ~s(aria-controls="#{sprite_id}-control   external-control")
    assert sprite_sheet =~ ~s(aria-describedby="#{sprite_id}-description")
    assert sprite_sheet =~ ~s(aria-details="#{sprite_id}-details")
    assert sprite_sheet =~ ~s(aria-errormessage="#{sprite_id}-error")
    assert sprite_sheet =~ ~s(aria-flowto="#{sprite_id}-flow")

    assert sprite_sheet =~
             ~s(aria-labelledby="#{sprite_id}-label   #{sprite_id}-description")

    assert sprite_sheet =~ ~s(aria-owns="#{sprite_id}-owner")
    assert sprite_sheet =~ ~s(for="#{sprite_id}-label")

    assert sprite_sheet =~
             ~s|begin="#{sprite_id}-shape.click; 2s; accessKey(a); #{sprite_id}-shape.begin+250ms"|

    assert sprite_sheet =~
             ~s|end="#{sprite_id}-shape.end-1s; indefinite; wallclock(2026-08-18T12:00:00Z)"|
  end

  test "build rewrites local URLs only in supported SVG attributes" do
    svg_source_root = unique_tmp_dir!("url-contexts")
    File.mkdir_p!(Path.join(svg_source_root, "icons"))

    File.write!(
      Path.join(svg_source_root, "icons/url_contexts.svg"),
      """
      <svg viewBox="0 0 24 24">
        <linearGradient id="paint" />
        <path
          fill="URL(#paint)"
          style="stroke: URL('#paint')"
          aria-label="url(#missing)"
          data-reference="URL(#missing)"
        />
      </svg>
      """
    )

    sprite_sheet = SpriteSheet.build(["icons/url_contexts"], source_root: svg_source_root)
    sprite_id = Source.sprite_id("icons/url_contexts", svg_source_root)

    assert sprite_sheet =~ ~s|fill="URL(##{sprite_id}-paint)"|
    assert sprite_sheet =~ ~s|style="stroke: URL('##{sprite_id}-paint')"|
    assert sprite_sheet =~ ~s|aria-label="url(#missing)"|
    assert sprite_sheet =~ ~s|data-reference="URL(#missing)"|
  end

  test "build rewrites CSS references according to lexical context" do
    svg_source_root = unique_tmp_dir!("css-reference-contexts")
    File.mkdir_p!(Path.join(svg_source_root, "icons"))

    File.write!(
      Path.join(svg_source_root, "icons/css_references.svg"),
      """
      <svg viewBox="0 0 24 24">
        <linearGradient id="paint" />
        <filter id="blur" />
        <path id="shape.icon" />
        <path id="fff" />
        <style>
          /* URL(#paint) and #shape\\.icon stay literal */
          #shape\\.icon::before {
            content: "URL(#paint) and #shape\\.icon";
            fill: URL(#paint);
          }
          [href="#shape.icon"], [xlink\\:href='#shape.icon'] { filter: url('#blur'); }
          [data-reference="#shape.icon"] { color: #fff; }
          .group {
            #shape\\.icon { stroke: url(#paint); }
          }
          @scope (#shape\\.icon) to (#fff) {
            [href="#shape.icon"] { fill: url(#paint); }
          }
          @supports selector([xlink\\:href='#shape.icon']) {
            #shape\\.icon { filter: URL(#blur); }
          }
          @keyframes pulse {
            from { color: #fff; }
            to { color: #fff; }
          }
          #fff { fill: #fff; }
        </style>
      </svg>
      """
    )

    sprite_sheet = SpriteSheet.build(["icons/css_references"], source_root: svg_source_root)
    sprite_id = Source.sprite_id("icons/css_references", svg_source_root)

    assert sprite_sheet =~ "/* URL(#paint) and #shape\\.icon stay literal */"
    assert sprite_sheet =~ ~s|content: "URL(#paint) and #shape\\.icon";|

    assert sprite_sheet =~
             "##{sprite_id}-shape\\.icon::before"

    assert sprite_sheet =~ ~s|fill: URL(##{sprite_id}-paint);|

    assert sprite_sheet =~
             ~s|[href="##{sprite_id}-shape.icon"], [xlink\\:href='##{sprite_id}-shape.icon']|

    assert sprite_sheet =~ ~s|filter: url('##{sprite_id}-blur');|
    assert sprite_sheet =~ ~s|[data-reference="#shape.icon"] { color: #fff; }|
    assert sprite_sheet =~ ".group {\n      ##{sprite_id}-shape\\.icon"

    assert sprite_sheet =~
             "@scope (##{sprite_id}-shape\\.icon) to (##{sprite_id}-fff)"

    assert sprite_sheet =~
             "@supports selector([xlink\\:href='##{sprite_id}-shape.icon'])"

    assert sprite_sheet =~ "@keyframes pulse"
    assert sprite_sheet =~ "from { color: #fff; }"
    assert sprite_sheet =~ "to { color: #fff; }"
    assert sprite_sheet =~ "##{sprite_id}-fff { fill: #fff; }"
  end

  test "build preserves an empty href fragment" do
    svg_source_root = unique_tmp_dir!("empty-href-fragment")
    File.mkdir_p!(Path.join(svg_source_root, "icons"))

    File.write!(
      Path.join(svg_source_root, "icons/empty_href.svg"),
      """
      <svg viewBox="0 0 24 24">
        <use href="#" />
      </svg>
      """
    )

    sprite_sheet = SpriteSheet.build(["icons/empty_href"], source_root: svg_source_root)

    assert sprite_sheet =~ ~s(href="#")
  end

  test "build strips exactly one hash from non-empty href fragments" do
    svg_source_root = unique_tmp_dir!("double-href-fragment")
    File.mkdir_p!(Path.join(svg_source_root, "icons"))

    File.write!(
      Path.join(svg_source_root, "icons/double_href.svg"),
      """
      <svg viewBox="0 0 24 24">
        <path id="shape" />
        <use href="##shape" />
      </svg>
      """
    )

    assert_raise ArgumentError, ~r/unknown local id "#shape" from href/, fn ->
      SpriteSheet.build(["icons/double_href"], source_root: svg_source_root)
    end
  end

  test "build rewrites style block selectors and local url references" do
    svg_source_root = unique_tmp_dir!("style-blocks")
    File.mkdir_p!(Path.join(svg_source_root, "icons"))

    File.write!(
      Path.join(svg_source_root, "icons/styled.svg"),
      """
      <svg viewBox="0 0 24 24">
        <defs>
          <linearGradient id="paint">
            <stop offset="0%" />
          </linearGradient>
        </defs>
        <style>
          #shape { fill: url(#paint); }
        </style>
        <path id="shape" d="M0 0h24v24H0z" />
      </svg>
      """
    )

    sprite_sheet = SpriteSheet.build(["icons/styled"], source_root: svg_source_root)
    sprite_id = Source.sprite_id("icons/styled", svg_source_root)

    assert sprite_sheet =~ "##{sprite_id}-shape { fill: url(##{sprite_id}-paint); }"
    assert sprite_sheet =~ ~s(id="#{sprite_id}-shape")
    assert sprite_sheet =~ ~s(id="#{sprite_id}-paint")
  end

  test "build does not rewrite colors that match local ids in style declarations" do
    svg_source_root = unique_tmp_dir!("style-colors")
    File.mkdir_p!(Path.join(svg_source_root, "icons"))

    File.write!(
      Path.join(svg_source_root, "icons/style_colors.svg"),
      """
      <svg viewBox="0 0 24 24">
        <style>
          #fff { fill: #fff; }
        </style>
        <path id="fff" d="M0 0h24v24H0z" />
      </svg>
      """
    )

    sprite_sheet = SpriteSheet.build(["icons/style_colors"], source_root: svg_source_root)
    sprite_id = Source.sprite_id("icons/style_colors", svg_source_root)

    assert sprite_sheet =~ "##{sprite_id}-fff { fill: #fff; }"
  end

  test "build does not rewrite local-id text in style comments or strings" do
    svg_source_root = unique_tmp_dir!("style-comments-and-strings")
    File.mkdir_p!(Path.join(svg_source_root, "icons"))

    File.write!(
      Path.join(svg_source_root, "icons/style_text.svg"),
      """
      <svg viewBox="0 0 24 24">
        <style>
          /* keep #shape */
          #shape::before { content: "#shape"; }
        </style>
        <path id="shape" d="M0 0h24v24H0z" />
      </svg>
      """
    )

    sprite_sheet = SpriteSheet.build(["icons/style_text"], source_root: svg_source_root)
    sprite_id = Source.sprite_id("icons/style_text", svg_source_root)

    assert sprite_sheet =~ "/* keep #shape */"
    assert sprite_sheet =~ ~s(##{sprite_id}-shape::before { content: "#shape"; })
  end

  test "build passes through non-local reference forms unchanged" do
    svg_source_root = unique_tmp_dir!("unsupported-refs")
    File.mkdir_p!(Path.join(svg_source_root, "icons"))

    File.write!(
      Path.join(svg_source_root, "icons/external.svg"),
      """
      <svg viewBox="0 0 24 24">
        <defs>
          <g id="shape">
            <path d="M0 0h24v24H0z" />
          </g>
        </defs>
        <path fill="url(http://example.com/pattern.svg#paint)" d="M0 0h24v24H0z" />
        <use href="other.svg#shape" />
      </svg>
      """
    )

    sprite_sheet = SpriteSheet.build(["icons/external"], source_root: svg_source_root)

    assert sprite_sheet =~ ~s|fill="url(http://example.com/pattern.svg#paint)"|
    assert sprite_sheet =~ ~s(href="other.svg#shape")
  end

  test "build still raises for missing local reference targets" do
    svg_source_root = unique_tmp_dir!("missing-local-refs")
    File.mkdir_p!(Path.join(svg_source_root, "icons"))

    File.write!(
      Path.join(svg_source_root, "icons/broken.svg"),
      """
      <svg viewBox="0 0 24 24">
        <path fill="url(#paint)" d="M0 0h24v24H0z" />
      </svg>
      """
    )

    assert_raise ArgumentError, ~r/references unknown local id/, fn ->
      SpriteSheet.build(["icons/broken"], source_root: svg_source_root)
    end
  end

  defp count_occurrences(haystack, needle) do
    haystack
    |> String.split(needle)
    |> length()
    |> Kernel.-(1)
  end

  defp symbol_position(sprite_sheet, sprite_id) do
    sprite_sheet
    |> :binary.match(~s(<symbol id="#{sprite_id}"))
    |> elem(0)
  end

  defp unique_tmp_dir!(suffix) do
    path =
      System.tmp_dir!()
      |> Path.join("svg_sprite_ex_test_#{suffix}_#{System.unique_integer([:positive])}")
      |> Path.expand()

    File.mkdir_p!(path)
    ExUnit.Callbacks.on_exit(fn -> File.rm_rf!(path) end)
    path
  end
end
