defmodule SvgSpriteEx.RefSheetedFixture do
  use SvgSpriteEx.Ref

  def ui_ref, do: sprite_ref("regular/xmark", sheet: " UI Actions ")
  def duplicate_ref, do: sprite_ref("regular/xmark", sheet: "ui_actions")
end
