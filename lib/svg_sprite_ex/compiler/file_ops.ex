defmodule SvgSpriteEx.Compiler.FileOps do
  @moduledoc false

  def changed(results) do
    if Enum.any?(results, &(&1 == :ok)), do: :ok, else: :noop
  end

  def cleanup_artifact_paths([]), do: :noop

  def cleanup_artifact_paths(paths) do
    paths
    |> Enum.map(&rm_if_exists/1)
    |> changed()
  end

  def list_regular_files(path) do
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

  def write_if_changed(path, contents) do
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

  def write_atomically!(path, contents) do
    temp_path = "#{path}.tmp-#{System.unique_integer([:positive, :monotonic])}"

    try do
      File.write!(temp_path, contents)
      File.rename!(temp_path, path)
    after
      File.rm(temp_path)
    end
  end

  def rm_if_exists(path) do
    case File.rm(path) do
      :ok -> :ok
      {:error, :enoent} -> :noop
    end
  end
end
