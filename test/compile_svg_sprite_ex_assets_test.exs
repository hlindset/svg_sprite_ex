defmodule Mix.Tasks.Compile.SvgSpriteExAssetsTest do
  use ExUnit.Case

  import Test.Support.CompileHelpers,
    only: [capture_result: 1, compile_fixture_modules!: 3, compiler_state_path: 1]

  alias Mix.Tasks.Compile.SvgSpriteExAssets
  alias SvgSpriteEx.Config
  alias SvgSpriteEx.Ref

  test "run/1 returns :noop" do
    assert :noop = SvgSpriteExAssets.run([])
  end

  test "compile_fixture_modules!/3 persists ref snapshots for modules that use refs" do
    source_dir = unique_tmp_dir!("source-dir")
    compile_path = unique_tmp_dir!("compile-path")
    manifest_path = elixir_manifest_path!(source_dir)
    sprite_module = unique_module(:snapshot_sprite_fixture)
    inline_module = unique_module(:snapshot_inline_fixture)

    write_sprite_fixture_module!(source_dir, sprite_module, sheet: "alerts")
    write_inline_fixture_module!(source_dir, inline_module, name: "regular/xmark")

    assert :ok = compile_fixture_modules!(manifest_path, source_dir, compile_path)

    assert %{
             vsn: 1,
             module: ^sprite_module,
             sprite_refs: [{"alerts", "regular/xmark"}],
             inline_refs: []
           } = read_ref_snapshot!(ref_snapshot_path(manifest_path, sprite_module))

    assert %{
             vsn: 1,
             module: ^inline_module,
             sprite_refs: [],
             inline_refs: ["regular/xmark"]
           } = read_ref_snapshot!(ref_snapshot_path(manifest_path, inline_module))

    assert temp_artifact_paths(compiler_state_path(manifest_path)) == []
  end

  test "after_elixir_callback/1 compiles sprite artifacts when elixir reports ok" do
    source_dir = unique_tmp_dir!("source-dir")
    compile_path = unique_tmp_dir!("compile-path")
    sprite_build_path = unique_tmp_dir!("sprite-build-path")
    manifest_path = elixir_manifest_path!(source_dir)
    compiler_manifest_path = compiler_manifest_path(manifest_path)
    runtime_data_path = runtime_data_path(manifest_path)

    write_sprite_fixture_module!(source_dir, unique_module(:hooked_sprite_fixture),
      sheet: "alerts"
    )

    write_inline_fixture_module!(source_dir, unique_module(:hooked_inline_fixture),
      name: "regular/xmark"
    )

    assert :ok = compile_fixture_modules!(manifest_path, source_dir, compile_path)

    callback =
      SvgSpriteExAssets.after_elixir_callback(
        compile_path: compile_path,
        compiler_state_path: compiler_state_path(manifest_path),
        compiler_manifest_path: compiler_manifest_path,
        elixir_manifest_path: manifest_path,
        runtime_data_path: runtime_data_path,
        build_path: sprite_build_path,
        source_root: Config.source_root!()
      )

    assert {:ok, [:diagnostic]} = callback.({:ok, [:diagnostic]})

    assert File.exists?(Ref.sheet_build_path("alerts", sprite_build_path))
    assert File.exists?(runtime_data_path)
    assert %{vsn: runtime_data_vsn} = read_runtime_data!(runtime_data_path)
    assert runtime_data_vsn == SvgSpriteEx.Generated.RuntimeData.runtime_data_vsn()
  end

  test "after_elixir_callback/1 recompiles sprite artifacts when elixir reports noop" do
    source_dir = unique_tmp_dir!("source-dir")
    compile_path = unique_tmp_dir!("compile-path")
    sprite_build_path = unique_tmp_dir!("sprite-build-path")
    manifest_path = elixir_manifest_path!(source_dir)
    compiler_manifest_path = compiler_manifest_path(manifest_path)
    runtime_data_path = runtime_data_path(manifest_path)

    write_sprite_fixture_module!(source_dir, unique_module(:hooked_sprite_fixture_on_noop),
      sheet: "alerts"
    )

    write_inline_fixture_module!(source_dir, unique_module(:hooked_inline_fixture_on_noop),
      name: "regular/xmark"
    )

    assert :ok = compile_fixture_modules!(manifest_path, source_dir, compile_path)

    callback =
      SvgSpriteExAssets.after_elixir_callback(
        compile_path: compile_path,
        compiler_state_path: compiler_state_path(manifest_path),
        compiler_manifest_path: compiler_manifest_path,
        elixir_manifest_path: manifest_path,
        runtime_data_path: runtime_data_path,
        build_path: sprite_build_path,
        source_root: Config.source_root!()
      )

    assert {:noop, [:diagnostic]} = callback.({:noop, [:diagnostic]})

    assert File.exists?(runtime_data_path)
    assert File.exists?(Ref.sheet_build_path("alerts", sprite_build_path))
  end

  test "after_elixir_callback/1 keeps artifacts unchanged when noop inputs are unchanged" do
    source_dir = unique_tmp_dir!("source-dir")
    compile_path = unique_tmp_dir!("compile-path")
    sprite_build_path = unique_tmp_dir!("sprite-build-path")
    manifest_path = elixir_manifest_path!(source_dir)
    compiler_manifest_path = compiler_manifest_path(manifest_path)
    runtime_data_path = runtime_data_path(manifest_path)

    write_sprite_fixture_module!(source_dir, unique_module(:hooked_stable_sprite_fixture),
      sheet: "alerts"
    )

    write_inline_fixture_module!(source_dir, unique_module(:hooked_stable_inline_fixture),
      name: "regular/xmark"
    )

    assert :ok = compile_fixture_modules!(manifest_path, source_dir, compile_path)

    callback =
      SvgSpriteExAssets.after_elixir_callback(
        compile_path: compile_path,
        compiler_state_path: compiler_state_path(manifest_path),
        compiler_manifest_path: compiler_manifest_path,
        elixir_manifest_path: manifest_path,
        runtime_data_path: runtime_data_path,
        build_path: sprite_build_path,
        source_root: Config.source_root!()
      )

    assert {:ok, []} = callback.({:ok, []})

    sheet_path = Ref.sheet_build_path("alerts", sprite_build_path)
    runtime_data = File.read!(runtime_data_path)
    sprite_sheet = File.read!(sheet_path)
    manifest = File.read!(compiler_manifest_path)

    assert {:noop, [:diagnostic]} = callback.({:noop, [:diagnostic]})

    assert File.read!(runtime_data_path) == runtime_data
    assert File.read!(sheet_path) == sprite_sheet
    assert File.read!(compiler_manifest_path) == manifest
  end

  test "after_elixir_callback/1 recompiles generated inline assets when inline svg contents change on noop" do
    source_dir = unique_tmp_dir!("source-dir")
    compile_path = unique_tmp_dir!("compile-path")
    sprite_build_path = unique_tmp_dir!("sprite-build-path")
    manifest_path = elixir_manifest_path!(source_dir)
    compiler_manifest_path = compiler_manifest_path(manifest_path)
    runtime_data_path = runtime_data_path(manifest_path)
    svg_source_root = unique_svg_source_root!("inline-noop-change")

    write_inline_fixture_module!(source_dir, unique_module(:hooked_inline_noop_fixture),
      name: "regular/xmark"
    )

    assert :ok = compile_fixture_modules!(manifest_path, source_dir, compile_path)

    callback =
      SvgSpriteExAssets.after_elixir_callback(
        compile_path: compile_path,
        compiler_state_path: compiler_state_path(manifest_path),
        compiler_manifest_path: compiler_manifest_path,
        elixir_manifest_path: manifest_path,
        runtime_data_path: runtime_data_path,
        build_path: sprite_build_path,
        source_root: svg_source_root
      )

    assert {:ok, []} = callback.({:ok, []})

    first_runtime_data = read_runtime_data!(runtime_data_path)

    write_svg_source!(
      svg_source_root,
      "regular/xmark",
      """
      <svg viewBox="0 0 24 24" fill="currentColor">
        <path d="M1 1h22v22H1z" />
      </svg>
      """
    )

    assert {:noop, [:diagnostic]} = callback.({:noop, [:diagnostic]})

    second_runtime_data = read_runtime_data!(runtime_data_path)

    refute first_runtime_data.inline_assets["regular/xmark"].attributes["fill"]
    assert second_runtime_data.inline_assets["regular/xmark"].attributes["fill"] == "currentColor"
    assert second_runtime_data.inline_assets["regular/xmark"].inner_content =~ "M1 1h22v22H1z"
    assert second_runtime_data.inline_svg_map["regular/xmark"].name == "regular/xmark"
  end

  test "after_elixir_callback/1 rewrites sprite sheets when sprite svg contents change on noop" do
    source_dir = unique_tmp_dir!("source-dir")
    compile_path = unique_tmp_dir!("compile-path")
    sprite_build_path = unique_tmp_dir!("sprite-build-path")
    manifest_path = elixir_manifest_path!(source_dir)
    compiler_manifest_path = compiler_manifest_path(manifest_path)
    runtime_data_path = runtime_data_path(manifest_path)
    svg_source_root = unique_svg_source_root!("sprite-noop-change")

    write_sprite_fixture_module!(source_dir, unique_module(:hooked_sprite_noop_fixture),
      sheet: "alerts"
    )

    assert :ok = compile_fixture_modules!(manifest_path, source_dir, compile_path)

    callback =
      SvgSpriteExAssets.after_elixir_callback(
        compile_path: compile_path,
        compiler_state_path: compiler_state_path(manifest_path),
        compiler_manifest_path: compiler_manifest_path,
        elixir_manifest_path: manifest_path,
        runtime_data_path: runtime_data_path,
        build_path: sprite_build_path,
        public_path: Config.public_path!(),
        source_root: svg_source_root
      )

    assert {:ok, []} = callback.({:ok, []})

    sheet_path = Ref.sheet_build_path("alerts", sprite_build_path)
    first_sprite_sheet = File.read!(sheet_path)

    write_svg_source!(
      svg_source_root,
      "regular/xmark",
      """
      <svg viewBox="0 0 24 24">
        <path d="M2 2h20v20H2z" />
      </svg>
      """
    )

    assert {:noop, [:diagnostic]} = callback.({:noop, [:diagnostic]})

    second_sprite_sheet = File.read!(sheet_path)

    refute first_sprite_sheet =~ "M2 2h20v20H2z"
    assert second_sprite_sheet =~ "M2 2h20v20H2z"
  end

  test "after_elixir_callback/1 skips sprite compilation when elixir reports error" do
    source_dir = unique_tmp_dir!("source-dir")
    compile_path = unique_tmp_dir!("compile-path")
    sprite_build_path = unique_tmp_dir!("sprite-build-path")
    manifest_path = elixir_manifest_path!(source_dir)
    compiler_manifest_path = compiler_manifest_path(manifest_path)
    runtime_data_path = runtime_data_path(manifest_path)

    write_sprite_fixture_module!(source_dir, unique_module(:hooked_sprite_fixture_on_error),
      sheet: "alerts"
    )

    write_inline_fixture_module!(source_dir, unique_module(:hooked_inline_fixture_on_error),
      name: "regular/xmark"
    )

    assert :ok = compile_fixture_modules!(manifest_path, source_dir, compile_path)

    callback =
      SvgSpriteExAssets.after_elixir_callback(
        compile_path: compile_path,
        compiler_state_path: compiler_state_path(manifest_path),
        compiler_manifest_path: compiler_manifest_path,
        elixir_manifest_path: manifest_path,
        runtime_data_path: runtime_data_path,
        build_path: sprite_build_path,
        source_root: Config.source_root!()
      )

    assert {:error, [:diagnostic]} = callback.({:error, [:diagnostic]})

    refute File.exists?(Ref.sheet_build_path("alerts", sprite_build_path))
    refute File.exists?(runtime_data_path)
  end

  test "register_after_elixir_hook/1 installs the hook without compiling eagerly" do
    source_dir = unique_tmp_dir!("source-dir")
    compile_path = unique_tmp_dir!("compile-path")
    sprite_build_path = unique_tmp_dir!("sprite-build-path")
    manifest_path = elixir_manifest_path!(source_dir)
    compiler_manifest_path = compiler_manifest_path(manifest_path)
    runtime_data_path = runtime_data_path(manifest_path)

    write_inline_fixture_module!(source_dir, unique_module(:hook_registration_inline_fixture),
      name: "regular/xmark"
    )

    assert :ok = compile_fixture_modules!(manifest_path, source_dir, compile_path)

    assert :ok =
             SvgSpriteExAssets.register_after_elixir_hook(
               compile_path: compile_path,
               compiler_state_path: compiler_state_path(manifest_path),
               compiler_manifest_path: compiler_manifest_path,
               elixir_manifest_path: manifest_path,
               runtime_data_path: runtime_data_path,
               build_path: sprite_build_path,
               source_root: Config.source_root!()
             )

    refute File.exists?(runtime_data_path)
  end

  test "after_elixir_callback/1 writes runtime data before compile.app completes" do
    source_dir = unique_tmp_dir!("source-dir")
    compile_path = unique_tmp_dir!("compile-path")
    sprite_build_path = unique_tmp_dir!("sprite-build-path")
    manifest_path = elixir_manifest_path!(source_dir)
    compiler_manifest_path = compiler_manifest_path(manifest_path)
    runtime_data_path = runtime_data_path(manifest_path)

    write_inline_fixture_module!(source_dir, unique_module(:app_order_inline_fixture),
      name: "regular/xmark"
    )

    assert :ok = compile_fixture_modules!(manifest_path, source_dir, compile_path)

    # register_after_elixir_hook/1 is covered by the installation test above;
    # this assertion is intentionally narrowed to after_elixir_callback/1 behavior.
    callback =
      SvgSpriteExAssets.after_elixir_callback(
        compile_path: compile_path,
        compiler_state_path: compiler_state_path(manifest_path),
        compiler_manifest_path: compiler_manifest_path,
        elixir_manifest_path: manifest_path,
        runtime_data_path: runtime_data_path,
        build_path: sprite_build_path,
        source_root: Config.source_root!()
      )

    assert {:ok, []} = callback.({:ok, []})
    assert File.exists?(runtime_data_path)

    Mix.Task.reenable("compile.app")

    assert {{:ok, []}, _output} =
             capture_result(fn ->
               Mix.Tasks.Compile.App.run(["--force", "--compile-path", compile_path])
             end)
  end

  test "compile_sprite_artifacts!/1 removes stale sprite outputs after modules disappear" do
    source_dir = unique_tmp_dir!("source-dir")
    compile_path = unique_tmp_dir!("compile-path")
    sprite_build_path = unique_tmp_dir!("sprite-build-path")
    manifest_path = elixir_manifest_path!(source_dir)
    runtime_data_path = runtime_data_path(manifest_path)
    svg_source_root = Config.source_root!()

    module = unique_module(:deleted_fixture)
    source_path = write_sprite_fixture_module!(source_dir, module, sheet: "alerts")

    assert :ok = compile_fixture_modules!(manifest_path, source_dir, compile_path)

    assert :ok =
             SvgSpriteExAssets.compile_sprite_artifacts!(
               compile_path: compile_path,
               compiler_state_path: compiler_state_path(manifest_path),
               elixir_manifest_path: manifest_path,
               runtime_data_path: runtime_data_path,
               build_path: sprite_build_path,
               source_root: svg_source_root
             )

    sheet_path = Ref.sheet_build_path("alerts", sprite_build_path)
    stale_beam_path = Path.join(compile_path, "#{Atom.to_string(module)}.beam")
    stale_beam_copy = Path.join(unique_tmp_dir!("stale-beam"), Path.basename(stale_beam_path))

    assert File.exists?(sheet_path)
    assert File.exists?(stale_beam_path)
    File.cp!(stale_beam_path, stale_beam_copy)

    File.rm!(source_path)
    assert :ok = compile_fixture_modules!(manifest_path, source_dir, compile_path)

    refute module in manifest_modules(manifest_path)
    unless File.exists?(stale_beam_path), do: File.cp!(stale_beam_copy, stale_beam_path)
    assert File.exists?(stale_beam_path)

    assert :ok =
             SvgSpriteExAssets.compile_sprite_artifacts!(
               compile_path: compile_path,
               compiler_state_path: compiler_state_path(manifest_path),
               elixir_manifest_path: manifest_path,
               runtime_data_path: runtime_data_path,
               build_path: sprite_build_path,
               source_root: svg_source_root
             )

    refute File.exists?(sheet_path)
  end

  test "compile_sprite_artifacts!/1 bootstraps missing ref snapshots from exported refs" do
    source_dir = unique_tmp_dir!("source-dir")
    compile_path = unique_tmp_dir!("compile-path")
    sprite_build_path = unique_tmp_dir!("sprite-build-path")
    manifest_path = elixir_manifest_path!(source_dir)
    compiler_manifest_path = compiler_manifest_path(manifest_path)
    runtime_data_path = runtime_data_path(manifest_path)
    sprite_module = unique_module(:bootstrapped_sprite_fixture)
    inline_module = unique_module(:bootstrapped_inline_fixture)

    write_sprite_fixture_module!(source_dir, sprite_module, sheet: "alerts")
    write_inline_fixture_module!(source_dir, inline_module, name: "regular/xmark")

    assert :ok = compile_fixture_modules!(manifest_path, source_dir, compile_path)

    File.rm_rf!(compiler_state_path(manifest_path))

    assert :ok =
             SvgSpriteExAssets.compile_sprite_artifacts!(
               compile_path: compile_path,
               compiler_state_path: compiler_state_path(manifest_path),
               compiler_manifest_path: compiler_manifest_path,
               elixir_manifest_path: manifest_path,
               runtime_data_path: runtime_data_path,
               build_path: sprite_build_path,
               public_path: Config.public_path!(),
               source_root: Config.source_root!()
             )

    assert File.exists?(ref_snapshot_path(manifest_path, sprite_module))
    assert File.exists?(ref_snapshot_path(manifest_path, inline_module))
    assert File.exists?(runtime_data_path)
    assert File.exists?(Ref.sheet_build_path("alerts", sprite_build_path))
    assert temp_artifact_paths(compiler_state_path(manifest_path)) == []
    assert temp_artifact_paths(sprite_build_path) == []
  end

  test "compile_sprite_artifacts!/1 keeps runtime data when manifest is present and one snapshot is missing" do
    source_dir = unique_tmp_dir!("source-dir")
    compile_path = unique_tmp_dir!("compile-path")
    sprite_build_path = unique_tmp_dir!("sprite-build-path")
    manifest_path = elixir_manifest_path!(source_dir)
    compiler_manifest_path = compiler_manifest_path(manifest_path)
    runtime_data_path = runtime_data_path(manifest_path)
    sprite_module = unique_module(:manifest_sprite_fixture)
    inline_module = unique_module(:manifest_inline_fixture)

    write_sprite_fixture_module!(source_dir, sprite_module, sheet: "alerts")
    write_inline_fixture_module!(source_dir, inline_module, name: "regular/xmark")

    assert :ok = compile_fixture_modules!(manifest_path, source_dir, compile_path)

    assert :ok =
             SvgSpriteExAssets.compile_sprite_artifacts!(
               compile_path: compile_path,
               compiler_state_path: compiler_state_path(manifest_path),
               compiler_manifest_path: compiler_manifest_path,
               elixir_manifest_path: manifest_path,
               runtime_data_path: runtime_data_path,
               build_path: sprite_build_path,
               public_path: Config.public_path!(),
               source_root: Config.source_root!()
             )

    assert File.exists?(compiler_manifest_path)
    assert tracked_ref_snapshots_bootstrapped(compiler_manifest_path)
    File.rm!(ref_snapshot_path(manifest_path, inline_module))
    refute File.exists?(ref_snapshot_path(manifest_path, inline_module))

    assert :ok =
             SvgSpriteExAssets.compile_sprite_artifacts!(
               compile_path: compile_path,
               compiler_state_path: compiler_state_path(manifest_path),
               compiler_manifest_path: compiler_manifest_path,
               elixir_manifest_path: manifest_path,
               runtime_data_path: runtime_data_path,
               build_path: sprite_build_path,
               public_path: Config.public_path!(),
               source_root: Config.source_root!()
             )

    assert File.exists?(runtime_data_path)
    assert File.exists?(Ref.sheet_build_path("alerts", sprite_build_path))
    assert File.exists?(ref_snapshot_path(manifest_path, inline_module))

    runtime_data = read_runtime_data!(runtime_data_path)
    assert Map.has_key?(runtime_data.inline_assets, "regular/xmark")
    assert Enum.any?(runtime_data.sprite_sheets, &(&1.name == "alerts"))
    refute tracked_ref_snapshots_bootstrapped(compiler_manifest_path)

    assert :ok =
             SvgSpriteExAssets.compile_sprite_artifacts!(
               compile_path: compile_path,
               compiler_state_path: compiler_state_path(manifest_path),
               compiler_manifest_path: compiler_manifest_path,
               elixir_manifest_path: manifest_path,
               runtime_data_path: runtime_data_path,
               build_path: sprite_build_path,
               public_path: Config.public_path!(),
               source_root: Config.source_root!()
             )

    assert tracked_ref_snapshots_bootstrapped(compiler_manifest_path)
  end

  test "compile_sprite_artifacts!/1 rewrites legacy ref snapshots to the versioned format" do
    source_dir = unique_tmp_dir!("source-dir")
    compile_path = unique_tmp_dir!("compile-path")
    sprite_build_path = unique_tmp_dir!("sprite-build-path")
    manifest_path = elixir_manifest_path!(source_dir)
    compiler_manifest_path = compiler_manifest_path(manifest_path)
    runtime_data_path = runtime_data_path(manifest_path)
    sprite_module = unique_module(:legacy_snapshot_sprite_fixture)
    inline_module = unique_module(:legacy_snapshot_inline_fixture)
    sprite_snapshot_path = ref_snapshot_path(manifest_path, sprite_module)

    write_sprite_fixture_module!(source_dir, sprite_module, sheet: "alerts")
    write_inline_fixture_module!(source_dir, inline_module, name: "regular/xmark")

    assert :ok = compile_fixture_modules!(manifest_path, source_dir, compile_path)

    write_legacy_ref_snapshot!(sprite_snapshot_path, %{
      module: sprite_module,
      sprite_refs: [{"alerts", "regular/xmark"}],
      inline_refs: []
    })

    assert :ok =
             SvgSpriteExAssets.compile_sprite_artifacts!(
               compile_path: compile_path,
               compiler_state_path: compiler_state_path(manifest_path),
               compiler_manifest_path: compiler_manifest_path,
               elixir_manifest_path: manifest_path,
               runtime_data_path: runtime_data_path,
               build_path: sprite_build_path,
               public_path: Config.public_path!(),
               source_root: Config.source_root!()
             )

    assert %{
             vsn: 1,
             module: ^sprite_module,
             sprite_refs: [{"alerts", "regular/xmark"}],
             inline_refs: []
           } = read_ref_snapshot!(sprite_snapshot_path)

    runtime_data = read_runtime_data!(runtime_data_path)
    assert Map.has_key?(runtime_data.inline_assets, "regular/xmark")
    assert Enum.any?(runtime_data.sprite_sheets, &(&1.name == "alerts"))
    refute tracked_ref_snapshots_bootstrapped(compiler_manifest_path)
  end

  test "compile_sprite_artifacts!/1 only removes manifest-tracked sprite outputs" do
    source_dir = unique_tmp_dir!("source-dir")
    compile_path = unique_tmp_dir!("compile-path")
    sprite_build_path = unique_tmp_dir!("sprite-build-path")
    manifest_path = elixir_manifest_path!(source_dir)
    compiler_manifest_path = compiler_manifest_path(manifest_path)
    runtime_data_path = runtime_data_path(manifest_path)
    svg_source_root = Config.source_root!()
    foreign_svg_path = Path.join(sprite_build_path, "foreign.svg")

    module = unique_module(:sprite_cleanup_fixture)
    write_sprite_fixture_module!(source_dir, module, sheet: "alerts")
    File.write!(foreign_svg_path, "<svg />")

    assert :ok = compile_fixture_modules!(manifest_path, source_dir, compile_path)

    assert :ok =
             SvgSpriteExAssets.compile_sprite_artifacts!(
               compile_path: compile_path,
               compiler_state_path: compiler_state_path(manifest_path),
               compiler_manifest_path: compiler_manifest_path,
               elixir_manifest_path: manifest_path,
               runtime_data_path: runtime_data_path,
               build_path: sprite_build_path,
               source_root: svg_source_root
             )

    File.rm!(fixture_source_path(source_dir, module))
    assert :ok = compile_fixture_modules!(manifest_path, source_dir, compile_path)

    assert :ok =
             SvgSpriteExAssets.compile_sprite_artifacts!(
               compile_path: compile_path,
               compiler_state_path: compiler_state_path(manifest_path),
               compiler_manifest_path: compiler_manifest_path,
               elixir_manifest_path: manifest_path,
               runtime_data_path: runtime_data_path,
               build_path: sprite_build_path,
               source_root: svg_source_root
             )

    refute File.exists?(Ref.sheet_build_path("alerts", sprite_build_path))
    assert File.exists?(foreign_svg_path)
  end

  test "compile_sprite_artifacts!/1 writes runtime data from manifest-backed inline refs" do
    source_dir = unique_tmp_dir!("source-dir")
    compile_path = unique_tmp_dir!("compile-path")
    sprite_build_path = unique_tmp_dir!("sprite-build-path")
    manifest_path = elixir_manifest_path!(source_dir)
    compiler_manifest_path = compiler_manifest_path(manifest_path)
    runtime_data_path = runtime_data_path(manifest_path)

    write_inline_fixture_module!(source_dir, unique_module(:inline_fixture),
      name: "regular/xmark"
    )

    assert :ok = compile_fixture_modules!(manifest_path, source_dir, compile_path)

    assert :ok =
             SvgSpriteExAssets.compile_sprite_artifacts!(
               compile_path: compile_path,
               compiler_state_path: compiler_state_path(manifest_path),
               compiler_manifest_path: compiler_manifest_path,
               elixir_manifest_path: manifest_path,
               runtime_data_path: runtime_data_path,
               build_path: sprite_build_path,
               source_root: Config.source_root!()
             )

    runtime_data = read_runtime_data!(runtime_data_path)

    assert runtime_data.inline_svgs == [runtime_data.inline_svg_map["regular/xmark"]]
    assert {:ok, _asset} = Map.fetch(runtime_data.inline_assets, "regular/xmark")
    assert runtime_data.inline_svg_map["regular/xmark"].name == "regular/xmark"

    assert compiler_manifest_path |> tracked_artifact_paths() |> Enum.sort() ==
             Enum.sort([
               runtime_data_path
             ])
  end

  test "compile_sprite_artifacts!/1 writes runtime data from manifest-backed sprite refs" do
    source_dir = unique_tmp_dir!("source-dir")
    compile_path = unique_tmp_dir!("compile-path")
    sprite_build_path = unique_tmp_dir!("sprite-build-path")
    manifest_path = elixir_manifest_path!(source_dir)
    compiler_manifest_path = compiler_manifest_path(manifest_path)
    runtime_data_path = runtime_data_path(manifest_path)

    write_sprite_fixture_module!(source_dir, unique_module(:sprite_metadata_fixture),
      sheet: "alerts"
    )

    assert :ok = compile_fixture_modules!(manifest_path, source_dir, compile_path)

    assert :ok =
             SvgSpriteExAssets.compile_sprite_artifacts!(
               compile_path: compile_path,
               compiler_state_path: compiler_state_path(manifest_path),
               compiler_manifest_path: compiler_manifest_path,
               elixir_manifest_path: manifest_path,
               runtime_data_path: runtime_data_path,
               build_path: sprite_build_path,
               public_path: Config.public_path!(),
               source_root: Config.source_root!()
             )

    runtime_data = read_runtime_data!(runtime_data_path)

    assert sheet_info = runtime_data.sprite_sheet_map["alerts"]
    assert sheet_info.name == "alerts"
    assert sheet_info.filename == "alerts.svg"
    assert match?([_], runtime_data.sprites_in_sheet["alerts"])

    assert compiler_manifest_path |> tracked_artifact_paths() |> Enum.sort() ==
             Enum.sort([
               Ref.sheet_build_path("alerts", sprite_build_path),
               runtime_data_path
             ])
  end

  test "compile_sprite_artifacts!/1 removes the runtime data artifact when inline refs disappear" do
    source_dir = unique_tmp_dir!("source-dir")
    compile_path = unique_tmp_dir!("compile-path")
    sprite_build_path = unique_tmp_dir!("sprite-build-path")
    manifest_path = elixir_manifest_path!(source_dir)
    compiler_manifest_path = compiler_manifest_path(manifest_path)
    runtime_data_path = runtime_data_path(manifest_path)

    module = unique_module(:inline_deleted_fixture)
    source_path = write_inline_fixture_module!(source_dir, module, name: "regular/xmark")

    assert :ok = compile_fixture_modules!(manifest_path, source_dir, compile_path)

    assert :ok =
             SvgSpriteExAssets.compile_sprite_artifacts!(
               compile_path: compile_path,
               compiler_state_path: compiler_state_path(manifest_path),
               compiler_manifest_path: compiler_manifest_path,
               elixir_manifest_path: manifest_path,
               runtime_data_path: runtime_data_path,
               build_path: sprite_build_path,
               source_root: Config.source_root!()
             )

    assert File.exists?(runtime_data_path)

    File.rm!(source_path)
    assert :ok = compile_fixture_modules!(manifest_path, source_dir, compile_path)

    assert :ok =
             SvgSpriteExAssets.compile_sprite_artifacts!(
               compile_path: compile_path,
               compiler_state_path: compiler_state_path(manifest_path),
               compiler_manifest_path: compiler_manifest_path,
               elixir_manifest_path: manifest_path,
               runtime_data_path: runtime_data_path,
               build_path: sprite_build_path,
               source_root: Config.source_root!()
             )

    refute File.exists?(runtime_data_path)
    assert tracked_artifact_paths(compiler_manifest_path) == []
  end

  test "compile_sprite_artifacts!/1 removes the runtime data artifact when sprite refs disappear" do
    source_dir = unique_tmp_dir!("source-dir")
    compile_path = unique_tmp_dir!("compile-path")
    sprite_build_path = unique_tmp_dir!("sprite-build-path")
    manifest_path = elixir_manifest_path!(source_dir)
    compiler_manifest_path = compiler_manifest_path(manifest_path)
    runtime_data_path = runtime_data_path(manifest_path)

    module = unique_module(:sprite_metadata_deleted_fixture)
    source_path = write_sprite_fixture_module!(source_dir, module, sheet: "alerts")

    assert :ok = compile_fixture_modules!(manifest_path, source_dir, compile_path)

    assert :ok =
             SvgSpriteExAssets.compile_sprite_artifacts!(
               compile_path: compile_path,
               compiler_state_path: compiler_state_path(manifest_path),
               compiler_manifest_path: compiler_manifest_path,
               elixir_manifest_path: manifest_path,
               runtime_data_path: runtime_data_path,
               build_path: sprite_build_path,
               public_path: Config.public_path!(),
               source_root: Config.source_root!()
             )

    assert File.exists?(runtime_data_path)

    File.rm!(source_path)
    assert :ok = compile_fixture_modules!(manifest_path, source_dir, compile_path)

    assert :ok =
             SvgSpriteExAssets.compile_sprite_artifacts!(
               compile_path: compile_path,
               compiler_state_path: compiler_state_path(manifest_path),
               compiler_manifest_path: compiler_manifest_path,
               elixir_manifest_path: manifest_path,
               runtime_data_path: runtime_data_path,
               build_path: sprite_build_path,
               public_path: Config.public_path!(),
               source_root: Config.source_root!()
             )

    refute File.exists?(runtime_data_path)
    assert tracked_artifact_paths(compiler_manifest_path) == []
  end

  test "compile_sprite_artifacts!/1 rewrites runtime data when inline svg contents change" do
    source_dir = unique_tmp_dir!("source-dir")
    compile_path = unique_tmp_dir!("compile-path")
    sprite_build_path = unique_tmp_dir!("sprite-build-path")
    manifest_path = elixir_manifest_path!(source_dir)
    compiler_manifest_path = compiler_manifest_path(manifest_path)
    runtime_data_path = runtime_data_path(manifest_path)
    svg_source_root = unique_svg_source_root!("inline-change")

    write_inline_fixture_module!(source_dir, unique_module(:inline_changed_fixture),
      name: "regular/xmark"
    )

    assert :ok = compile_fixture_modules!(manifest_path, source_dir, compile_path)

    assert :ok =
             SvgSpriteExAssets.compile_sprite_artifacts!(
               compile_path: compile_path,
               compiler_state_path: compiler_state_path(manifest_path),
               compiler_manifest_path: compiler_manifest_path,
               elixir_manifest_path: manifest_path,
               runtime_data_path: runtime_data_path,
               build_path: sprite_build_path,
               source_root: svg_source_root
             )

    first_runtime_data = read_runtime_data!(runtime_data_path)

    File.write!(
      Path.join(svg_source_root, "regular/xmark.svg"),
      """
      <svg viewBox="0 0 24 24" fill="currentColor">
        <path d="M1 1h22v22H1z" />
      </svg>
      """
    )

    assert :ok =
             SvgSpriteExAssets.compile_sprite_artifacts!(
               compile_path: compile_path,
               compiler_state_path: compiler_state_path(manifest_path),
               compiler_manifest_path: compiler_manifest_path,
               elixir_manifest_path: manifest_path,
               runtime_data_path: runtime_data_path,
               build_path: sprite_build_path,
               source_root: svg_source_root
             )

    second_runtime_data = read_runtime_data!(runtime_data_path)

    refute first_runtime_data.inline_assets["regular/xmark"].attributes["fill"]
    assert second_runtime_data.inline_assets["regular/xmark"].attributes["fill"] == "currentColor"
    assert second_runtime_data.inline_assets["regular/xmark"].inner_content =~ "M1 1h22v22H1z"
  end

  test "compile_sprite_artifacts!/1 rebuilds runtime data when a tracked artifact is missing" do
    source_dir = unique_tmp_dir!("source-dir")
    compile_path = unique_tmp_dir!("compile-path")
    sprite_build_path = unique_tmp_dir!("sprite-build-path")
    manifest_path = elixir_manifest_path!(source_dir)
    compiler_manifest_path = compiler_manifest_path(manifest_path)
    runtime_data_path = runtime_data_path(manifest_path)

    write_inline_fixture_module!(source_dir, unique_module(:missing_artifact_fixture),
      name: "regular/xmark"
    )

    assert :ok = compile_fixture_modules!(manifest_path, source_dir, compile_path)

    assert :ok =
             SvgSpriteExAssets.compile_sprite_artifacts!(
               compile_path: compile_path,
               compiler_state_path: compiler_state_path(manifest_path),
               compiler_manifest_path: compiler_manifest_path,
               elixir_manifest_path: manifest_path,
               runtime_data_path: runtime_data_path,
               build_path: sprite_build_path,
               source_root: Config.source_root!()
             )

    File.rm!(runtime_data_path)

    assert :ok =
             SvgSpriteExAssets.compile_sprite_artifacts!(
               compile_path: compile_path,
               compiler_state_path: compiler_state_path(manifest_path),
               compiler_manifest_path: compiler_manifest_path,
               elixir_manifest_path: manifest_path,
               runtime_data_path: runtime_data_path,
               build_path: sprite_build_path,
               source_root: Config.source_root!()
             )

    assert File.exists?(runtime_data_path)
  end

  test "compile_sprite_artifacts!/1 rebuilds when the compiler manifest is from an older version" do
    source_dir = unique_tmp_dir!("source-dir")
    compile_path = unique_tmp_dir!("compile-path")
    sprite_build_path = unique_tmp_dir!("sprite-build-path")
    manifest_path = elixir_manifest_path!(source_dir)
    compiler_manifest_path = compiler_manifest_path(manifest_path)
    runtime_data_path = runtime_data_path(manifest_path)

    write_inline_fixture_module!(source_dir, unique_module(:legacy_manifest_fixture),
      name: "regular/xmark"
    )

    assert :ok = compile_fixture_modules!(manifest_path, source_dir, compile_path)

    assert :ok =
             SvgSpriteExAssets.compile_sprite_artifacts!(
               compile_path: compile_path,
               compiler_state_path: compiler_state_path(manifest_path),
               compiler_manifest_path: compiler_manifest_path,
               elixir_manifest_path: manifest_path,
               runtime_data_path: runtime_data_path,
               build_path: sprite_build_path,
               source_root: Config.source_root!()
             )

    write_legacy_manifest!(compiler_manifest_path, tracked_artifact_paths(compiler_manifest_path))

    assert :ok =
             SvgSpriteExAssets.compile_sprite_artifacts!(
               compile_path: compile_path,
               compiler_state_path: compiler_state_path(manifest_path),
               compiler_manifest_path: compiler_manifest_path,
               elixir_manifest_path: manifest_path,
               runtime_data_path: runtime_data_path,
               build_path: sprite_build_path,
               source_root: Config.source_root!()
             )

    assert is_binary(tracked_input_digest(compiler_manifest_path))
  end

  test "compile_sprite_artifacts!/1 rebuilds when the compiler fingerprint changes" do
    source_dir = unique_tmp_dir!("source-dir")
    compile_path = unique_tmp_dir!("compile-path")
    sprite_build_path = unique_tmp_dir!("sprite-build-path")
    manifest_path = elixir_manifest_path!(source_dir)
    compiler_manifest_path = compiler_manifest_path(manifest_path)
    runtime_data_path = runtime_data_path(manifest_path)

    write_inline_fixture_module!(source_dir, unique_module(:fingerprint_fixture),
      name: "regular/xmark"
    )

    assert :ok = compile_fixture_modules!(manifest_path, source_dir, compile_path)

    assert :ok =
             SvgSpriteExAssets.compile_sprite_artifacts!(
               compile_path: compile_path,
               compiler_state_path: compiler_state_path(manifest_path),
               compiler_manifest_path: compiler_manifest_path,
               elixir_manifest_path: manifest_path,
               runtime_data_path: runtime_data_path,
               compiler_fingerprint: "fingerprint-v1",
               build_path: sprite_build_path,
               source_root: Config.source_root!()
             )

    first_digest = tracked_input_digest(compiler_manifest_path)

    assert :noop =
             SvgSpriteExAssets.compile_sprite_artifacts!(
               compile_path: compile_path,
               compiler_state_path: compiler_state_path(manifest_path),
               compiler_manifest_path: compiler_manifest_path,
               elixir_manifest_path: manifest_path,
               runtime_data_path: runtime_data_path,
               compiler_fingerprint: "fingerprint-v1",
               build_path: sprite_build_path,
               source_root: Config.source_root!()
             )

    assert :ok =
             SvgSpriteExAssets.compile_sprite_artifacts!(
               compile_path: compile_path,
               compiler_state_path: compiler_state_path(manifest_path),
               compiler_manifest_path: compiler_manifest_path,
               elixir_manifest_path: manifest_path,
               runtime_data_path: runtime_data_path,
               compiler_fingerprint: "fingerprint-v2",
               build_path: sprite_build_path,
               source_root: Config.source_root!()
             )

    second_digest = tracked_input_digest(compiler_manifest_path)

    assert first_digest != second_digest
  end

  test "compile_sprite_artifacts!/1 noops when the manifest-backed refs are unchanged" do
    source_dir = unique_tmp_dir!("source-dir")
    compile_path = unique_tmp_dir!("compile-path")
    sprite_build_path = unique_tmp_dir!("sprite-build-path")
    manifest_path = elixir_manifest_path!(source_dir)
    compiler_manifest_path = compiler_manifest_path(manifest_path)
    runtime_data_path = runtime_data_path(manifest_path)
    svg_source_root = Config.source_root!()

    write_sprite_fixture_module!(source_dir, unique_module(:with_sprite_refs), sheet: "alerts")

    write_inline_fixture_module!(source_dir, unique_module(:with_inline_refs),
      name: "regular/xmark"
    )

    write_plain_module!(source_dir, unique_module(:without_refs))

    assert :ok = compile_fixture_modules!(manifest_path, source_dir, compile_path)

    assert :ok =
             SvgSpriteExAssets.compile_sprite_artifacts!(
               compile_path: compile_path,
               compiler_state_path: compiler_state_path(manifest_path),
               compiler_manifest_path: compiler_manifest_path,
               elixir_manifest_path: manifest_path,
               runtime_data_path: runtime_data_path,
               build_path: sprite_build_path,
               public_path: Config.public_path!(),
               source_root: svg_source_root
             )

    alerts_path = Ref.sheet_build_path("alerts", sprite_build_path)

    assert File.exists?(alerts_path)
    assert File.read!(alerts_path) =~ "<symbol"
    assert File.exists?(runtime_data_path)

    assert compiler_manifest_path |> tracked_artifact_paths() |> Enum.sort() ==
             Enum.sort([
               alerts_path,
               runtime_data_path
             ])

    assert is_binary(tracked_input_digest(compiler_manifest_path))

    assert :noop =
             SvgSpriteExAssets.compile_sprite_artifacts!(
               compile_path: compile_path,
               compiler_state_path: compiler_state_path(manifest_path),
               compiler_manifest_path: compiler_manifest_path,
               elixir_manifest_path: manifest_path,
               runtime_data_path: runtime_data_path,
               build_path: sprite_build_path,
               public_path: Config.public_path!(),
               source_root: svg_source_root
             )
  end

  defp manifest_modules(manifest_path) do
    manifest_path
    |> Mix.Compilers.Elixir.read_manifest()
    |> elem(0)
    |> case do
      modules when is_map(modules) -> Map.keys(modules)
      modules when is_list(modules) -> modules
      _modules -> []
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

        def icon_ref, do: sprite_ref("regular/xmark", sheet: #{inspect(sheet)})
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

        def icon_ref, do: inline_ref(#{inspect(name)})
      end
      """
    )

    source_path
  end

  defp write_plain_module!(source_dir, module) do
    source_path = fixture_source_path(source_dir, module)

    File.write!(
      source_path,
      """
      defmodule #{inspect(module)} do
        def ping, do: :pong
      end
      """
    )

    source_path
  end

  defp fixture_source_path(source_dir, module) do
    Path.join(source_dir, "#{Atom.to_string(module)}.ex")
  end

  defp compiler_manifest_path(manifest_path) do
    compiler_state_path(manifest_path)
    |> Path.join("compile.svg_sprite_ex_assets")
  end

  defp runtime_data_path(manifest_path) do
    compiler_state_path(manifest_path)
    |> Path.join("runtime_data.etf")
  end

  defp ref_snapshot_path(manifest_path, module) do
    SvgSpriteEx.Ref.ref_snapshot_path(module, compiler_state_path(manifest_path))
  end

  defp unique_module(suffix) do
    Module.concat([
      SvgSpriteEx,
      CompileTaskFixtures,
      :"#{suffix}_#{System.unique_integer([:positive])}"
    ])
  end

  defp tracked_artifact_paths(path) do
    case File.read(path) do
      {:ok, binary} ->
        %{artifact_paths: artifact_paths} = :erlang.binary_to_term(binary, [:safe])
        artifact_paths

      {:error, :enoent} ->
        []
    end
  end

  defp tracked_input_digest(path) do
    case File.read(path) do
      {:ok, binary} ->
        :erlang.binary_to_term(binary, [:safe])
        |> Map.get(:input_digest)

      {:error, :enoent} ->
        nil
    end
  end

  defp tracked_ref_snapshots_bootstrapped(path) do
    case File.read(path) do
      {:ok, binary} ->
        :erlang.binary_to_term(binary, [:safe])
        |> Map.get(:ref_snapshots_bootstrapped, false)

      {:error, :enoent} ->
        false
    end
  end

  defp read_ref_snapshot!(path) do
    path
    |> File.read!()
    |> :erlang.binary_to_term([:safe])
  end

  defp read_runtime_data!(path) do
    path
    |> File.read!()
    |> :erlang.binary_to_term([:safe])
  end

  defp temp_artifact_paths(root) do
    [
      Path.join(root, "*.tmp-*"),
      Path.join(root, "**/*.tmp-*")
    ]
    |> Enum.flat_map(&Path.wildcard/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp write_legacy_manifest!(path, artifact_paths) do
    File.write!(path, :erlang.term_to_binary(%{vsn: 1, artifact_paths: artifact_paths}))
  end

  defp write_legacy_ref_snapshot!(path, snapshot) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, :erlang.term_to_binary(snapshot))
  end

  defp elixir_manifest_path!(source_dir) do
    manifest_dir = Path.join(source_dir, ".mix")
    File.mkdir_p!(manifest_dir)
    Path.join(manifest_dir, "compile.elixir")
  end

  defp unique_svg_source_root!(suffix) do
    svg_source_root = unique_tmp_dir!("svg-root-#{suffix}")
    File.mkdir_p!(Path.join(svg_source_root, "regular"))

    write_svg_source!(
      svg_source_root,
      "regular/xmark",
      """
      <svg viewBox="0 0 24 24">
        <path d="M0 0h24v24H0z" />
      </svg>
      """
    )

    svg_source_root
  end

  defp write_svg_source!(svg_source_root, name, source) do
    path = Path.join(svg_source_root, "#{name}.svg")
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, source)
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
