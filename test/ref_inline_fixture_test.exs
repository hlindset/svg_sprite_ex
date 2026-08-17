defmodule SvgSpriteEx.RefInlineFixture do
  use SvgSpriteEx.Ref

  def icon_ref, do: inline_ref("regular/xmark")
  def duplicate_ref, do: inline_ref("regular/xmark")
end
