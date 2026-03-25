defmodule Mix.Tasks.Compile.SvgSpriteExAssets do
  @moduledoc false

  use Mix.Task.Compiler

  @recursive true
  @shortdoc "Builds application SVG sprite sheets"
  @manifest_vsn 2

  alias SvgSpriteEx.Config
  alias SvgSpriteEx.InlineSvgMeta
  alias SvgSpriteEx.Ref
  alias SvgSpriteEx.Source
  alias SvgSpriteEx.SpriteMeta
  alias SvgSpriteEx.SpriteSheet
  alias SvgSpriteEx.SpriteSheetMeta

  @inline_registry_module SvgSpriteEx.Generated.InlineIcons
  @inline_metadata_module SvgSpriteEx.Generated.InlineSvgs
  @sprite_metadata_module SvgSpriteEx.Generated.SpriteSheets

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
    compile_path = Mix.Project.compile_path()
    compiler_manifest_path = compiler_manifest_path()

    cleanup_generated_module(compile_path, generated_source_path(), @inline_registry_module)
    cleanup_generated_module(compile_path, inline_metadata_source_path(), @inline_metadata_module)
    cleanup_generated_module(compile_path, sprite_metadata_source_path(), @sprite_metadata_module)

    compiler_manifest_path
    |> read_compiler_manifest()
    |> Map.fetch!(:artifact_paths)
    |> cleanup_artifact_paths()

    File.rm(compiler_manifest_path)
    :ok
  end

  def compile_sprite_artifacts!(opts) do
    compile_path = Keyword.fetch!(opts, :compile_path)
    elixir_manifest_path = Keyword.get(opts, :elixir_manifest_path, elixir_manifest_path())

    compiler_manifest_path =
      Keyword.get(opts, :compiler_manifest_path, compiler_manifest_path(elixir_manifest_path))

    generated_source_path =
      Keyword.get(opts, :generated_source_path, generated_source_path(elixir_manifest_path))

    inline_metadata_source_path =
      Keyword.get(
        opts,
        :inline_metadata_source_path,
        inline_metadata_source_path(elixir_manifest_path)
      )

    sprite_metadata_source_path =
      Keyword.get(
        opts,
        :sprite_metadata_source_path,
        sprite_metadata_source_path(elixir_manifest_path)
      )

    inline_registry_module = Keyword.get(opts, :inline_registry_module, @inline_registry_module)
    inline_metadata_module = Keyword.get(opts, :inline_metadata_module, @inline_metadata_module)
    sprite_metadata_module = Keyword.get(opts, :sprite_metadata_module, @sprite_metadata_module)
    build_path = Keyword.fetch!(opts, :build_path)
    public_path = Keyword.get(opts, :public_path, Config.public_path!())
    source_root = Keyword.fetch!(opts, :source_root)

    modules = project_modules(compile_path, elixir_manifest_path)

    sprite_refs = collect_project_refs(modules, &sprite_refs/1)
    inline_refs = collect_project_refs(modules, &inline_refs/1)
    compiler_manifest = read_compiler_manifest(compiler_manifest_path)

    input_digest =
      input_digest(
        sprite_refs,
        inline_refs,
        source_root,
        build_path,
        public_path,
        generated_source_path,
        inline_metadata_source_path,
        sprite_metadata_source_path,
        inline_registry_module,
        inline_metadata_module,
        sprite_metadata_module
      )

    if manifest_current?(compiler_manifest, input_digest) do
      :noop
    else
      inline_sources = load_inline_sources(inline_refs, source_root)
      sprite_metadata = build_sprite_metadata(sprite_refs, build_path, public_path, source_root)
      inline_svg_infos = build_inline_svg_infos(inline_sources)
      sprite_builds = build_sprite_outputs(sprite_metadata, source_root)

      File.mkdir_p!(build_path)

      sprite_result = write_sprite_sheets(sprite_builds)

      inline_result =
        write_inline_registry(
          compile_path,
          generated_source_path,
          inline_registry_module,
          inline_sources
        )

      sprite_metadata_result =
        write_sprite_metadata_registry(
          compile_path,
          sprite_metadata_source_path,
          sprite_metadata_module,
          sprite_metadata
        )

      inline_metadata_result =
        write_inline_metadata_registry(
          compile_path,
          inline_metadata_source_path,
          inline_metadata_module,
          inline_svg_infos
        )

      active_artifact_paths =
        active_artifact_paths(
          sprite_builds,
          compile_path,
          generated_source_path,
          inline_sources,
          inline_registry_module,
          sprite_metadata_source_path,
          sprite_metadata,
          sprite_metadata_module,
          inline_metadata_source_path,
          inline_svg_infos,
          inline_metadata_module
        )

      manifest_cleanup_result =
        compiler_manifest
        |> Map.fetch!(:artifact_paths)
        |> Enum.reject(&(&1 in active_artifact_paths))
        |> cleanup_artifact_paths()

      manifest_write_result =
        write_compiler_manifest(compiler_manifest_path, active_artifact_paths, input_digest)

      if Enum.all?(
           [
             sprite_result,
             inline_result,
             sprite_metadata_result,
             inline_metadata_result,
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
      compiler_manifest_path: compiler_manifest_path(),
      elixir_manifest_path: elixir_manifest_path(),
      generated_source_path: generated_source_path(),
      inline_metadata_source_path: inline_metadata_source_path(),
      sprite_metadata_source_path: sprite_metadata_source_path(),
      inline_registry_module: @inline_registry_module,
      inline_metadata_module: @inline_metadata_module,
      sprite_metadata_module: @sprite_metadata_module,
      build_path: Config.build_path!(),
      public_path: Config.public_path!(),
      source_root: Config.source_root!()
    ]
  end

  defp project_modules(compile_path, elixir_manifest_path) do
    Code.prepend_path(compile_path)

    elixir_manifest_path
    |> Mix.Compilers.Elixir.read_manifest()
    |> elem(0)
    |> manifest_modules()
    |> Enum.filter(&Code.ensure_loaded?/1)
    |> Enum.sort_by(&Atom.to_string/1)
  end

  defp collect_project_refs(modules, extractor) do
    modules
    |> Enum.flat_map(extractor)
    |> Enum.uniq()
    |> Enum.sort()
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
            source_path: Source.source_file_path!(name, source_root),
            sprite_id: Source.sprite_id_from_normalized(name),
            href: Ref.sprite_href(name, source_root, sheet, public_path)
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

  defp input_digest(
         sprite_refs,
         inline_refs,
         source_root,
         build_path,
         public_path,
         generated_source_path,
         inline_metadata_source_path,
         sprite_metadata_source_path,
         inline_registry_module,
         inline_metadata_module,
         sprite_metadata_module
       ) do
    digest_input = %{
      sprite_refs: sprite_refs,
      inline_refs: inline_refs,
      asset_digests: asset_digests(sprite_refs, inline_refs, source_root),
      source_root: Path.expand(source_root),
      build_path: Path.expand(build_path),
      public_path: public_path,
      generated_source_path: generated_source_path,
      inline_metadata_source_path: inline_metadata_source_path,
      sprite_metadata_source_path: sprite_metadata_source_path,
      inline_registry_module: inline_registry_module,
      inline_metadata_module: inline_metadata_module,
      sprite_metadata_module: sprite_metadata_module
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
    |> term_digest()
  end

  defp term_digest(term) do
    term
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
  end

  defp active_artifact_paths(
         sprite_builds,
         compile_path,
         generated_source_path,
         inline_sources,
         inline_registry_module,
         sprite_metadata_source_path,
         sprite_metadata,
         sprite_metadata_module,
         inline_metadata_source_path,
         inline_svg_infos,
         inline_metadata_module
       ) do
    sprite_artifacts = Map.keys(sprite_builds)

    inline_artifacts =
      generated_module_artifact_paths(
        compile_path,
        generated_source_path,
        inline_sources,
        inline_registry_module
      )

    sprite_metadata_artifacts =
      generated_module_artifact_paths(
        compile_path,
        sprite_metadata_source_path,
        sprite_metadata,
        sprite_metadata_module
      )

    inline_metadata_artifacts =
      generated_module_artifact_paths(
        compile_path,
        inline_metadata_source_path,
        inline_svg_infos,
        inline_metadata_module
      )

    (sprite_artifacts ++
       inline_artifacts ++ sprite_metadata_artifacts ++ inline_metadata_artifacts)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp manifest_modules(modules) when is_map(modules), do: Map.keys(modules)
  defp manifest_modules(modules) when is_list(modules), do: modules
  defp manifest_modules(_modules), do: []

  defp sprite_refs(module) do
    if function_exported?(module, :__sprite_refs__, 0) do
      module.__sprite_refs__()
    else
      []
    end
  end

  defp inline_refs(module) do
    if function_exported?(module, :__inline_refs__, 0) do
      module.__inline_refs__()
    else
      []
    end
  end

  defp write_sprite_sheets(sprite_builds) do
    sprite_builds
    |> Enum.map(fn {output_path, sprite_sheet} ->
      current_sprite =
        case File.read(output_path) do
          {:ok, contents} -> contents
          {:error, :enoent} -> nil
        end

      if current_sprite == sprite_sheet do
        :noop
      else
        File.write!(output_path, sprite_sheet)
        :ok
      end
    end)
    |> changed()
  end

  defp write_inline_registry(
         compile_path,
         generated_source_path,
         inline_registry_module,
         []
       ) do
    cleanup_generated_module(compile_path, generated_source_path, inline_registry_module)
  end

  defp write_inline_registry(
         compile_path,
         generated_source_path,
         inline_registry_module,
         inline_sources
       ) do
    source = build_inline_registry_source(inline_registry_module, inline_sources)

    write_generated_module(
      compile_path,
      generated_source_path,
      inline_registry_module,
      source,
      "inline registry"
    )
  end

  defp write_generated_source(path, source) do
    write_if_changed(path, source)
  end

  defp write_sprite_metadata_registry(
         compile_path,
         generated_source_path,
         sprite_metadata_module,
         []
       ) do
    cleanup_generated_module(compile_path, generated_source_path, sprite_metadata_module)
  end

  defp write_sprite_metadata_registry(
         compile_path,
         generated_source_path,
         sprite_metadata_module,
         sprite_metadata
       ) do
    source = build_sprite_metadata_registry_source(sprite_metadata_module, sprite_metadata)

    write_generated_module(
      compile_path,
      generated_source_path,
      sprite_metadata_module,
      source,
      "sprite metadata registry"
    )
  end

  defp write_inline_metadata_registry(
         compile_path,
         generated_source_path,
         inline_metadata_module,
         []
       ) do
    cleanup_generated_module(compile_path, generated_source_path, inline_metadata_module)
  end

  defp write_inline_metadata_registry(
         compile_path,
         generated_source_path,
         inline_metadata_module,
         inline_svg_infos
       ) do
    source = build_inline_metadata_registry_source(inline_metadata_module, inline_svg_infos)

    write_generated_module(
      compile_path,
      generated_source_path,
      inline_metadata_module,
      source,
      "inline metadata registry"
    )
  end

  defp write_generated_module(
         compile_path,
         generated_source_path,
         generated_module,
         source,
         description
       ) do
    write_status = write_generated_source(generated_source_path, source)

    compile_status =
      compile_generated_module(
        compile_path,
        generated_source_path,
        generated_module,
        write_status,
        description
      )

    changed([write_status, compile_status])
  end

  defp compile_generated_module(
         compile_path,
         generated_source_path,
         generated_module,
         write_status,
         description
       ) do
    beam_path = generated_beam_path(compile_path, generated_module)

    if write_status == :noop and File.exists?(beam_path) do
      :noop
    else
      unload_generated_module(generated_module)

      case Kernel.ParallelCompiler.compile_to_path([generated_source_path], compile_path,
             return_diagnostics: true
           ) do
        {:ok, _modules, _warnings} ->
          unload_generated_module(generated_module)
          :ok

        {:error, errors, warnings} ->
          diagnostics =
            Enum.map(List.wrap(errors), &diagnostic_message/1) ++ warning_messages(warnings)

          raise Mix.Error,
            message:
              "failed to compile generated #{description}:\n#{Enum.join(diagnostics, "\n")}"
      end
    end
  end

  defp cleanup_generated_module(compile_path, generated_source_path, generated_module) do
    unload_generated_module(generated_module)

    changed([
      rm_if_exists(generated_source_path),
      rm_if_exists(generated_beam_path(compile_path, generated_module))
    ])
  end

  defp generated_module_artifact_paths(
         _compile_path,
         _generated_source_path,
         [],
         _generated_module
       ),
       do: []

  defp generated_module_artifact_paths(
         compile_path,
         generated_source_path,
         _entries,
         generated_module
       ) do
    [generated_source_path, generated_beam_path(compile_path, generated_module)]
  end

  defp build_inline_registry_source(inline_registry_module, inline_sources) do
    inline_registry_module
    |> build_inline_registry_ast(inline_sources)
    |> Macro.to_string()
    |> Kernel.<>("\n")
  end

  defp build_inline_registry_ast(inline_registry_module, inline_sources) do
    external_resource_asts =
      Enum.map(inline_sources, fn %Source{file_path: file_path} ->
        quote do
          @external_resource unquote(file_path)
        end
      end)

    fetch_clause_asts =
      Enum.map(inline_sources, fn %Source{
                                    name: name,
                                    attributes: attributes,
                                    inner_content: inner_content
                                  } ->
        attrs_ast = literal_map_ast(attributes)

        quote do
          def fetch(unquote(name)) do
            {:ok,
             %InlineAsset{
               attributes: unquote(attrs_ast),
               inner_content: unquote(inner_content)
             }}
          end
        end
      end)

    inline_names = Enum.map(inline_sources, & &1.name)

    quote do
      defmodule unquote(inline_registry_module) do
        @moduledoc false

        alias SvgSpriteEx.InlineAsset

        unquote_splicing(external_resource_asts)

        @spec fetch(String.t()) :: {:ok, InlineAsset.t()} | :error
        unquote_splicing(fetch_clause_asts)
        def fetch(_name), do: :error

        @spec names() :: [String.t()]
        def names, do: unquote(inline_names)
      end
    end
  end

  defp build_sprite_metadata_registry_source(sprite_metadata_module, sprite_metadata) do
    sprite_metadata_module
    |> build_sprite_metadata_registry_ast(sprite_metadata)
    |> Macro.to_string()
    |> Kernel.<>("\n")
  end

  defp build_sprite_metadata_registry_ast(sprite_metadata_module, sprite_metadata) do
    sprite_sheets = Enum.map(sprite_metadata, fn {sheet_info, _sprites} -> sheet_info end)

    sprite_sheet_clause_asts =
      Enum.map(sprite_metadata, fn {%SpriteSheetMeta{name: name} = sheet_info, _sprites} ->
        sheet_info_ast = Macro.escape(sheet_info)

        quote do
          def sprite_sheet(unquote(name)), do: unquote(sheet_info_ast)
        end
      end)

    sprites_in_sheet_clause_asts =
      Enum.map(sprite_metadata, fn {%SpriteSheetMeta{name: name}, sprites} ->
        sprites_ast = Macro.escape(sprites)

        quote do
          def sprites_in_sheet(unquote(name)), do: unquote(sprites_ast)
        end
      end)

    sprite_sheets_ast = Macro.escape(sprite_sheets)

    quote do
      defmodule unquote(sprite_metadata_module) do
        @moduledoc false

        alias SvgSpriteEx.SpriteMeta
        alias SvgSpriteEx.SpriteSheetMeta

        @spec sprite_sheets() :: [SpriteSheetMeta.t()]
        def sprite_sheets, do: unquote(sprite_sheets_ast)

        @spec sprite_sheet(String.t()) :: SpriteSheetMeta.t() | nil
        unquote_splicing(sprite_sheet_clause_asts)
        def sprite_sheet(_name), do: nil

        @spec sprites_in_sheet(String.t()) :: [SpriteMeta.t()]
        unquote_splicing(sprites_in_sheet_clause_asts)
        def sprites_in_sheet(_name), do: []
      end
    end
  end

  defp build_inline_metadata_registry_source(inline_metadata_module, inline_svg_infos) do
    inline_metadata_module
    |> build_inline_metadata_registry_ast(inline_svg_infos)
    |> Macro.to_string()
    |> Kernel.<>("\n")
  end

  defp build_inline_metadata_registry_ast(inline_metadata_module, inline_svg_infos) do
    inline_svg_clause_asts =
      Enum.map(inline_svg_infos, fn %InlineSvgMeta{name: name} = inline_svg_info ->
        inline_svg_info_ast = Macro.escape(inline_svg_info)

        quote do
          def inline_svg(unquote(name)), do: unquote(inline_svg_info_ast)
        end
      end)

    inline_svg_infos_ast = Macro.escape(inline_svg_infos)

    quote do
      defmodule unquote(inline_metadata_module) do
        @moduledoc false

        alias SvgSpriteEx.InlineSvgMeta

        @spec inline_svgs() :: [InlineSvgMeta.t()]
        def inline_svgs, do: unquote(inline_svg_infos_ast)

        @spec inline_svg(String.t()) :: InlineSvgMeta.t() | nil
        unquote_splicing(inline_svg_clause_asts)
        def inline_svg(_name), do: nil
      end
    end
  end

  defp generated_beam_path(compile_path, generated_module) do
    Path.join(compile_path, Atom.to_string(generated_module) <> ".beam")
  end

  defp generated_source_path do
    generated_source_path(elixir_manifest_path())
  end

  defp compiler_manifest_path do
    compiler_manifest_path(elixir_manifest_path())
  end

  defp compiler_manifest_path(elixir_manifest_path) do
    elixir_manifest_path
    |> Path.dirname()
    |> Path.join("compile.svg_sprite_ex_assets")
  end

  defp inline_metadata_source_path do
    inline_metadata_source_path(elixir_manifest_path())
  end

  defp sprite_metadata_source_path do
    sprite_metadata_source_path(elixir_manifest_path())
  end

  defp generated_source_path(elixir_manifest_path) do
    elixir_manifest_path
    |> Path.dirname()
    |> Path.join("svg_sprite_ex_generated_inline_icons.ex")
  end

  defp inline_metadata_source_path(elixir_manifest_path) do
    elixir_manifest_path
    |> Path.dirname()
    |> Path.join("svg_sprite_ex_generated_inline_svgs.ex")
  end

  defp sprite_metadata_source_path(elixir_manifest_path) do
    elixir_manifest_path
    |> Path.dirname()
    |> Path.join("svg_sprite_ex_generated_sprite_sheets.ex")
  end

  defp unload_generated_module(generated_module) do
    :code.purge(generated_module)
    :code.delete(generated_module)
    :ok
  end

  defp warning_messages(%{compile_warnings: compile_warnings, runtime_warnings: runtime_warnings}) do
    Enum.map(compile_warnings ++ runtime_warnings, &diagnostic_message/1)
  end

  defp warning_messages(_warnings), do: []

  defp diagnostic_message(%{message: message}), do: message
  defp diagnostic_message(message) when is_binary(message), do: message
  defp diagnostic_message(other), do: inspect(other)

  defp literal_map_ast(map) do
    {:%{}, [], Enum.map(Enum.sort(map), fn {key, value} -> {key, value} end)}
  end

  defp read_compiler_manifest(path) do
    case File.read(path) do
      {:ok, binary} ->
        case :erlang.binary_to_term(binary, [:safe]) do
          %{vsn: @manifest_vsn, artifact_paths: artifact_paths, input_digest: input_digest}
          when is_list(artifact_paths) and is_binary(input_digest) ->
            %{artifact_paths: artifact_paths, input_digest: input_digest}

          %{artifact_paths: artifact_paths} when is_list(artifact_paths) ->
            %{artifact_paths: artifact_paths, input_digest: nil}

          _other ->
            empty_manifest()
        end

      {:error, :enoent} ->
        empty_manifest()
    end
  end

  defp write_compiler_manifest(path, artifact_paths, input_digest) do
    manifest =
      %{vsn: @manifest_vsn, artifact_paths: artifact_paths, input_digest: input_digest}
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

  defp empty_manifest, do: %{artifact_paths: [], input_digest: nil}

  defp cleanup_artifact_paths([]), do: :noop

  defp cleanup_artifact_paths(paths) do
    paths
    |> Enum.map(&rm_if_exists/1)
    |> changed()
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
      File.write!(path, contents)
      :ok
    end
  end

  defp rm_if_exists(path) do
    case File.rm(path) do
      :ok -> :ok
      {:error, :enoent} -> :noop
    end
  end

  defp changed(results) do
    if Enum.any?(results, &(&1 == :ok)), do: :ok, else: :noop
  end

  defp elixir_manifest_path do
    Mix.Tasks.Compile.Elixir.manifests()
    |> List.first()
  end
end
