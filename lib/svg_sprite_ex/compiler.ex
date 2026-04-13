defmodule SvgSpriteEx.Compiler do
  @moduledoc false

  alias SvgSpriteEx.Compiler.FileOps
  alias SvgSpriteEx.Compiler.Manifest
  alias SvgSpriteEx.Compiler.RefSnapshots
  alias SvgSpriteEx.Compiler.RuntimeDataWriter
  alias SvgSpriteEx.Compiler.SpriteBuilder
  alias SvgSpriteEx.Config
  alias SvgSpriteEx.Ref
  alias SvgSpriteEx.Source

  def default_compile_opts do
    compiler_state_path = compiler_state_path()

    [
      compile_path: Mix.Project.compile_path(),
      compiler_state_path: compiler_state_path,
      compiler_manifest_path: manifest_path(compiler_state_path),
      elixir_manifest_path: elixir_manifest_path(),
      runtime_data_path: RuntimeDataWriter.default_path(),
      build_path: Config.build_path!(),
      public_path: Config.public_path!(),
      source_root: Config.source_root!()
    ]
  end

  def compile_sprite_artifacts!(opts) do
    compile_path = Keyword.fetch!(opts, :compile_path)
    elixir_manifest_path = Keyword.get(opts, :elixir_manifest_path, elixir_manifest_path())
    compiler_state_path = Keyword.get(opts, :compiler_state_path, compiler_state_path())

    compiler_manifest_path =
      Keyword.get(opts, :compiler_manifest_path, manifest_path(compiler_state_path))

    runtime_data_path = Keyword.get(opts, :runtime_data_path, RuntimeDataWriter.default_path())
    build_path = Keyword.fetch!(opts, :build_path)
    public_path = Keyword.get(opts, :public_path, Config.public_path!())
    source_root = Keyword.fetch!(opts, :source_root)

    compiler_manifest = Manifest.read(compiler_manifest_path)
    modules = project_modules(elixir_manifest_path)

    {sprite_refs, inline_refs, ref_snapshot_result} =
      RefSnapshots.collect_project_refs(
        compile_path,
        compiler_state_path,
        modules
      )

    compiler_fingerprint = Keyword.get(opts, :compiler_fingerprint, compiler_fingerprint())

    input_digest =
      input_digest(
        sprite_refs,
        inline_refs,
        source_root,
        build_path,
        public_path,
        compiler_state_path,
        compiler_fingerprint,
        runtime_data_path
      )

    if Manifest.current?(compiler_manifest, input_digest) do
      FileOps.changed([ref_snapshot_result])
    else
      inline_sources = SpriteBuilder.load_inline_sources(inline_refs, source_root)

      sprite_metadata =
        SpriteBuilder.build_sprite_metadata(sprite_refs, build_path, public_path, source_root)

      inline_svg_infos = SpriteBuilder.build_inline_svg_infos(inline_sources)
      sprite_builds = SpriteBuilder.build_sprite_outputs(sprite_metadata, source_root)

      File.mkdir_p!(build_path)

      sprite_result = write_sprite_sheets(sprite_builds)

      runtime_data =
        RuntimeDataWriter.build_runtime_data(inline_sources, inline_svg_infos, sprite_metadata)

      runtime_data_result = RuntimeDataWriter.write(runtime_data_path, runtime_data)

      active_artifact_paths =
        active_artifact_paths(sprite_builds, runtime_data_path, runtime_data)

      manifest_cleanup_result =
        compiler_manifest
        |> Map.fetch!(:artifact_paths)
        |> Enum.reject(&(&1 in active_artifact_paths))
        |> FileOps.cleanup_artifact_paths()

      manifest_write_result =
        Manifest.write(
          compiler_manifest_path,
          active_artifact_paths,
          input_digest
        )

      RuntimeDataWriter.invalidate_cache()

      if Enum.all?(
           [
             ref_snapshot_result,
             sprite_result,
             runtime_data_result,
             manifest_cleanup_result,
             manifest_write_result
           ],
           &(&1 == :noop)
         ),
         do: :noop,
         else: :ok
    end
  end

  def manifest_path do
    manifest_path(compiler_state_path())
  end

  def manifest_path(compiler_state_path) do
    Manifest.path(compiler_state_path)
  end

  def clean do
    compiler_state_path = compiler_state_path()
    compiler_manifest_path = manifest_path(compiler_state_path)

    compiler_manifest_path
    |> Manifest.read()
    |> Map.fetch!(:artifact_paths)
    |> FileOps.cleanup_artifact_paths()

    File.rm(compiler_manifest_path)
    File.rm_rf(RefSnapshots.snapshots_path(compiler_state_path))
    FileOps.rm_if_exists(RuntimeDataWriter.default_path())
    RuntimeDataWriter.invalidate_cache()
    :ok
  end

  defp project_modules(elixir_manifest_path) do
    elixir_manifest_path
    |> Mix.Compilers.Elixir.read_manifest()
    |> elem(0)
    |> manifest_modules()
    |> Enum.sort_by(&Atom.to_string/1)
  end

  defp input_digest(
         sprite_refs,
         inline_refs,
         source_root,
         build_path,
         public_path,
         compiler_state_path,
         compiler_fingerprint,
         runtime_data_path
       ) do
    digest_input = %{
      sprite_refs: sprite_refs,
      inline_refs: inline_refs,
      asset_digests: asset_digests(sprite_refs, inline_refs, source_root),
      source_root: Path.expand(source_root),
      build_path: Path.expand(build_path),
      public_path: public_path,
      compiler_state_path: Path.expand(compiler_state_path),
      compiler_fingerprint: compiler_fingerprint,
      runtime_data_path: Path.expand(runtime_data_path)
    }

    term_digest(digest_input)
  end

  defp asset_digests(sprite_refs, inline_refs, source_root) do
    sprite_refs
    |> Enum.map(fn {_sheet, name} -> name end)
    |> Kernel.++(inline_refs)
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.map(fn name ->
      file_path = Source.source_file_path!(name, source_root)
      {name, file_path, file_digest(file_path)}
    end)
  end

  defp file_digest(path) do
    path
    |> File.read!()
    |> binary_digest()
  end

  defp binary_digest(binary) when is_binary(binary) do
    :crypto.hash(:sha256, binary)
  end

  defp term_digest(term) do
    term
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
  end

  defp active_artifact_paths(sprite_builds, runtime_data_path, runtime_data) do
    (Map.keys(sprite_builds) ++ RuntimeDataWriter.artifact_paths(runtime_data_path, runtime_data))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp write_sprite_sheets(sprite_builds) do
    sprite_builds
    |> Enum.map(fn {output_path, sprite_sheet} ->
      FileOps.write_if_changed(output_path, sprite_sheet)
    end)
    |> FileOps.changed()
  end

  defp manifest_modules(modules) when is_map(modules), do: Map.keys(modules)
  defp manifest_modules(modules) when is_list(modules), do: modules
  defp manifest_modules(_modules), do: []

  defp compiler_state_path do
    Ref.compiler_state_path!()
  end

  defp compiler_fingerprint do
    [
      __MODULE__,
      FileOps,
      Manifest,
      RefSnapshots,
      RuntimeDataWriter,
      SpriteBuilder,
      SvgSpriteEx.RuntimeData,
      SvgSpriteEx.InlineAsset,
      SvgSpriteEx.InlineSvgMeta,
      SvgSpriteEx.Ref,
      SvgSpriteEx.Source,
      SvgSpriteEx.SpriteMeta,
      SvgSpriteEx.SpriteSheet,
      SvgSpriteEx.SpriteSheetMeta
    ]
    |> Enum.map(fn module ->
      Code.ensure_loaded!(module)
      {module, module.module_info(:md5)}
    end)
    |> term_digest()
  end

  defp elixir_manifest_path do
    List.first(Mix.Tasks.Compile.Elixir.manifests())
  end
end
