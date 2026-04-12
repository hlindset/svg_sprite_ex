defmodule SvgSpriteEx.Generated.RuntimeData do
  @moduledoc false

  @cache_key {__MODULE__, :runtime_data}

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

  defp data do
    fingerprint = runtime_data_fingerprint()

    case :persistent_term.get(@cache_key, :missing) do
      %{fingerprint: ^fingerprint, data: data} ->
        data

      _other ->
        data = load_runtime_data(fingerprint)
        :persistent_term.put(@cache_key, %{fingerprint: fingerprint, data: data})
        data
    end
  end

  defp load_runtime_data(fingerprint) do
    fingerprint
    |> Enum.map(fn {path, _mtime, _size} -> read_runtime_data!(path) end)
    |> Enum.reduce(empty_runtime_data(), &merge_runtime_data/2)
    |> finalize_runtime_data()
  end

  defp merge_runtime_data(file_data, merged_data) do
    %{
      merged_data
      | inline_assets: Map.merge(merged_data.inline_assets, file_data.inline_assets),
        inline_svg_map: Map.merge(merged_data.inline_svg_map, file_data.inline_svg_map),
        sprite_sheet_map: Map.merge(merged_data.sprite_sheet_map, file_data.sprite_sheet_map),
        sprites_in_sheet:
          Map.merge(
            merged_data.sprites_in_sheet,
            file_data.sprites_in_sheet,
            fn _sheet, current_sprites, incoming_sprites ->
              merge_sprites(current_sprites, incoming_sprites)
            end
          )
    }
  end

  defp finalize_runtime_data(merged_data) do
    %{
      merged_data
      | inline_svgs:
          merged_data.inline_svg_map
          |> Map.values()
          |> Enum.sort_by(& &1.name),
        sprite_sheets:
          merged_data.sprite_sheet_map
          |> Map.values()
          |> Enum.sort_by(& &1.name),
        sprites_in_sheet:
          Map.new(merged_data.sprites_in_sheet, fn {sheet, sprites} ->
            {sheet, Enum.sort_by(sprites, & &1.name)}
          end)
    }
  end

  defp merge_sprites(current_sprites, incoming_sprites) do
    (current_sprites ++ incoming_sprites)
    |> Enum.uniq_by(&{&1.sheet, &1.name})
  end

  defp read_runtime_data!(path) do
    path
    |> File.read!()
    |> :erlang.binary_to_term([:safe])
    |> validate_runtime_data!(path)
  end

  defp validate_runtime_data!(
         %{
           vsn: 1,
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

  defp runtime_data_fingerprint do
    runtime_data_paths()
    |> Enum.map(fn path ->
      case File.stat(path, time: :posix) do
        {:ok, %{mtime: mtime, size: size}} -> {path, mtime, size}
        {:error, _reason} -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
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
      sprite_sheets: [],
      sprite_sheet_map: %{},
      sprites_in_sheet: %{}
    }
  end
end
