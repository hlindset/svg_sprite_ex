defmodule SvgSpriteEx.Generated.RuntimeData do
  @moduledoc false

  @cache_key {__MODULE__, :runtime_data}
  @runtime_data_vsn 2

  def runtime_data_vsn, do: @runtime_data_vsn

  def fetch_inline_asset(name) do
    Map.fetch(data().inline_assets, name)
  end

  def inline_names do
    data().inline_assets
    |> Map.keys()
    |> Enum.sort()
  end

  def inline_svgs do
    data().inline_svgs
  end

  def inline_svg(name) do
    Map.get(data().inline_svg_map, name)
  end

  def sprite_sheets do
    data().sprite_sheets
  end

  def sprite_sheet(name) do
    Map.get(data().sprite_sheet_map, name)
  end

  def sprites_in_sheet(name) do
    Map.get(data().sprites_in_sheet, name, [])
  end

  def delete do
    :persistent_term.erase(@cache_key)
    :ok
  end

  defp data do
    case :persistent_term.get(@cache_key, :missing) do
      %{data: data} ->
        data

      :missing ->
        data = load_runtime_data(runtime_data_paths())
        :persistent_term.put(@cache_key, %{data: data})
        data

      _other ->
        delete()
        data()
    end
  end

  defp load_runtime_data(paths) do
    paths
    |> Enum.reduce(empty_runtime_data(), fn path, merged_data ->
      path
      |> read_runtime_data!()
      |> merge_runtime_data(path, merged_data)
    end)
    |> finalize_runtime_data()
  end

  defp merge_runtime_data(file_data, path, merged_data) do
    sheet_sources = register_sheet_sources!(merged_data.sheet_sources, file_data, path)

    %{
      merged_data
      | inline_assets: Map.merge(merged_data.inline_assets, file_data.inline_assets),
        inline_svg_map: Map.merge(merged_data.inline_svg_map, file_data.inline_svg_map),
        sprite_sheet_map: Map.merge(merged_data.sprite_sheet_map, file_data.sprite_sheet_map),
        sprites_in_sheet: Map.merge(merged_data.sprites_in_sheet, file_data.sprites_in_sheet),
        sheet_sources: sheet_sources
    }
  end

  defp finalize_runtime_data(merged_data) do
    runtime_data = Map.drop(merged_data, [:sheet_sources])

    %{
      runtime_data
      | inline_svgs:
          runtime_data.inline_svg_map
          |> Map.values()
          |> Enum.sort_by(& &1.name),
        sprite_sheets:
          runtime_data.sprite_sheet_map
          |> Map.values()
          |> Enum.sort_by(& &1.name),
        sprites_in_sheet:
          Map.new(runtime_data.sprites_in_sheet, fn {sheet, sprites} ->
            {sheet, Enum.sort_by(sprites, & &1.name)}
          end)
    }
  end

  defp register_sheet_sources!(sheet_sources, file_data, path) do
    file_data
    |> sheet_names()
    |> Enum.reduce(sheet_sources, fn sheet, acc ->
      case acc do
        %{^sheet => existing_path} ->
          raise_duplicate_sheet_error!(sheet, existing_path, path)

        %{} ->
          Map.put(acc, sheet, path)
      end
    end)
  end

  defp sheet_names(file_data) do
    (Map.keys(file_data.sprite_sheet_map) ++ Map.keys(file_data.sprites_in_sheet))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp raise_duplicate_sheet_error!(sheet, existing_path, path) do
    raise ArgumentError,
          "duplicate svg_sprite_ex sheet #{inspect(sheet)} in runtime data files " <>
            "#{inspect(existing_path)} and #{inspect(path)}; sheet names must be unique across apps on the code path"
  end

  defp read_runtime_data!(path) do
    path
    |> File.read!()
    |> :erlang.binary_to_term([:safe])
    |> validate_runtime_data!(path)
  end

  defp validate_runtime_data!(
         %{
           vsn: @runtime_data_vsn,
           inline_assets: inline_assets,
           inline_svg_map: inline_svg_map,
           sprite_sheet_map: sprite_sheet_map,
           sprites_in_sheet: sprites_in_sheet
         } = runtime_data,
         _path
       )
       when is_map(inline_assets) and is_map(inline_svg_map) and is_map(sprite_sheet_map) and
              is_map(sprites_in_sheet) do
    runtime_data
  end

  defp validate_runtime_data!(runtime_data, path) do
    raise ArgumentError,
          "invalid svg_sprite_ex runtime data at #{path}: #{inspect(runtime_data)}"
  end

  defp runtime_data_paths do
    :code.get_path()
    |> Enum.map(&to_string/1)
    |> Enum.map(fn ebin_path ->
      ebin_path
      |> Path.dirname()
      |> Path.join("priv/svg_sprite_ex/runtime_data.etf")
    end)
    |> Enum.filter(&File.regular?/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp empty_runtime_data do
    %{
      inline_assets: %{},
      inline_svgs: [],
      inline_svg_map: %{},
      sheet_sources: %{},
      sprite_sheets: [],
      sprite_sheet_map: %{},
      sprites_in_sheet: %{}
    }
  end
end
