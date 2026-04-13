defmodule SvgSpriteEx.Compiler.FileOpsTest do
  use ExUnit.Case

  alias SvgSpriteEx.Compiler.FileOps

  test "list_regular_files/1 returns an empty list for non-directory paths" do
    path =
      System.tmp_dir!()
      |> Path.join("svg_sprite_ex_file_ops_#{System.unique_integer([:positive])}.txt")
      |> Path.expand()

    File.write!(path, "contents")

    on_exit(fn -> File.rm(path) end)

    assert [] = FileOps.list_regular_files(path)
  end
end
