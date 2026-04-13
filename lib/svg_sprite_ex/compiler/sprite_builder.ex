defmodule SvgSpriteEx.Compiler.SpriteBuilder do
  @moduledoc false

  alias SvgSpriteEx.InlineSvgMeta
  alias SvgSpriteEx.Ref
  alias SvgSpriteEx.Source
  alias SvgSpriteEx.SpriteMeta
  alias SvgSpriteEx.SpriteSheet
  alias SvgSpriteEx.SpriteSheetMeta

  def build_sprite_metadata(sprite_refs, build_path, public_path, source_root) do
    sprite_refs
    |> Enum.group_by(fn {sheet, _name} -> sheet end, fn {_sheet, name} -> name end)
    |> Enum.sort_by(fn {sheet, _names} -> sheet end)
    |> Enum.map(fn {sheet, names} ->
      sheet_build_path = Ref.sheet_build_path(sheet, build_path)
      sheet_public_path = Ref.sheet_public_path(sheet, public_path)

      sheet_info = %SpriteSheetMeta{
        name: sheet,
        filename: Path.basename(sheet_build_path),
        build_path: sheet_build_path,
        public_path: sheet_public_path
      }

      sprites =
        Enum.map(names, fn name ->
          %SpriteMeta{
            name: name,
            sheet: sheet,
            sheet_public_path: sheet_public_path,
            source_path: Source.source_file_path!(name, source_root),
            sprite_id: Source.sprite_id_from_normalized(name)
          }
        end)

      {sheet_info, sprites}
    end)
  end

  def build_sprite_outputs(sprite_metadata, source_root) do
    Enum.into(sprite_metadata, %{}, fn {%SpriteSheetMeta{build_path: build_path}, sprites} ->
      {build_path, SpriteSheet.build(Enum.map(sprites, & &1.name), source_root: source_root)}
    end)
  end

  def load_inline_sources(inline_refs, source_root) do
    Enum.map(inline_refs, &Source.read!(&1, source_root))
  end

  def build_inline_svg_infos(inline_sources) do
    Enum.map(inline_sources, fn %Source{name: name, file_path: file_path} ->
      %InlineSvgMeta{
        name: name,
        source_path: file_path
      }
    end)
  end
end
