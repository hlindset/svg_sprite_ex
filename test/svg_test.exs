defmodule SvgSpriteEx.SvgTest do
  use ExUnit.Case
  use Phoenix.Component
  use SvgSpriteEx

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias SvgSpriteEx.InlineAsset
  alias SvgSpriteEx.InlineRef
  alias SvgSpriteEx.Svg

  @runtime_data_cache_key {SvgSpriteEx.RuntimeData, :runtime_data}

  defmodule StaticPathResolver do
    def static_path(path), do: "/digested#{path}?vsn=123"
  end

  test "loads the module" do
    assert Code.ensure_loaded?(SvgSpriteEx)
  end

  test "use SvgSpriteEx imports svg rendering and sprite refs" do
    html = render_component(&sprite_wrapper/1, %{})

    assert html =~ ~s(<svg class="size-4")

    assert html =~
             ~s(<use href="#{SvgSpriteEx.Ref.sprite_href("regular/xmark", "/test/fixtures/icons", SvgSpriteEx.Config.default_sheet!(), "/assets/sprites")}")

    refute html =~ "aria-hidden"
  end

  test "svg/1 renders inline svg markup from an inline ref and merges attrs" do
    put_runtime_data(%{
      "icons/alert" => %InlineAsset{
        attributes: %{"viewBox" => "0 0 24 24"},
        inner_content: "<path d=\"M0 0h24v24H0z\" />"
      }
    })

    html =
      render_component(&Svg.svg/1,
        ref: %InlineRef{name: "icons/alert"},
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

    put_runtime_data(%{
      "icons/alert" => %InlineAsset{
        attributes: %{},
        inner_content: "<path d=\"M0 0h24v24H0z\" />"
      }
    })

    inline_html =
      render_component(&passthrough_wrapper/1,
        icon: %InlineRef{name: "icons/alert"}
      )

    assert sprite_html =~ "<use href="
    assert inline_html =~ "<path"
  end

  test "svg/1 resolves sprite sheet hrefs through the configured static path resolver" do
    previous_resolver = Application.get_env(:svg_sprite_ex, :static_path_resolver)
    Application.put_env(:svg_sprite_ex, :static_path_resolver, StaticPathResolver)

    on_exit(fn ->
      if is_nil(previous_resolver) do
        Application.delete_env(:svg_sprite_ex, :static_path_resolver)
      else
        Application.put_env(:svg_sprite_ex, :static_path_resolver, previous_resolver)
      end
    end)

    html = render_component(&sprite_wrapper/1, %{})

    assert html =~ ~s(<use href="/digested/assets/sprites/sprites.svg?vsn=123#)
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

  test "svg/1 raises when an inline ref cannot be fetched at runtime" do
    put_runtime_data(%{})

    assert_raise ArgumentError, ~r/could not be fetched at runtime/, fn ->
      render_component(&Svg.svg/1, ref: %InlineRef{name: "icons/missing"})
    end
  end

  test "svg/1 raises when runtime data returns an invalid result" do
    :persistent_term.put(@runtime_data_cache_key, %{
      data: %{inline_assets: %{"icons/bad" => :invalid}}
    })

    on_exit(fn -> :persistent_term.erase(@runtime_data_cache_key) end)

    assert_raise ArgumentError, ~r/returned an invalid result/, fn ->
      render_component(&Svg.svg/1, ref: %InlineRef{name: "icons/bad"})
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

  defp put_runtime_data(inline_assets) do
    :persistent_term.put(@runtime_data_cache_key, %{data: %{inline_assets: inline_assets}})
    on_exit(fn -> :persistent_term.erase(@runtime_data_cache_key) end)
  end
end
