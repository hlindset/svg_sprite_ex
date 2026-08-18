defmodule SvgSpriteEx.RefEmbeddedStyleTest do
  use ExUnit.Case

  test "sprite and inline refs reject embedded style elements" do
    source_root =
      System.tmp_dir!()
      |> Path.join("svg_sprite_ex_embedded_style_#{System.unique_integer([:positive])}")
      |> Path.expand()

    asset_path = Path.join([source_root, "regular", "styled.svg"])
    File.mkdir_p!(Path.dirname(asset_path))

    File.write!(
      asset_path,
      ~s(<svg viewBox="0 0 24 24"><style>.cls-1 { fill: red }</style></svg>)
    )

    on_exit(fn -> File.rm_rf!(source_root) end)

    Enum.each(["sprite_ref", "inline_ref"], fn ref_macro ->
      module = unique_module(ref_macro)

      assert_raise CompileError, ~r/unsupported <style> element.*SVGO/, fn ->
        compile_module!(module, source_root, ref_macro)
      end
    end)
  end

  defp compile_module!(module, source_root, ref_macro) do
    path =
      System.tmp_dir!()
      |> Path.join("svg_sprite_ex_embedded_style_#{System.unique_integer([:positive])}.exs")
      |> Path.expand()

    File.write!(
      path,
      """
      defmodule #{inspect(module)} do
        use SvgSpriteEx.Ref

        @svg_sprite_ex_source_root #{inspect(source_root)}
        @svg_sprite_ex_default_sheet "sprites"
        @svg_sprite_ex_public_path "/assets/sprites"

        def ref, do: #{ref_macro}("regular/styled")
      end
      """
    )

    on_exit(fn -> File.rm_rf!(path) end)
    Code.compile_file(path)
  end

  defp unique_module(suffix) do
    Module.concat([
      SvgSpriteEx,
      RefEmbeddedStyleFixtures,
      :"#{suffix}_#{System.unique_integer([:positive])}"
    ])
  end
end
