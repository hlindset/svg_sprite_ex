defmodule SvgSpriteEx.RuntimeData.Validator do
  @moduledoc false

  alias SvgSpriteEx.InlineAsset
  alias SvgSpriteEx.InlineSvgMeta
  alias SvgSpriteEx.SpriteMeta
  alias SvgSpriteEx.SpriteSheetMeta

  @top_level_keys MapSet.new([
                    :vsn,
                    :inline_assets,
                    :inline_svg_map,
                    :sprite_sheet_map,
                    :sprites_in_sheet
                  ])

  @inline_asset_fields MapSet.new([:__struct__, :attributes, :inner_content])
  @inline_svg_meta_fields MapSet.new([:__struct__, :name, :source_path])
  @sprite_sheet_meta_fields MapSet.new([:__struct__, :name, :filename, :build_path, :public_path])

  @sprite_meta_fields MapSet.new([
                        :__struct__,
                        :name,
                        :sheet,
                        :sheet_public_path,
                        :source_path,
                        :sprite_id
                      ])

  @spec validate!(term(), String.t()) :: map()
  def validate!(runtime_data, artifact_path) when is_map(runtime_data) do
    validate_top_level!(runtime_data, artifact_path)

    inline_assets = Map.fetch!(runtime_data, :inline_assets)
    inline_svg_map = Map.fetch!(runtime_data, :inline_svg_map)
    sprite_sheet_map = Map.fetch!(runtime_data, :sprite_sheet_map)
    sprites_in_sheet = Map.fetch!(runtime_data, :sprites_in_sheet)

    validate_inline_assets!(inline_assets, artifact_path)
    validate_inline_svg_map!(inline_svg_map, artifact_path)

    validate_matching_keys!(
      inline_assets,
      inline_svg_map,
      "inline_assets",
      "inline_svg_map",
      artifact_path
    )

    validate_sprite_sheet_map!(sprite_sheet_map, artifact_path)
    validate_sprites_in_sheet_container!(sprites_in_sheet, artifact_path)

    validate_matching_keys!(
      sprite_sheet_map,
      sprites_in_sheet,
      "sprite_sheet_map",
      "sprites_in_sheet",
      artifact_path
    )

    validate_sprites_in_sheet!(sprites_in_sheet, sprite_sheet_map, artifact_path)

    runtime_data
  end

  def validate!(_runtime_data, artifact_path) do
    invalid!(artifact_path, "top-level: expected map")
  end

  defp validate_top_level!(runtime_data, artifact_path) do
    case MapSet.equal?(MapSet.new(Map.keys(runtime_data)), @top_level_keys) do
      true ->
        :ok

      false ->
        invalid!(artifact_path, "top-level: expected exactly the current runtime data schema")
    end
  end

  defp validate_inline_assets!(inline_assets, artifact_path) when is_map(inline_assets) do
    Enum.each(sorted_entries(inline_assets), fn {name, inline_asset} ->
      field_path = field_path("inline_assets", name)
      validate_string_key!(name, "inline_assets", artifact_path)
      validate_inline_asset!(inline_asset, field_path, artifact_path)
    end)
  end

  defp validate_inline_assets!(_inline_assets, artifact_path) do
    invalid!(artifact_path, "inline_assets: expected map")
  end

  defp validate_inline_asset!(%InlineAsset{} = inline_asset, field_path, artifact_path) do
    validate_struct_fields!(
      inline_asset,
      @inline_asset_fields,
      InlineAsset,
      field_path,
      artifact_path
    )

    validate_string_map!(inline_asset.attributes, "#{field_path}.attributes", artifact_path)
    validate_binary!(inline_asset.inner_content, "#{field_path}.inner_content", artifact_path)
  end

  defp validate_inline_asset!(_inline_asset, field_path, artifact_path) do
    invalid!(artifact_path, "#{field_path}: expected #{inspect(InlineAsset)} struct")
  end

  defp validate_inline_svg_map!(inline_svg_map, artifact_path) when is_map(inline_svg_map) do
    Enum.each(sorted_entries(inline_svg_map), fn {name, inline_svg_meta} ->
      field_path = field_path("inline_svg_map", name)
      validate_string_key!(name, "inline_svg_map", artifact_path)
      validate_inline_svg_meta!(inline_svg_meta, field_path, artifact_path)
      validate_matches_key!(inline_svg_meta.name, name, "#{field_path}.name", artifact_path)
    end)
  end

  defp validate_inline_svg_map!(_inline_svg_map, artifact_path) do
    invalid!(artifact_path, "inline_svg_map: expected map")
  end

  defp validate_inline_svg_meta!(%InlineSvgMeta{} = inline_svg_meta, field_path, artifact_path) do
    validate_struct_fields!(
      inline_svg_meta,
      @inline_svg_meta_fields,
      InlineSvgMeta,
      field_path,
      artifact_path
    )

    validate_binary!(inline_svg_meta.name, "#{field_path}.name", artifact_path)
    validate_binary!(inline_svg_meta.source_path, "#{field_path}.source_path", artifact_path)
  end

  defp validate_inline_svg_meta!(_inline_svg_meta, field_path, artifact_path) do
    invalid!(artifact_path, "#{field_path}: expected #{inspect(InlineSvgMeta)} struct")
  end

  defp validate_sprite_sheet_map!(sprite_sheet_map, artifact_path)
       when is_map(sprite_sheet_map) do
    Enum.each(sorted_entries(sprite_sheet_map), fn {name, sprite_sheet_meta} ->
      field_path = field_path("sprite_sheet_map", name)
      validate_string_key!(name, "sprite_sheet_map", artifact_path)
      validate_sprite_sheet_meta!(sprite_sheet_meta, field_path, artifact_path)
      validate_matches_key!(sprite_sheet_meta.name, name, "#{field_path}.name", artifact_path)
    end)
  end

  defp validate_sprite_sheet_map!(_sprite_sheet_map, artifact_path) do
    invalid!(artifact_path, "sprite_sheet_map: expected map")
  end

  defp validate_sprite_sheet_meta!(
         %SpriteSheetMeta{} = sprite_sheet_meta,
         field_path,
         artifact_path
       ) do
    validate_struct_fields!(
      sprite_sheet_meta,
      @sprite_sheet_meta_fields,
      SpriteSheetMeta,
      field_path,
      artifact_path
    )

    validate_binary!(sprite_sheet_meta.name, "#{field_path}.name", artifact_path)
    validate_binary!(sprite_sheet_meta.filename, "#{field_path}.filename", artifact_path)
    validate_binary!(sprite_sheet_meta.build_path, "#{field_path}.build_path", artifact_path)
    validate_binary!(sprite_sheet_meta.public_path, "#{field_path}.public_path", artifact_path)
  end

  defp validate_sprite_sheet_meta!(_sprite_sheet_meta, field_path, artifact_path) do
    invalid!(artifact_path, "#{field_path}: expected #{inspect(SpriteSheetMeta)} struct")
  end

  defp validate_sprites_in_sheet!(sprites_in_sheet, sprite_sheet_map, artifact_path)
       when is_map(sprites_in_sheet) do
    Enum.each(sorted_entries(sprites_in_sheet), fn {sheet_name, sprites} ->
      field_path = field_path("sprites_in_sheet", sheet_name)
      validate_string_key!(sheet_name, "sprites_in_sheet", artifact_path)
      validate_sprite_list!(sprites, sheet_name, field_path, sprite_sheet_map, artifact_path)
    end)
  end

  defp validate_sprites_in_sheet!(_sprites_in_sheet, _sprite_sheet_map, artifact_path) do
    invalid!(artifact_path, "sprites_in_sheet: expected map")
  end

  defp validate_sprites_in_sheet_container!(sprites_in_sheet, _artifact_path)
       when is_map(sprites_in_sheet),
       do: :ok

  defp validate_sprites_in_sheet_container!(_sprites_in_sheet, artifact_path) do
    invalid!(artifact_path, "sprites_in_sheet: expected map")
  end

  defp validate_sprite_list!(sprites, sheet_name, field_path, sprite_sheet_map, artifact_path)
       when is_list(sprites) do
    expected_public_path = expected_public_path(sprite_sheet_map, sheet_name)

    sprites
    |> Enum.with_index()
    |> Enum.reduce(MapSet.new(), fn {sprite_meta, index}, sprite_names ->
      sprite_field_path = "#{field_path}[#{index}]"
      validate_sprite_meta!(sprite_meta, sprite_field_path, artifact_path)

      validate_matches!(
        sprite_meta.sheet,
        sheet_name,
        "#{sprite_field_path}.sheet",
        "must match sheet key",
        artifact_path
      )

      validate_matches!(
        sprite_meta.sheet_public_path,
        expected_public_path,
        "#{sprite_field_path}.sheet_public_path",
        "must match sprite_sheet_map[#{inspect_key(sheet_name)}].public_path",
        artifact_path
      )

      validate_unique_sprite_name!(
        sprite_names,
        sprite_meta.name,
        "#{sprite_field_path}.name",
        artifact_path
      )
    end)
  end

  defp validate_sprite_list!(_sprites, _sheet_name, field_path, _sprite_sheet_map, artifact_path) do
    invalid!(artifact_path, "#{field_path}: expected list")
  end

  defp validate_sprite_meta!(%SpriteMeta{} = sprite_meta, field_path, artifact_path) do
    validate_struct_fields!(
      sprite_meta,
      @sprite_meta_fields,
      SpriteMeta,
      field_path,
      artifact_path
    )

    validate_binary!(sprite_meta.name, "#{field_path}.name", artifact_path)
    validate_binary!(sprite_meta.sheet, "#{field_path}.sheet", artifact_path)

    validate_binary!(
      sprite_meta.sheet_public_path,
      "#{field_path}.sheet_public_path",
      artifact_path
    )

    validate_binary!(sprite_meta.source_path, "#{field_path}.source_path", artifact_path)
    validate_binary!(sprite_meta.sprite_id, "#{field_path}.sprite_id", artifact_path)
  end

  defp validate_sprite_meta!(_sprite_meta, field_path, artifact_path) do
    invalid!(artifact_path, "#{field_path}: expected #{inspect(SpriteMeta)} struct")
  end

  defp validate_struct_fields!(struct, expected_fields, module, field_path, artifact_path) do
    case MapSet.new(Map.keys(struct)) do
      ^expected_fields -> :ok
      _other -> invalid!(artifact_path, "#{field_path}: expected #{inspect(module)} fields")
    end
  end

  defp validate_string_map!(map, field_path, artifact_path) when is_map(map) do
    Enum.each(sorted_entries(map), fn {key, value} ->
      validate_string_key!(key, field_path, artifact_path)
      validate_binary!(value, "#{field_path}[#{inspect_key(key)}]", artifact_path)
    end)
  end

  defp validate_string_map!(_map, field_path, artifact_path) do
    invalid!(artifact_path, "#{field_path}: expected map")
  end

  defp validate_string_key!(key, _field_path, _artifact_path) when is_binary(key), do: :ok

  defp validate_string_key!(_key, field_path, artifact_path) do
    invalid!(artifact_path, "#{field_path}: expected string key")
  end

  defp validate_binary!(value, _field_path, _artifact_path) when is_binary(value), do: :ok

  defp validate_binary!(_value, field_path, artifact_path) do
    invalid!(artifact_path, "#{field_path}: expected binary")
  end

  defp validate_matching_keys!(left, right, left_name, right_name, artifact_path) do
    case MapSet.new(Map.keys(left)) == MapSet.new(Map.keys(right)) do
      true -> :ok
      false -> invalid!(artifact_path, "#{left_name}: keys must match #{right_name}")
    end
  end

  defp expected_public_path(sprite_sheet_map, sheet_name) do
    case Map.fetch(sprite_sheet_map, sheet_name) do
      {:ok, sprite_sheet_meta} -> sprite_sheet_meta.public_path
      :error -> nil
    end
  end

  defp validate_matches_key!(value, key, field_path, artifact_path) do
    validate_matches!(value, key, field_path, "must match key", artifact_path)
  end

  defp validate_matches!(value, expected, _field_path, _detail, _artifact_path)
       when value == expected,
       do: :ok

  defp validate_matches!(_value, _expected, field_path, detail, artifact_path) do
    invalid!(artifact_path, "#{field_path}: #{detail}")
  end

  defp validate_unique_sprite_name!(sprite_names, sprite_name, field_path, artifact_path) do
    case MapSet.member?(sprite_names, sprite_name) do
      true -> invalid!(artifact_path, "#{field_path}: duplicate sprite name")
      false -> MapSet.put(sprite_names, sprite_name)
    end
  end

  defp sorted_entries(map) do
    map
    |> Map.to_list()
    |> Enum.sort_by(fn {key, _value} -> key end)
  end

  defp field_path(collection, key) when is_binary(key), do: "#{collection}[#{inspect_key(key)}]"
  defp field_path(collection, _key), do: collection

  defp inspect_key(key), do: inspect(key, limit: 5, printable_limit: 80)

  defp invalid!(artifact_path, detail) do
    raise ArgumentError, "invalid svg_sprite_ex runtime data at #{artifact_path}, #{detail}"
  end
end
