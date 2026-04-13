defmodule SvgSpriteEx.Compiler.RefSnapshotsTest do
  use ExUnit.Case

  alias SvgSpriteEx.Compiler.RefSnapshots

  test "write/4 returns the file deletion result when both ref lists are empty" do
    compiler_state_path =
      System.tmp_dir!()
      |> Path.join("svg_sprite_ex_ref_snapshots_#{System.unique_integer([:positive])}")
      |> Path.expand()

    module =
      Module.concat([
        __MODULE__,
        :"delete_result_#{System.unique_integer([:positive])}"
      ])

    snapshot_path = RefSnapshots.path(module, compiler_state_path)

    on_exit(fn -> File.rm_rf(compiler_state_path) end)

    assert {:error, :enoent} = RefSnapshots.write(module, compiler_state_path, [], [])

    File.mkdir_p!(Path.dirname(snapshot_path))
    File.write!(snapshot_path, "stale")

    assert :ok = RefSnapshots.write(module, compiler_state_path, [], [])
    refute File.exists?(snapshot_path)
  end

  test "write/4 returns :ok when it persists a snapshot" do
    compiler_state_path =
      System.tmp_dir!()
      |> Path.join("svg_sprite_ex_ref_snapshots_#{System.unique_integer([:positive])}")
      |> Path.expand()

    module =
      Module.concat([
        __MODULE__,
        :"persist_result_#{System.unique_integer([:positive])}"
      ])

    snapshot_path = RefSnapshots.path(module, compiler_state_path)

    on_exit(fn -> File.rm_rf(compiler_state_path) end)

    assert :ok =
             RefSnapshots.write(module, compiler_state_path, [{"alerts", "regular/xmark"}], [])

    assert File.exists?(snapshot_path)
  end
end
