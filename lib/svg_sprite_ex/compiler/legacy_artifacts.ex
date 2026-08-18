defmodule SvgSpriteEx.Compiler.LegacyArtifacts do
  @moduledoc false

  alias SvgSpriteEx.Compiler.FileOps
  alias SvgSpriteEx.Compiler.Manifest

  @legacy_manifest_filename "compile.svg_sprite_ex_assets"
  @generated_source_filenames [
    "svg_sprite_ex_generated_inline_icons.ex",
    "svg_sprite_ex_generated_inline_svgs.ex",
    "svg_sprite_ex_generated_sprite_sheets.ex"
  ]
  @generated_modules [
    SvgSpriteEx.Generated.InlineIcons,
    SvgSpriteEx.Generated.InlineSvgs,
    SvgSpriteEx.Generated.SpriteSheets
  ]

  def cleanup(compiler_state_path, compiler_manifest_path, compile_path, preserved_paths) do
    legacy_manifest_path = manifest_path(compiler_state_path)
    preserved_paths = expanded_paths(preserved_paths)

    cleanup_result =
      legacy_manifest_artifact_paths(legacy_manifest_path, compiler_manifest_path)
      |> Kernel.++(generated_artifact_paths(compiler_state_path, compile_path))
      |> Enum.uniq()
      |> Enum.reject(&(Path.expand(&1) in preserved_paths))
      |> FileOps.cleanup_artifact_paths()

    manifest_result =
      remove_distinct_legacy_manifest(legacy_manifest_path, compiler_manifest_path)

    FileOps.changed([cleanup_result, manifest_result])
  end

  def manifest_path(compiler_state_path) do
    compiler_state_path
    |> Path.dirname()
    |> Path.join(@legacy_manifest_filename)
  end

  defp generated_artifact_paths(compiler_state_path, compile_path) do
    legacy_state_path = Path.dirname(compiler_state_path)

    generated_source_paths =
      Enum.map(@generated_source_filenames, &Path.join(legacy_state_path, &1))

    generated_beam_paths =
      Enum.map(@generated_modules, &Path.join(compile_path, Atom.to_string(&1) <> ".beam"))

    generated_source_paths ++ generated_beam_paths
  end

  defp expanded_paths(paths), do: Enum.map(paths, &Path.expand/1)

  defp legacy_manifest_artifact_paths(legacy_manifest_path, compiler_manifest_path) do
    case same_path?(legacy_manifest_path, compiler_manifest_path) do
      true -> []
      false -> legacy_manifest_path |> Manifest.read() |> Map.fetch!(:artifact_paths)
    end
  end

  defp remove_distinct_legacy_manifest(legacy_manifest_path, compiler_manifest_path) do
    case same_path?(legacy_manifest_path, compiler_manifest_path) do
      true -> :noop
      false -> FileOps.rm_if_exists(legacy_manifest_path)
    end
  end

  defp same_path?(left, right), do: Path.expand(left) == Path.expand(right)
end
