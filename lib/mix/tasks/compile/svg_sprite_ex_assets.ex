defmodule Mix.Tasks.Compile.SvgSpriteExAssets do
  @moduledoc false

  use Mix.Task.Compiler

  @recursive true
  @shortdoc "Builds application SVG sprite sheets"
  @manifest_vsn 3

  alias SvgSpriteEx.Config
  alias SvgSpriteEx.RuntimeData
  alias SvgSpriteEx.InlineSvgMeta
  alias SvgSpriteEx.Ref
  alias SvgSpriteEx.Source
  alias SvgSpriteEx.SpriteMeta
  alias SvgSpriteEx.SpriteSheet
  alias SvgSpriteEx.SpriteSheetMeta

  @impl Mix.Task.Compiler
  def run(_args) do
    register_after_elixir_hook(default_compile_opts())
    :noop
  end

  @doc false
  def register_after_elixir_hook(opts) do
    Mix.Task.Compiler.after_compiler(:elixir, after_elixir_callback(opts))
  end

  @doc false
  def after_elixir_callback(opts) do
    fn
      {:error, diagnostics} ->
        {:error, diagnostics}

      {status, diagnostics} ->
        compile_sprite_artifacts!(opts)
        {status, diagnostics}
    end
  end

  @impl Mix.Task.Compiler
  def manifests do
    [compiler_manifest_path()]
  end

  @impl Mix.Task.Compiler
  def clean do
    compiler_state_path = compiler_state_path()
    compiler_manifest_path = compiler_manifest_path(compiler_state_path)

    compiler_manifest_path
    |> read_compiler_manifest()
    |> Map.fetch!(:artifact_paths)
    |> cleanup_artifact_paths()

    File.rm(compiler_manifest_path)
    File.rm_rf(ref_snapshots_path(compiler_state_path))
    rm_if_exists(runtime_data_path())
    invalidate_runtime_data_cache()
    :ok
  end

  def compile_sprite_artifacts!(opts) do
    compile_path = Keyword.fetch!(opts, :compile_path)
    elixir_manifest_path = Keyword.get(opts, :elixir_manifest_path, elixir_manifest_path())
    compiler_state_path = Keyword.get(opts, :compiler_state_path, compiler_state_path())

    compiler_manifest_path =
      Keyword.get(opts, :compiler_manifest_path, compiler_manifest_path(compiler_state_path))

    runtime_data_path = Keyword.get(opts, :runtime_data_path, runtime_data_path())
    build_path = Keyword.fetch!(opts, :build_path)
    public_path = Keyword.get(opts, :public_path, Config.public_path!())
    source_root = Keyword.fetch!(opts, :source_root)

    compiler_manifest = read_compiler_manifest(compiler_manifest_path)
    modules = project_modules(elixir_manifest_path)

    {sprite_refs, inline_refs, ref_snapshot_result} =
      collect_project_refs(
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

    if manifest_current?(compiler_manifest, input_digest) do
      changed([ref_snapshot_result])
    else
      inline_sources = load_inline_sources(inline_refs, source_root)
      sprite_metadata = build_sprite_metadata(sprite_refs, build_path, public_path, source_root)
      inline_svg_infos = build_inline_svg_infos(inline_sources)
      sprite_builds = build_sprite_outputs(sprite_metadata, source_root)

      File.mkdir_p!(build_path)

      sprite_result = write_sprite_sheets(sprite_builds)
      runtime_data = build_runtime_data(inline_sources, inline_svg_infos, sprite_metadata)
      runtime_data_result = write_runtime_data(runtime_data_path, runtime_data)

      active_artifact_paths =
        active_artifact_paths(sprite_builds, runtime_data_path, runtime_data)

      manifest_cleanup_result =
        compiler_manifest
        |> Map.fetch!(:artifact_paths)
        |> Enum.reject(&(&1 in active_artifact_paths))
        |> cleanup_artifact_paths()

      manifest_write_result =
        write_compiler_manifest(
          compiler_manifest_path,
          active_artifact_paths,
          input_digest
        )

      invalidate_runtime_data_cache()

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

  defp default_compile_opts do
    [
      compile_path: Mix.Project.compile_path(),
      compiler_state_path: compiler_state_path(),
      compiler_manifest_path: compiler_manifest_path(),
      elixir_manifest_path: elixir_manifest_path(),
      runtime_data_path: runtime_data_path(),
      build_path: Config.build_path!(),
      public_path: Config.public_path!(),
      source_root: Config.source_root!()
    ]
  end

  defp project_modules(elixir_manifest_path) do
    elixir_manifest_path
    |> Mix.Compilers.Elixir.read_manifest()
    |> elem(0)
    |> manifest_modules()
    |> Enum.sort_by(&Atom.to_string/1)
  end

  defp collect_project_refs(
         compile_path,
         compiler_state_path,
         modules
       ) do
    Code.prepend_path(compile_path)

    ref_modules = project_ref_modules(modules)

    active_snapshot_paths =
      Enum.map(ref_modules, &Ref.ref_snapshot_path(&1, compiler_state_path))

    stale_snapshot_result =
      compiler_state_path
      |> ref_snapshots_path()
      |> list_regular_files()
      |> Enum.reject(&(&1 in active_snapshot_paths))
      |> cleanup_artifact_paths()

    sprite_refs =
      ref_modules
      |> Enum.flat_map(& &1.__sprite_refs__())
      |> Enum.uniq()
      |> Enum.sort()

    inline_refs =
      ref_modules
      |> Enum.flat_map(& &1.__inline_refs__())
      |> Enum.uniq()
      |> Enum.sort()

    {sprite_refs, inline_refs, stale_snapshot_result}
  end

  defp build_sprite_metadata(sprite_refs, build_path, public_path, source_root) do
    sprite_refs
    |> Enum.group_by(fn {sheet, _name} -> sheet end, fn {_sheet, name} -> name end)
    |> Enum.sort_by(fn {sheet, _names} -> sheet end)
    |> Enum.map(fn {sheet, names} ->
      sheet_build_path = Ref.sheet_build_path(sheet, build_path)
      sheet_public_path = Ref.sheet_public_path(sheet, public_path)

      sheet_info = %SpriteSheetMeta{
        name: sheet,
        filename: Path.basename(sheet_build_path),
        build_path: sheet_build_path,
        public_path: sheet_public_path
      }

      sprites =
        Enum.map(names, fn name ->
          %SpriteMeta{
            name: name,
            sheet: sheet,
            sheet_public_path: sheet_public_path,
            source_path: Source.source_file_path!(name, source_root),
            sprite_id: Source.sprite_id_from_normalized(name)
          }
        end)

      {sheet_info, sprites}
    end)
  end

  defp build_sprite_outputs(sprite_metadata, source_root) do
    Enum.into(sprite_metadata, %{}, fn {%SpriteSheetMeta{build_path: build_path}, sprites} ->
      {build_path, SpriteSheet.build(Enum.map(sprites, & &1.name), source_root: source_root)}
    end)
  end

  defp load_inline_sources(inline_refs, source_root) do
    Enum.map(inline_refs, fn name ->
      Source.read!(name, source_root)
    end)
  end

  defp build_inline_svg_infos(inline_sources) do
    Enum.map(inline_sources, fn %Source{name: name, file_path: file_path} ->
      %InlineSvgMeta{
        name: name,
        source_path: file_path
      }
    end)
  end

  defp build_runtime_data(inline_sources, inline_svg_infos, sprite_metadata) do
    inline_assets =
      Map.new(inline_sources, fn %Source{
                                   name: name,
                                   attributes: attributes,
                                   inner_content: inner_content
                                 } ->
        {name, %SvgSpriteEx.InlineAsset{attributes: attributes, inner_content: inner_content}}
      end)

    inline_svg_map = Map.new(inline_svg_infos, &{&1.name, &1})

    sprite_sheet_map =
      Map.new(sprite_metadata, fn {sheet_info, _sprites} -> {sheet_info.name, sheet_info} end)

    sprites_in_sheet =
      Map.new(sprite_metadata, fn {sheet_info, sprites} -> {sheet_info.name, sprites} end)

    %{
      vsn: RuntimeData.runtime_data_vsn(),
      inline_assets: inline_assets,
      inline_svg_map: inline_svg_map,
      sprite_sheet_map: sprite_sheet_map,
      sprites_in_sheet: sprites_in_sheet
    }
  end

  defp runtime_data_artifact_paths(runtime_data_path, runtime_data) do
    if runtime_data == empty_runtime_data() do
      []
    else
      [runtime_data_path]
    end
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
      compiler_state_path: compiler_state_path,
      compiler_fingerprint: compiler_fingerprint,
      runtime_data_path: runtime_data_path
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
    (Map.keys(sprite_builds) ++ runtime_data_artifact_paths(runtime_data_path, runtime_data))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp manifest_modules(modules) when is_map(modules), do: Map.keys(modules)
  defp manifest_modules(modules) when is_list(modules), do: modules
  defp manifest_modules(_modules), do: []

  defp write_sprite_sheets(sprite_builds) do
    sprite_builds
    |> Enum.map(fn {output_path, sprite_sheet} ->
      write_if_changed(output_path, sprite_sheet)
    end)
    |> changed()
  end

  defp write_runtime_data(runtime_data_path, runtime_data) do
    if runtime_data == empty_runtime_data() do
      rm_if_exists(runtime_data_path)
    else
      write_if_changed(runtime_data_path, :erlang.term_to_binary(runtime_data))
    end
  end

  defp compiler_manifest_path do
    compiler_manifest_path(compiler_state_path())
  end

  defp compiler_manifest_path(compiler_state_path) do
    compiler_state_path
    |> Path.join("compile.svg_sprite_ex_assets")
  end

  defp runtime_data_path do
    Mix.Project.app_path()
    |> Path.join("priv/svg_sprite_ex/runtime_data.etf")
  end

  defp ref_snapshots_path(compiler_state_path) do
    Path.join(compiler_state_path, "refs")
  end

  defp empty_runtime_data do
    %{
      vsn: RuntimeData.runtime_data_vsn(),
      inline_assets: %{},
      inline_svg_map: %{},
      sprite_sheet_map: %{},
      sprites_in_sheet: %{}
    }
  end

  defp read_compiler_manifest(path) do
    case File.read(path) do
      {:ok, binary} ->
        case :erlang.binary_to_term(binary, [:safe]) do
          %{
            vsn: @manifest_vsn,
            artifact_paths: artifact_paths,
            input_digest: input_digest
          }
          when is_list(artifact_paths) and is_binary(input_digest) ->
            %{
              artifact_paths: artifact_paths,
              input_digest: input_digest
            }

          %{artifact_paths: artifact_paths} when is_list(artifact_paths) ->
            %{
              artifact_paths: artifact_paths,
              input_digest: nil
            }

          _other ->
            empty_manifest()
        end

      {:error, :enoent} ->
        empty_manifest()
    end
  end

  defp write_compiler_manifest(path, artifact_paths, input_digest) do
    manifest =
      %{
        vsn: @manifest_vsn,
        artifact_paths: artifact_paths,
        input_digest: input_digest
      }
      |> :erlang.term_to_binary()

    write_if_changed(path, manifest)
  end

  defp manifest_current?(
         %{artifact_paths: artifact_paths, input_digest: input_digest},
         input_digest
       )
       when is_binary(input_digest) do
    Enum.all?(artifact_paths, &File.exists?/1)
  end

  defp manifest_current?(_manifest, _input_digest), do: false

  defp empty_manifest,
    do: %{artifact_paths: [], input_digest: nil}

  defp cleanup_artifact_paths([]), do: :noop

  defp cleanup_artifact_paths(paths) do
    paths
    |> Enum.map(&rm_if_exists/1)
    |> changed()
  end

  defp project_ref_modules(modules) do
    Enum.filter(modules, fn module ->
      Code.ensure_loaded?(module) and function_exported?(module, :__sprite_refs__, 0) and
        function_exported?(module, :__inline_refs__, 0)
    end)
  end

  defp list_regular_files(path) do
    case File.ls(path) do
      {:ok, entries} ->
        entries
        |> Enum.map(&Path.join(path, &1))
        |> Enum.filter(&File.regular?/1)
        |> Enum.sort()

      {:error, :enoent} ->
        []
    end
  end

  defp write_if_changed(path, contents) do
    current_contents =
      case File.read(path) do
        {:ok, binary} -> binary
        {:error, :enoent} -> nil
      end

    if current_contents == contents do
      :noop
    else
      File.mkdir_p!(Path.dirname(path))
      write_atomically!(path, contents)
      :ok
    end
  end

  defp write_atomically!(path, contents) do
    temp_path = temp_write_path(path)

    try do
      File.write!(temp_path, contents)
      File.rename!(temp_path, path)
    after
      File.rm(temp_path)
    end
  end

  defp temp_write_path(path) do
    "#{path}.tmp-#{System.unique_integer([:positive, :monotonic])}"
  end

  defp rm_if_exists(path) do
    case File.rm(path) do
      :ok -> :ok
      {:error, :enoent} -> :noop
    end
  end

  defp invalidate_runtime_data_cache do
    runtime_data_module = SvgSpriteEx.RuntimeData

    if Code.ensure_loaded?(runtime_data_module) and
         function_exported?(runtime_data_module, :delete, 0) do
      runtime_data_module.delete()
    else
      :ok
    end
  end

  defp changed(results) do
    if Enum.any?(results, &(&1 == :ok)), do: :ok, else: :noop
  end

  defp compiler_state_path do
    Ref.compiler_state_path!()
  end

  defp compiler_fingerprint do
    [
      __MODULE__,
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
    Mix.Tasks.Compile.Elixir.manifests()
    |> List.first()
  end
end
