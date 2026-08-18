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
      {:error, reason} -> raise File.Error, reason: reason, action: "remove file", path: path
    end
  end
end
