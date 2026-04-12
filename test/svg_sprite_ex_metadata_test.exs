defmodule SvgSpriteEx.MetadataTest do
  use ExUnit.Case

  alias Mix.Tasks.Compile.SvgSpriteExAssets
  alias SvgSpriteEx.Config
  alias SvgSpriteEx.InlineRef
  alias SvgSpriteEx.InlineSvgMeta
  alias SvgSpriteEx.SpriteRef
  alias SvgSpriteEx.SpriteMeta
  alias SvgSpriteEx.SpriteSheetMeta

  test "sprite metadata APIs expose compiled sprite sheets and sprites" do
    {source_dir, manifest_path, compile_path, sprite_build_path} = runtime_fixture_paths!()

    write_sprite_fixture_module!(source_dir, unique_module(:alerts_fixture), sheet: "alerts")

    write_sprite_fixture_module!(source_dir, unique_module(:ui_actions_fixture),
      sheet: :" UI Actions "
    )

    compile_runtime_metadata!(manifest_path, source_dir, compile_path, sprite_build_path)

    assert [
             %SpriteSheetMeta{name: "alerts", filename: "alerts.svg"},
             %SpriteSheetMeta{name: "ui_actions", filename: "ui_actions.svg"}
           ] = SvgSpriteEx.sprite_sheets()

    assert %SpriteSheetMeta{name: "ui_actions"} =
             sheet_info =
             SvgSpriteEx.sprite_sheet(:" UI Actions ")

    assert sheet_info.build_path == Path.join(sprite_build_path, "ui_actions.svg")
    assert sheet_info.public_path == "/assets/sprites/ui_actions.svg"

    assert [
             %SpriteMeta{
               name: "regular/xmark",
               sheet: "ui_actions",
               source_path: source_path,
               sprite_id: sprite_id,
               href: href
             }
           ] = SvgSpriteEx.sprites_in_sheet(:" UI Actions ")

    assert source_path == Path.join(Config.source_root!(), "regular/xmark.svg")
    assert href == "/assets/sprites/ui_actions.svg##{sprite_id}"
    assert SvgSpriteEx.sprite_sheet("missing") == nil
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
             %InlineSvgMeta{name: "regular/xmark", source_path: source_path}
           ] = SvgSpriteEx.inline_svgs()

    assert source_path == Path.join(Config.source_root!(), "regular/xmark.svg")

    assert %InlineSvgMeta{name: "regular/xmark", source_path: ^source_path} =
             SvgSpriteEx.inline_svg(" regular\\xmark ")

    assert SvgSpriteEx.inline_svg("regular/missing") == nil
  end

  test "metadata can be converted back into render-time refs" do
    {source_dir, manifest_path, compile_path, sprite_build_path} = runtime_fixture_paths!()

    write_sprite_fixture_module!(source_dir, unique_module(:sprite_ref_fixture), sheet: "alerts")

    write_inline_fixture_module!(source_dir, unique_module(:inline_ref_fixture),
      name: "regular/xmark"
    )

    compile_runtime_metadata!(manifest_path, source_dir, compile_path, sprite_build_path)

    assert [%SpriteMeta{} = sprite_meta] = SvgSpriteEx.sprites_in_sheet("alerts")
    assert %InlineSvgMeta{} = inline_svg_meta = SvgSpriteEx.inline_svg("regular/xmark")

    assert %SpriteRef{} = sprite_ref = SvgSpriteEx.to_ref(sprite_meta)
    assert sprite_ref.name == sprite_meta.name
    assert sprite_ref.sheet == sprite_meta.sheet
    assert sprite_ref.sprite_id == sprite_meta.sprite_id
    assert sprite_ref.href == sprite_meta.href

    assert %InlineRef{} = inline_ref = SvgSpriteEx.to_ref(inline_svg_meta)
    assert inline_ref.name == inline_svg_meta.name
    assert inline_ref.registry == SvgSpriteEx.Generated.InlineIcons
  end

  test "runtime metadata merges artifacts from multiple app code paths" do
    {source_dir_one, manifest_path_one, compile_path_one, sprite_build_path_one} =
      runtime_fixture_paths!()

    {source_dir_two, manifest_path_two, compile_path_two, sprite_build_path_two} =
      runtime_fixture_paths!()

    write_sprite_fixture_module!(source_dir_one, unique_module(:umbrella_alerts_fixture),
      sheet: "alerts"
    )

    write_sprite_fixture_module!(source_dir_two, unique_module(:umbrella_dashboard_fixture),
      sheet: "dashboard"
    )

    write_inline_fixture_module!(source_dir_two, unique_module(:umbrella_inline_fixture),
      name: "regular/xmark"
    )

    setup_runtime_loader!([compile_path_one, compile_path_two])

    assert :ok =
             compile_runtime_metadata_app!(
               manifest_path_one,
               source_dir_one,
               compile_path_one,
               sprite_build_path_one
             )

    assert :ok =
             compile_runtime_metadata_app!(
               manifest_path_two,
               source_dir_two,
               compile_path_two,
               sprite_build_path_two
             )

    clear_runtime_data_cache()

    assert [
             %SpriteSheetMeta{name: "alerts", filename: "alerts.svg"},
             %SpriteSheetMeta{name: "dashboard", filename: "dashboard.svg"}
           ] = SvgSpriteEx.sprite_sheets()

    assert [%SpriteMeta{sheet: "alerts", name: "regular/xmark"}] =
             SvgSpriteEx.sprites_in_sheet("alerts")

    assert [%SpriteMeta{sheet: "dashboard", name: "regular/xmark"}] =
             SvgSpriteEx.sprites_in_sheet("dashboard")

    assert [%InlineSvgMeta{name: "regular/xmark"}] = SvgSpriteEx.inline_svgs()
    assert %InlineSvgMeta{name: "regular/xmark"} = SvgSpriteEx.inline_svg("regular/xmark")
    assert File.exists?(runtime_data_path(compile_path_one))
    assert File.exists?(runtime_data_path(compile_path_two))
  end

  test "runtime metadata cache reloads after compiler updates artifacts" do
    {source_dir, manifest_path, compile_path, sprite_build_path} = runtime_fixture_paths!()

    write_sprite_fixture_module!(source_dir, unique_module(:runtime_cache_alerts_fixture),
      sheet: "alerts"
    )

    setup_runtime_loader!([compile_path])

    assert :ok =
             compile_runtime_metadata_app!(
               manifest_path,
               source_dir,
               compile_path,
               sprite_build_path
             )

    assert [%SpriteSheetMeta{name: "alerts"}] = SvgSpriteEx.sprite_sheets()

    write_sprite_fixture_module!(source_dir, unique_module(:runtime_cache_dashboard_fixture),
      sheet: "dashboard"
    )

    assert :ok =
             compile_runtime_metadata_app!(
               manifest_path,
               source_dir,
               compile_path,
               sprite_build_path
             )

    assert [
             %SpriteSheetMeta{name: "alerts"},
             %SpriteSheetMeta{name: "dashboard"}
           ] = SvgSpriteEx.sprite_sheets()
  end

  defp compile_runtime_metadata!(manifest_path, source_dir, compile_path, sprite_build_path) do
    setup_runtime_loader!([compile_path])
    compile_runtime_metadata_app!(manifest_path, source_dir, compile_path, sprite_build_path)
  end

  defp unload_generated_modules do
    for module <- [
          SvgSpriteEx.Generated.InlineIcons,
          SvgSpriteEx.Generated.InlineSvgs,
          SvgSpriteEx.Generated.SpriteSheets
        ] do
      :code.delete(module)
      :code.purge(module)
    end

    :ok
  end

  defp clear_runtime_data_cache do
    SvgSpriteEx.Generated.RuntimeData.delete()
  end

  defp setup_runtime_loader!(compile_paths) do
    unload_generated_modules()
    clear_runtime_data_cache()

    Enum.each(compile_paths, &Code.prepend_path/1)

    on_exit(fn ->
      unload_generated_modules()
      clear_runtime_data_cache()

      Enum.each(compile_paths, &Code.delete_path/1)

      compile_paths
      |> Enum.map(&runtime_data_path/1)
      |> Enum.map(&Path.dirname(Path.dirname(&1)))
      |> Enum.uniq()
      |> Enum.each(&File.rm_rf!/1)
    end)
  end

  defp compile_runtime_metadata_app!(manifest_path, source_dir, compile_path, sprite_build_path) do
    runtime_data_path = runtime_data_path(compile_path)

    assert :ok = compile_fixture_modules!(manifest_path, source_dir, compile_path)

    assert :ok =
             SvgSpriteExAssets.compile_sprite_artifacts!(
               compile_path: compile_path,
               compiler_state_path: compiler_state_path(manifest_path),
               elixir_manifest_path: manifest_path,
               runtime_data_path: runtime_data_path,
               build_path: sprite_build_path,
               public_path: Config.public_path!(),
               source_root: Config.source_root!()
             )
  end

  defp compile_fixture_modules!(manifest_path, source_dir, compile_path) do
    override = compiler_state_path(manifest_path)
    previous_override = Application.get_env(:svg_sprite_ex, :compiler_state_path_override)
    Application.put_env(:svg_sprite_ex, :compiler_state_path_override, override)

    try do
      # Note: This intentionally uses Mix's internal compile/7 API for test
      # infrastructure. If the signature changes on Elixir upgrade, update this
      # helper in test/svg_sprite_ex_metadata_test.exs.
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
    after
      if is_nil(previous_override) do
        Application.delete_env(:svg_sprite_ex, :compiler_state_path_override)
      else
        Application.put_env(:svg_sprite_ex, :compiler_state_path_override, previous_override)
      end
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
    app_path = unique_tmp_dir!("runtime-app-path")
    compile_path = Path.join(app_path, "ebin")
    sprite_build_path = unique_tmp_dir!("runtime-sprite-build-path")
    manifest_path = elixir_manifest_path!(source_dir)
    File.mkdir_p!(compile_path)
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

  defp compiler_state_path(manifest_path) do
    manifest_path
    |> Path.dirname()
    |> Path.join("svg_sprite_ex")
  end

  defp runtime_data_path(compile_path) do
    compile_path
    |> Path.dirname()
    |> Path.join("priv/svg_sprite_ex/runtime_data.etf")
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
