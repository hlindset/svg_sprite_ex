defmodule SpriteEx.SvgTest do
  use ExUnit.Case
  use Phoenix.Component
  use SpriteEx

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias SpriteEx.InlineRef
  alias SpriteEx.Svg

  defmodule InlineRegistryFixture do
    alias SpriteEx.InlineAsset

    def fetch("icons/alert") do
      {:ok,
       %InlineAsset{
         attributes: %{"viewBox" => "0 0 24 24"},
         inner_content: "<path d=\"M0 0h24v24H0z\" />"
       }}
    end

    def fetch(_name), do: :error
  end

  defmodule InvalidInlineRegistryFixture do
    def fetch("icons/bad"), do: {:ok, :invalid}
  end

  test "loads the module" do
    assert Code.ensure_loaded?(SpriteEx)
  end

  test "use SpriteEx imports svg rendering and sprite refs" do
    html = render_component(&sprite_wrapper/1, %{})

    assert html =~ ~s(<svg class="size-4")

    assert html =~
             ~s(<use href="#{SpriteEx.Ref.sprite_href("regular/xmark", "/test/fixtures/icons", SpriteEx.Config.default_sheet!(), "/assets/sprites")}")

    refute html =~ "aria-hidden"
  end

  test "svg/1 renders inline svg markup from an inline ref and merges attrs" do
    html =
      render_component(&Svg.svg/1,
        ref: %InlineRef{name: "icons/alert", registry: InlineRegistryFixture},
        class: "size-5",
        aria_hidden: "true",
        data_role: "icon"
      )

    {:ok, document} = Floki.parse_document(html)
    [svg] = Floki.find(document, "svg")
    {"svg", attrs, _children} = svg
    [path] = Floki.find(svg, "path")
    {"path", _path_attrs, _path_children} = path
    attrs = Map.new(attrs)

    assert attrs["aria-hidden"] == "true"
    assert attrs["class"] == "size-5"
    assert attrs["data-role"] == "icon"
    assert attrs["xmlns"] == "http://www.w3.org/2000/svg"
    assert path
  end

  test "wrapper components can pass either sprite or inline refs through a single ref attr" do
    sprite_html = render_component(&passthrough_wrapper/1, icon: sprite_ref("regular/xmark"))

    inline_html =
      render_component(&passthrough_wrapper/1,
        icon: %InlineRef{name: "icons/alert", registry: InlineRegistryFixture}
      )

    assert sprite_html =~ "<use href="
    assert inline_html =~ "<path"
  end

  test "svg/1 raises when ref is missing" do
    assert_raise ArgumentError, ~r/expects ref=\{sprite_ref/, fn ->
      render_component(&Svg.svg/1, %{})
    end
  end

  test "svg/1 raises for non-ref values" do
    assert_raise ArgumentError, ~r/expects ref=\{sprite_ref/, fn ->
      render_component(&Svg.svg/1, ref: "regular/xmark")
    end
  end

  test "svg/1 raises when an inline ref cannot be fetched from its registry" do
    assert_raise ArgumentError, ~r/could not be fetched at runtime/, fn ->
      render_component(&Svg.svg/1,
        ref: %InlineRef{name: "icons/missing", registry: InlineRegistryFixture}
      )
    end
  end

  test "svg/1 raises when an inline registry returns an invalid result" do
    assert_raise ArgumentError, ~r/returned an invalid result/, fn ->
      render_component(&Svg.svg/1,
        ref: %InlineRef{name: "icons/bad", registry: InvalidInlineRegistryFixture}
      )
    end
  end

  def sprite_wrapper(assigns) do
    ~H"""
    <.svg ref={sprite_ref("regular/xmark")} class="size-4" />
    """
  end

  def passthrough_wrapper(assigns) do
    ~H"""
    <.svg ref={@icon} class="size-4" />
    """
  end
end
