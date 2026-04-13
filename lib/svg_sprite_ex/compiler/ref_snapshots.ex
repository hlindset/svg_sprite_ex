defmodule SvgSpriteEx.Compiler.RefSnapshots do
  @moduledoc false

  alias SvgSpriteEx.Compiler.FileOps

  @ref_snapshot_vsn 1

  def path(module, compiler_state_path)
      when is_atom(module) and is_binary(compiler_state_path) do
    module_hash =
      module
      |> Atom.to_string()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    Path.join([compiler_state_path, "refs", module_hash <> ".term"])
  end

  def ref_snapshot_vsn, do: @ref_snapshot_vsn

  def build_snapshot(module, sprite_refs, inline_refs) do
    %{
      vsn: @ref_snapshot_vsn,
      module: module,
      sprite_refs: sprite_refs |> Enum.uniq() |> Enum.sort(),
      inline_refs: inline_refs |> Enum.uniq() |> Enum.sort()
    }
  end

  def write(module, compiler_state_path, sprite_refs, inline_refs) do
    snapshot = build_snapshot(module, sprite_refs, inline_refs)
    snapshot_path = path(module, compiler_state_path)

    if snapshot.sprite_refs == [] and snapshot.inline_refs == [] do
      File.rm(snapshot_path)
    else
      File.mkdir_p!(Path.dirname(snapshot_path))
      FileOps.write_atomically!(snapshot_path, :erlang.term_to_binary(snapshot))
    end

    :ok
  end

  def collect_project_refs(compile_path, compiler_state_path, modules) do
    Code.prepend_path(compile_path)

    ref_modules = project_ref_modules(modules)
    active_snapshot_paths = Enum.map(ref_modules, &path(&1, compiler_state_path))

    stale_snapshot_result =
      compiler_state_path
      |> snapshots_path()
      |> FileOps.list_regular_files()
      |> Enum.reject(&(&1 in active_snapshot_paths))
      |> FileOps.cleanup_artifact_paths()

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

  def snapshots_path(compiler_state_path) do
    Path.join(compiler_state_path, "refs")
  end

  defp project_ref_modules(modules) do
    Enum.filter(modules, fn module ->
      Code.ensure_loaded?(module) and function_exported?(module, :__sprite_refs__, 0) and
        function_exported?(module, :__inline_refs__, 0)
    end)
  end
end
