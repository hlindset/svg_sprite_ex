defmodule SvgSpriteEx.MetadataTest do
  use ExUnit.Case

  alias Mix.Tasks.Compile.SvgSpriteExAssets
  alias SvgSpriteEx.Config
  alias SvgSpriteEx.SpriteInfo
  alias SvgSpriteEx.SpriteSheetInfo
  alias SvgSpriteEx.InlineSvgInfo

  test "sprite metadata APIs expose compiled sprite sheets and sprites" do
    {source_dir, manifest_path, compile_path, sprite_build_path} = runtime_fixture_paths!()

    write_sprite_fixture_module!(source_dir, unique_module(:alerts_fixture), sheet: "alerts")

    write_sprite_fixture_module!(source_dir, unique_module(:ui_actions_fixture),
      sheet: :" UI Actions "
    )

    compile_runtime_metadata!(manifest_path, source_dir, compile_path, sprite_build_path)

    assert [
             %SpriteSheetInfo{name: "alerts", filename: "alerts.svg"},
             %SpriteSheetInfo{name: "ui_actions", filename: "ui_actions.svg"}
           ] = SvgSpriteEx.sprite_sheets()

    assert {:ok, %SpriteSheetInfo{name: "ui_actions"} = sheet_info} =
             SvgSpriteEx.sprite_sheet(:" UI Actions ")

    assert sheet_info.build_path == Path.join(sprite_build_path, "ui_actions.svg")
    assert sheet_info.public_path == "/assets/sprites/ui_actions.svg"

    assert [
             %SpriteInfo{
               name: "regular/xmark",
               sheet: "ui_actions",
               source_path: source_path,
               sprite_id: sprite_id,
               href: href
             }
           ] = SvgSpriteEx.sprites_in_sheet(:" UI Actions ")

    assert source_path == Path.join(Config.source_root!(), "regular/xmark.svg")
    assert href == "/assets/sprites/ui_actions.svg##{sprite_id}"
    assert SvgSpriteEx.sprite_sheet("missing") == :error
    assert SvgSpriteEx.sprites_in_sheet("missing") == []
  end

  test "inline svg metadata APIs expose compiled inline svgs" do
    {source_dir, manifest_path, compile_path, sprite_build_path} = runtime_fixture_paths!()

    write_inline_fixture_module!(source_dir, unique_module(:inline_fixture),
      name: "regular/xmark"
    )

    write_inline_fixture_module!(source_dir, unique_module(:duplicate_inline_fixture),
      name: "regular/xmark"
    )

    compile_runtime_metadata!(manifest_path, source_dir, compile_path, sprite_build_path)

    assert [
             %InlineSvgInfo{name: "regular/xmark", source_path: source_path}
           ] = SvgSpriteEx.inline_svgs()

    assert source_path == Path.join(Config.source_root!(), "regular/xmark.svg")

    assert {:ok, %InlineSvgInfo{name: "regular/xmark", source_path: ^source_path}} =
             SvgSpriteEx.inline_svg(" regular\\xmark ")

    assert SvgSpriteEx.inline_svg("regular/missing") == :error
  end

  defp compile_runtime_metadata!(manifest_path, source_dir, compile_path, sprite_build_path) do
    unload_generated_modules()
    Code.prepend_path(compile_path)

    on_exit(fn ->
      unload_generated_modules()
      Code.delete_path(compile_path)
    end)

    assert :ok = compile_fixture_modules!(manifest_path, source_dir, compile_path)

    assert :ok =
             SvgSpriteExAssets.compile_sprite_artifacts!(
               compile_path: compile_path,
               elixir_manifest_path: manifest_path,
               build_path: sprite_build_path,
               public_path: Config.public_path!(),
               source_root: Config.source_root!()
             )
  end

  defp unload_generated_modules do
    for module <- [
          SvgSpriteEx.Generated.InlineIcons,
          SvgSpriteEx.Generated.InlineSvgs,
          SvgSpriteEx.Generated.SpriteSheets
        ] do
      :code.purge(module)
      :code.delete(module)
    end

    :ok
  end

  defp compile_fixture_modules!(manifest_path, source_dir, compile_path) do
    case Mix.Compilers.Elixir.compile(
           manifest_path,
           [source_dir],
           compile_path,
           {:svg_sprite_ex_test, source_dir},
           [],
           [],
           []
         ) do
      {:ok, _diagnostics} ->
        :ok

      {:noop, _diagnostics} ->
        :ok

      {:error, diagnostics} ->
        flunk("fixture modules failed to compile: #{inspect(diagnostics)}")
    end
  end

  defp write_sprite_fixture_module!(source_dir, module, opts) do
    sheet = Keyword.fetch!(opts, :sheet)
    source_path = fixture_source_path(source_dir, module)

    File.write!(
      source_path,
      """
      defmodule #{inspect(module)} do
        use SvgSpriteEx.Ref

        def sprite_ref_fixture, do: sprite_ref("regular/xmark", sheet: #{inspect(sheet)})
      end
      """
    )

    source_path
  end

  defp write_inline_fixture_module!(source_dir, module, opts) do
    name = Keyword.fetch!(opts, :name)
    source_path = fixture_source_path(source_dir, module)

    File.write!(
      source_path,
      """
      defmodule #{inspect(module)} do
        use SvgSpriteEx.Ref

        def inline_ref_fixture, do: inline_ref(#{inspect(name)})
      end
      """
    )

    source_path
  end

  defp runtime_fixture_paths! do
    source_dir = unique_tmp_dir!("runtime-source-dir")
    compile_path = unique_tmp_dir!("runtime-compile-path")
    sprite_build_path = unique_tmp_dir!("runtime-sprite-build-path")
    manifest_path = elixir_manifest_path!(source_dir)
    {source_dir, manifest_path, compile_path, sprite_build_path}
  end

  defp fixture_source_path(source_dir, module) do
    Path.join(source_dir, "#{Atom.to_string(module)}.ex")
  end

  defp elixir_manifest_path!(source_dir) do
    manifest_dir = Path.join(source_dir, ".mix")
    File.mkdir_p!(manifest_dir)
    Path.join(manifest_dir, "compile.elixir")
  end

  defp unique_module(suffix) do
    Module.concat([
      SvgSpriteEx,
      MetadataFixtures,
      :"#{suffix}_#{System.unique_integer([:positive])}"
    ])
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
