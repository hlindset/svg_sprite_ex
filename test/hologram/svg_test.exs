if Code.ensure_loaded?(Hologram.Component) do
  defmodule SvgSpriteEx.Hologram.SvgTest do
    use ExUnit.Case

    alias Hologram.Commons.ETS
    alias Hologram.Template.Renderer
    alias SvgSpriteEx.Hologram.Svg
    alias SvgSpriteEx.InlineRef
    alias SvgSpriteEx.SpriteRef

    defmodule AssetPathRegistry do
      def ets_table_name, do: __MODULE__
    end

    setup do
      previous = Application.get_env(:hologram, :asset_path_registry_impl)
      ETS.create_named_table(AssetPathRegistry.ets_table_name())

      ETS.put(
        AssetPathRegistry.ets_table_name(),
        "assets/sprites/sprites.svg",
        "/assets/sprites/sprites-a1b2c3.svg"
      )

      Application.put_env(:hologram, :asset_path_registry_impl, AssetPathRegistry)

      on_exit(fn ->
        ETS.delete(AssetPathRegistry.ets_table_name())

        if is_nil(previous) do
          Application.delete_env(:hologram, :asset_path_registry_impl)
        else
          Application.put_env(:hologram, :asset_path_registry_impl, previous)
        end
      end)
    end

    test "renders a digested sprite href and native SVG props" do
      html =
        render_svg(
          ref: sprite_ref(),
          class: "size-4",
          width: 16,
          height: "1em",
          color: "red",
          fill: "none",
          stroke: "currentColor",
          aria_label: "Search"
        )

      {:ok, document} = Floki.parse_document(html)
      [svg] = Floki.find(document, "svg")
      attrs = svg |> elem(1) |> Map.new()

      assert attrs["class"] == "size-4"
      assert attrs["width"] == "16"
      assert attrs["height"] == "1em"
      assert attrs["color"] == "red"
      assert attrs["fill"] == "none"
      assert attrs["stroke"] == "currentColor"
      assert attrs["role"] == "img"
      assert attrs["aria-label"] == "Search"
      refute Map.has_key?(attrs, "aria-hidden")

      assert Floki.attribute(document, "use", "href") == [
               "/assets/sprites/sprites-a1b2c3.svg#sprite-search"
             ]
    end

    test "marks an unlabelled sprite as decorative" do
      html = render_svg(ref: sprite_ref())
      {:ok, document} = Floki.parse_document(html)
      [svg] = Floki.find(document, "svg")
      attrs = svg |> elem(1) |> Map.new()

      assert attrs["aria-hidden"] == "true"
      refute Map.has_key?(attrs, "aria-label")
      refute Map.has_key?(attrs, "role")
    end

    test "rejects inline refs" do
      assert_raise FunctionClauseError, fn ->
        render_svg(ref: %InlineRef{name: "regular/xmark"})
      end
    end

    test "raises Hologram's asset error when the sprite sheet is not registered" do
      ref = %{sprite_ref() | sheet_public_path: "/assets/sprites/missing.svg"}

      assert_raise Hologram.AssetNotFoundError, fn ->
        render_svg(ref: ref)
      end
    end

    defp sprite_ref do
      %SpriteRef{
        name: "regular/search",
        sheet: "sprites",
        sheet_public_path: "/assets/sprites/sprites.svg",
        sprite_id: "sprite-search"
      }
    end

    defp render_svg(props) do
      props_dom =
        Enum.map(props, fn {name, value} ->
          {Atom.to_string(name), [expression: {value}]}
        end)

      {html, _registry, _server} =
        Renderer.render_dom(
          {:component, Svg, props_dom, []},
          %Renderer.Env{},
          %Hologram.Server{}
        )

      html
    end
  end
end
