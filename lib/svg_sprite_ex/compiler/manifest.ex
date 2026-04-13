defmodule SvgSpriteEx.Compiler.Manifest do
  @moduledoc false

  alias SvgSpriteEx.Compiler.FileOps

  @manifest_vsn 3

  def path(compiler_state_path) do
    Path.join(compiler_state_path, "compile.svg_sprite_ex_assets")
  end

  def read(path) do
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

  def write(path, artifact_paths, input_digest) do
    manifest =
      :erlang.term_to_binary(%{
        vsn: @manifest_vsn,
        artifact_paths: artifact_paths,
        input_digest: input_digest
      })

    FileOps.write_if_changed(path, manifest)
  end

  def current?(
        %{artifact_paths: artifact_paths, input_digest: input_digest},
        input_digest
      )
      when is_binary(input_digest) do
    Enum.all?(artifact_paths, &File.exists?/1)
  end

  def current?(_manifest, _input_digest), do: false

  defp empty_manifest do
    %{artifact_paths: [], input_digest: nil}
  end
end
