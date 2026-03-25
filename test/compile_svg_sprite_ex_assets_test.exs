defmodule Mix.Tasks.Compile.SvgSpriteExAssetsTest do
  use ExUnit.Case

  alias Mix.Tasks.Compile.SvgSpriteExAssets
  alias SvgSpriteEx.Config
  alias SvgSpriteEx.Ref

  test "compile_sprite_artifacts!/1 removes stale sprite outputs after modules disappear" do
    source_dir = unique_tmp_dir!("source-dir")
    compile_path = unique_tmp_dir!("compile-path")
    sprite_build_path = unique_tmp_dir!("sprite-build-path")
    manifest_path = elixir_manifest_path!(source_dir)
    svg_source_root = Config.source_root!()

    module = unique_module(:deleted_fixture)
    source_path = write_sprite_fixture_module!(source_dir, module, sheet: "alerts")

    assert :ok = compile_fixture_modules!(manifest_path, source_dir, compile_path)

    assert :ok =
             SvgSpriteExAssets.compile_sprite_artifacts!(
               compile_path: compile_path,
               elixir_manifest_path: manifest_path,
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
               elixir_manifest_path: manifest_path,
               build_path: sprite_build_path,
               source_root: svg_source_root
             )

    refute File.exists?(sheet_path)
  end

  test "compile_sprite_artifacts!/1 only removes manifest-tracked sprite outputs" do
    source_dir = unique_tmp_dir!("source-dir")
    compile_path = unique_tmp_dir!("compile-path")
    sprite_build_path = unique_tmp_dir!("sprite-build-path")
    manifest_path = elixir_manifest_path!(source_dir)
    compiler_manifest_path = compiler_manifest_path(manifest_path)
    svg_source_root = Config.source_root!()
    foreign_svg_path = Path.join(sprite_build_path, "foreign.svg")

    module = unique_module(:sprite_cleanup_fixture)
    write_sprite_fixture_module!(source_dir, module, sheet: "alerts")
    File.write!(foreign_svg_path, "<svg />")

    assert :ok = compile_fixture_modules!(manifest_path, source_dir, compile_path)

    assert :ok =
             SvgSpriteExAssets.compile_sprite_artifacts!(
               compile_path: compile_path,
               compiler_manifest_path: compiler_manifest_path,
               elixir_manifest_path: manifest_path,
               build_path: sprite_build_path,
               source_root: svg_source_root
             )

    File.rm!(fixture_source_path(source_dir, module))
    assert :ok = compile_fixture_modules!(manifest_path, source_dir, compile_path)

    assert :ok =
             SvgSpriteExAssets.compile_sprite_artifacts!(
               compile_path: compile_path,
               compiler_manifest_path: compiler_manifest_path,
               elixir_manifest_path: manifest_path,
               build_path: sprite_build_path,
               source_root: svg_source_root
             )

    refute File.exists?(Ref.sheet_build_path("alerts", sprite_build_path))
    assert File.exists?(foreign_svg_path)
  end

  test "compile_sprite_artifacts!/1 compiles an inline registry from manifest-backed inline refs" do
    source_dir = unique_tmp_dir!("source-dir")
    compile_path = unique_tmp_dir!("compile-path")
    sprite_build_path = unique_tmp_dir!("sprite-build-path")
    manifest_path = elixir_manifest_path!(source_dir)
    compiler_manifest_path = compiler_manifest_path(manifest_path)
    generated_source_path = generated_source_path(manifest_path)
    inline_metadata_source_path = inline_metadata_source_path(manifest_path)
    inline_registry_module = unique_inline_registry_module()
    inline_metadata_module = unique_inline_metadata_module()

    write_inline_fixture_module!(source_dir, unique_module(:inline_fixture),
      name: "regular/xmark"
    )

    assert :ok = compile_fixture_modules!(manifest_path, source_dir, compile_path)

    assert :ok =
             SvgSpriteExAssets.compile_sprite_artifacts!(
               compile_path: compile_path,
               compiler_manifest_path: compiler_manifest_path,
               elixir_manifest_path: manifest_path,
               generated_source_path: generated_source_path,
               inline_registry_module: inline_registry_module,
               inline_metadata_source_path: inline_metadata_source_path,
               inline_metadata_module: inline_metadata_module,
               build_path: sprite_build_path,
               source_root: Config.source_root!()
             )

    generated_source = File.read!(generated_source_path)

    assert generated_source =~ ~s|def fetch("regular/xmark")|
    assert generated_source =~ "@external_resource"
    assert String.ends_with?(generated_source, "\n")
    assert Code.ensure_loaded?(inline_registry_module)
    assert apply(inline_registry_module, :names, []) == ["regular/xmark"]
    assert match?({:ok, _asset}, apply(inline_registry_module, :fetch, ["regular/xmark"]))

    assert compiler_manifest_path |> tracked_artifact_paths() |> Enum.sort() ==
             Enum.sort([
               generated_beam_path(compile_path, inline_registry_module),
               generated_beam_path(compile_path, inline_metadata_module),
               generated_source_path,
               inline_metadata_source_path
             ])
  end

  test "compile_sprite_artifacts!/1 compiles a sprite metadata registry from manifest-backed sprite refs" do
    source_dir = unique_tmp_dir!("source-dir")
    compile_path = unique_tmp_dir!("compile-path")
    sprite_build_path = unique_tmp_dir!("sprite-build-path")
    manifest_path = elixir_manifest_path!(source_dir)
    compiler_manifest_path = compiler_manifest_path(manifest_path)
    sprite_metadata_source_path = sprite_metadata_source_path(manifest_path)
    sprite_metadata_module = unique_sprite_metadata_module()

    write_sprite_fixture_module!(source_dir, unique_module(:sprite_metadata_fixture),
      sheet: "alerts"
    )

    assert :ok = compile_fixture_modules!(manifest_path, source_dir, compile_path)

    assert :ok =
             SvgSpriteExAssets.compile_sprite_artifacts!(
               compile_path: compile_path,
               compiler_manifest_path: compiler_manifest_path,
               elixir_manifest_path: manifest_path,
               sprite_metadata_source_path: sprite_metadata_source_path,
               sprite_metadata_module: sprite_metadata_module,
               build_path: sprite_build_path,
               public_path: Config.public_path!(),
               source_root: Config.source_root!()
             )

    generated_source = File.read!(sprite_metadata_source_path)

    assert generated_source =~ ~s|def sprite_sheet("alerts")|
    assert generated_source =~ ~s|def sprites_in_sheet("alerts")|
    assert String.ends_with?(generated_source, "\n")
    assert Code.ensure_loaded?(sprite_metadata_module)

    assert sheet_info = apply(sprite_metadata_module, :sprite_sheet, ["alerts"])
    assert sheet_info.name == "alerts"
    assert sheet_info.filename == "alerts.svg"
    assert match?([_], apply(sprite_metadata_module, :sprites_in_sheet, ["alerts"]))

    assert compiler_manifest_path |> tracked_artifact_paths() |> Enum.sort() ==
             Enum.sort([
               generated_beam_path(compile_path, sprite_metadata_module),
               Ref.sheet_build_path("alerts", sprite_build_path),
               sprite_metadata_source_path
             ])
  end

  test "compile_sprite_artifacts!/1 removes the generated inline registry when inline refs disappear" do
    source_dir = unique_tmp_dir!("source-dir")
    compile_path = unique_tmp_dir!("compile-path")
    sprite_build_path = unique_tmp_dir!("sprite-build-path")
    manifest_path = elixir_manifest_path!(source_dir)
    compiler_manifest_path = compiler_manifest_path(manifest_path)
    generated_source_path = generated_source_path(manifest_path)
    inline_metadata_source_path = inline_metadata_source_path(manifest_path)
    inline_registry_module = unique_inline_registry_module()
    inline_metadata_module = unique_inline_metadata_module()

    module = unique_module(:inline_deleted_fixture)
    source_path = write_inline_fixture_module!(source_dir, module, name: "regular/xmark")

    assert :ok = compile_fixture_modules!(manifest_path, source_dir, compile_path)

    assert :ok =
             SvgSpriteExAssets.compile_sprite_artifacts!(
               compile_path: compile_path,
               compiler_manifest_path: compiler_manifest_path,
               elixir_manifest_path: manifest_path,
               generated_source_path: generated_source_path,
               inline_registry_module: inline_registry_module,
               inline_metadata_source_path: inline_metadata_source_path,
               inline_metadata_module: inline_metadata_module,
               build_path: sprite_build_path,
               source_root: Config.source_root!()
             )

    assert File.exists?(generated_source_path)
    assert File.exists?(generated_beam_path(compile_path, inline_registry_module))
    assert File.exists?(inline_metadata_source_path)
    assert File.exists?(generated_beam_path(compile_path, inline_metadata_module))

    File.rm!(source_path)
    assert :ok = compile_fixture_modules!(manifest_path, source_dir, compile_path)

    assert :ok =
             SvgSpriteExAssets.compile_sprite_artifacts!(
               compile_path: compile_path,
               compiler_manifest_path: compiler_manifest_path,
               elixir_manifest_path: manifest_path,
               generated_source_path: generated_source_path,
               inline_registry_module: inline_registry_module,
               inline_metadata_source_path: inline_metadata_source_path,
               inline_metadata_module: inline_metadata_module,
               build_path: sprite_build_path,
               source_root: Config.source_root!()
             )

    refute File.exists?(generated_source_path)
    refute File.exists?(generated_beam_path(compile_path, inline_registry_module))
    refute File.exists?(inline_metadata_source_path)
    refute File.exists?(generated_beam_path(compile_path, inline_metadata_module))
    assert tracked_artifact_paths(compiler_manifest_path) == []
  end

  test "compile_sprite_artifacts!/1 removes the generated sprite metadata registry when sprite refs disappear" do
    source_dir = unique_tmp_dir!("source-dir")
    compile_path = unique_tmp_dir!("compile-path")
    sprite_build_path = unique_tmp_dir!("sprite-build-path")
    manifest_path = elixir_manifest_path!(source_dir)
    compiler_manifest_path = compiler_manifest_path(manifest_path)
    sprite_metadata_source_path = sprite_metadata_source_path(manifest_path)
    sprite_metadata_module = unique_sprite_metadata_module()

    module = unique_module(:sprite_metadata_deleted_fixture)
    source_path = write_sprite_fixture_module!(source_dir, module, sheet: "alerts")

    assert :ok = compile_fixture_modules!(manifest_path, source_dir, compile_path)

    assert :ok =
             SvgSpriteExAssets.compile_sprite_artifacts!(
               compile_path: compile_path,
               compiler_manifest_path: compiler_manifest_path,
               elixir_manifest_path: manifest_path,
               sprite_metadata_source_path: sprite_metadata_source_path,
               sprite_metadata_module: sprite_metadata_module,
               build_path: sprite_build_path,
               public_path: Config.public_path!(),
               source_root: Config.source_root!()
             )

    assert File.exists?(sprite_metadata_source_path)
    assert File.exists?(generated_beam_path(compile_path, sprite_metadata_module))

    File.rm!(source_path)
    assert :ok = compile_fixture_modules!(manifest_path, source_dir, compile_path)

    assert :ok =
             SvgSpriteExAssets.compile_sprite_artifacts!(
               compile_path: compile_path,
               compiler_manifest_path: compiler_manifest_path,
               elixir_manifest_path: manifest_path,
               sprite_metadata_source_path: sprite_metadata_source_path,
               sprite_metadata_module: sprite_metadata_module,
               build_path: sprite_build_path,
               public_path: Config.public_path!(),
               source_root: Config.source_root!()
             )

    refute File.exists?(sprite_metadata_source_path)
    refute File.exists?(generated_beam_path(compile_path, sprite_metadata_module))
    assert tracked_artifact_paths(compiler_manifest_path) == []
  end

  test "compile_sprite_artifacts!/1 rewrites the inline registry when inline svg contents change" do
    source_dir = unique_tmp_dir!("source-dir")
    compile_path = unique_tmp_dir!("compile-path")
    sprite_build_path = unique_tmp_dir!("sprite-build-path")
    manifest_path = elixir_manifest_path!(source_dir)
    compiler_manifest_path = compiler_manifest_path(manifest_path)
    generated_source_path = generated_source_path(manifest_path)
    initial_inline_registry_module = unique_inline_registry_module()
    svg_source_root = unique_svg_source_root!("inline-change")

    write_inline_fixture_module!(source_dir, unique_module(:inline_changed_fixture),
      name: "regular/xmark"
    )

    assert :ok = compile_fixture_modules!(manifest_path, source_dir, compile_path)

    assert :ok =
             SvgSpriteExAssets.compile_sprite_artifacts!(
               compile_path: compile_path,
               compiler_manifest_path: compiler_manifest_path,
               elixir_manifest_path: manifest_path,
               generated_source_path: generated_source_path,
               inline_registry_module: initial_inline_registry_module,
               build_path: sprite_build_path,
               source_root: svg_source_root
             )

    first_source = File.read!(generated_source_path)

    File.write!(
      Path.join(svg_source_root, "regular/xmark.svg"),
      """
      <svg viewBox="0 0 24 24" fill="currentColor">
        <path d="M1 1h22v22H1z" />
      </svg>
      """
    )

    updated_inline_registry_module = unique_inline_registry_module()

    assert :ok =
             SvgSpriteExAssets.compile_sprite_artifacts!(
               compile_path: compile_path,
               compiler_manifest_path: compiler_manifest_path,
               elixir_manifest_path: manifest_path,
               generated_source_path: generated_source_path,
               inline_registry_module: updated_inline_registry_module,
               build_path: sprite_build_path,
               source_root: svg_source_root
             )

    second_source = File.read!(generated_source_path)

    refute first_source =~ "fill"
    assert second_source =~ "fill"
    assert second_source =~ "M1 1h22v22H1z"
  end

  test "compile_sprite_artifacts!/1 noops when the manifest-backed refs are unchanged" do
    source_dir = unique_tmp_dir!("source-dir")
    compile_path = unique_tmp_dir!("compile-path")
    sprite_build_path = unique_tmp_dir!("sprite-build-path")
    manifest_path = elixir_manifest_path!(source_dir)
    compiler_manifest_path = compiler_manifest_path(manifest_path)
    generated_source_path = generated_source_path(manifest_path)
    inline_registry_module = unique_inline_registry_module()
    inline_metadata_source_path = inline_metadata_source_path(manifest_path)
    inline_metadata_module = unique_inline_metadata_module()
    sprite_metadata_source_path = sprite_metadata_source_path(manifest_path)
    sprite_metadata_module = unique_sprite_metadata_module()
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
               compiler_manifest_path: compiler_manifest_path,
               elixir_manifest_path: manifest_path,
               generated_source_path: generated_source_path,
               inline_registry_module: inline_registry_module,
               inline_metadata_source_path: inline_metadata_source_path,
               inline_metadata_module: inline_metadata_module,
               sprite_metadata_source_path: sprite_metadata_source_path,
               sprite_metadata_module: sprite_metadata_module,
               build_path: sprite_build_path,
               public_path: Config.public_path!(),
               source_root: svg_source_root
             )

    alerts_path = Ref.sheet_build_path("alerts", sprite_build_path)

    assert File.exists?(alerts_path)
    assert File.read!(alerts_path) =~ "<symbol"
    assert File.exists?(generated_source_path)

    assert compiler_manifest_path |> tracked_artifact_paths() |> Enum.sort() ==
             Enum.sort([
               alerts_path,
               generated_beam_path(compile_path, inline_registry_module),
               generated_beam_path(compile_path, inline_metadata_module),
               generated_beam_path(compile_path, sprite_metadata_module),
               generated_source_path,
               inline_metadata_source_path,
               sprite_metadata_source_path
             ])

    assert :noop =
             SvgSpriteExAssets.compile_sprite_artifacts!(
               compile_path: compile_path,
               compiler_manifest_path: compiler_manifest_path,
               elixir_manifest_path: manifest_path,
               generated_source_path: generated_source_path,
               inline_registry_module: inline_registry_module,
               inline_metadata_source_path: inline_metadata_source_path,
               inline_metadata_module: inline_metadata_module,
               sprite_metadata_source_path: sprite_metadata_source_path,
               sprite_metadata_module: sprite_metadata_module,
               build_path: sprite_build_path,
               public_path: Config.public_path!(),
               source_root: svg_source_root
             )
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

  defp generated_beam_path(compile_path, inline_registry_module) do
    Path.join(compile_path, Atom.to_string(inline_registry_module) <> ".beam")
  end

  defp generated_source_path(manifest_path) do
    manifest_path
    |> Path.dirname()
    |> Path.join("svg_sprite_ex_generated_inline_icons.ex")
  end

  defp inline_metadata_source_path(manifest_path) do
    manifest_path
    |> Path.dirname()
    |> Path.join("svg_sprite_ex_generated_inline_svgs.ex")
  end

  defp sprite_metadata_source_path(manifest_path) do
    manifest_path
    |> Path.dirname()
    |> Path.join("svg_sprite_ex_generated_sprite_sheets.ex")
  end

  defp compiler_manifest_path(manifest_path) do
    manifest_path
    |> Path.dirname()
    |> Path.join("compile.svg_sprite_ex_assets")
  end

  defp unique_module(suffix) do
    Module.concat([
      SvgSpriteEx,
      CompileTaskFixtures,
      :"#{suffix}_#{System.unique_integer([:positive])}"
    ])
  end

  defp unique_inline_registry_module do
    Module.concat([
      SvgSpriteEx,
      Generated,
      :"InlineIcons#{System.unique_integer([:positive])}"
    ])
  end

  defp unique_inline_metadata_module do
    Module.concat([
      SvgSpriteEx,
      Generated,
      :"InlineSvgs#{System.unique_integer([:positive])}"
    ])
  end

  defp unique_sprite_metadata_module do
    Module.concat([
      SvgSpriteEx,
      Generated,
      :"SpriteSheets#{System.unique_integer([:positive])}"
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

  defp elixir_manifest_path!(source_dir) do
    manifest_dir = Path.join(source_dir, ".mix")
    File.mkdir_p!(manifest_dir)
    Path.join(manifest_dir, "compile.elixir")
  end

  defp unique_svg_source_root!(suffix) do
    svg_source_root = unique_tmp_dir!("svg-root-#{suffix}")
    File.mkdir_p!(Path.join(svg_source_root, "regular"))

    File.write!(
      Path.join(svg_source_root, "regular/xmark.svg"),
      """
      <svg viewBox="0 0 24 24">
        <path d="M0 0h24v24H0z" />
      </svg>
      """
    )

    svg_source_root
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
