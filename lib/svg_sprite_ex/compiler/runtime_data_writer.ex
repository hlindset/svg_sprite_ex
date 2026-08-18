defmodule SvgSpriteEx.Compiler.RuntimeDataWriter do
  @moduledoc false

  alias SvgSpriteEx.Compiler.FileOps
  alias SvgSpriteEx.InlineAsset
  alias SvgSpriteEx.InlineSvgMeta
  alias SvgSpriteEx.RuntimeData
  alias SvgSpriteEx.Source
  alias SvgSpriteEx.SpriteSheetMeta

  def default_path do
    Path.join(Mix.Project.app_path(), "priv/svg_sprite_ex/runtime_data.etf")
  end

  def build_runtime_data(inline_sources, inline_svg_infos, sprite_metadata) do
    inline_assets =
      Map.new(inline_sources, fn %Source{
                                   name: name,
                                   attributes: attributes,
                                   inner_content: inner_content
                                 } ->
        {name, %InlineAsset{attributes: attributes, inner_content: inner_content}}
      end)

    inline_svg_map =
      Map.new(inline_svg_infos, fn %InlineSvgMeta{name: name} = inline_svg_info ->
        {name, inline_svg_info}
      end)

    sprite_sheet_map =
      Map.new(sprite_metadata, fn {%SpriteSheetMeta{name: name} = sheet_info, _sprites} ->
        {name, sheet_info}
      end)

    sprites_in_sheet =
      Map.new(sprite_metadata, fn {%SpriteSheetMeta{name: name}, sprites} ->
        {name, sprites}
      end)

    %{
      vsn: RuntimeData.runtime_data_vsn(),
      inline_assets: inline_assets,
      inline_svg_map: inline_svg_map,
      sprite_sheet_map: sprite_sheet_map,
      sprites_in_sheet: sprites_in_sheet
    }
  end

  def write(path, runtime_data) do
    if runtime_data == empty_runtime_data() do
      FileOps.rm_if_exists(path)
    else
      FileOps.write_if_changed(path, :erlang.term_to_binary(runtime_data))
    end
  end

  def artifact_paths(path, runtime_data) do
    if runtime_data == empty_runtime_data(), do: [], else: [path]
  end

  def invalidate_cache do
    if Code.ensure_loaded?(RuntimeData) and function_exported?(RuntimeData, :delete, 0) do
      RuntimeData.delete()
    else
      :ok
    end
  end

  defp empty_runtime_data do
    %{
      vsn: RuntimeData.runtime_data_vsn(),
      inline_assets: %{},
      inline_svg_map: %{},
      sprite_sheet_map: %{},
      sprites_in_sheet: %{}
    }
  end
end
