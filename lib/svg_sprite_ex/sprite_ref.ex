defmodule SvgSpriteEx.SpriteRef do
  @moduledoc """
  Compile-time sprite-backed SVG reference.

  `SvgSpriteEx.Ref.sprite_ref/1` and `SvgSpriteEx.Ref.sprite_ref/2` return this
  struct for both `SvgSpriteEx.LiveView.Svg` and `SvgSpriteEx.Hologram.Svg`.

  `sheet_public_path` is the non-digested public sheet path that the renderer
  resolves at runtime.
  """

  @enforce_keys [:name, :sheet, :sheet_public_path, :sprite_id]
  defstruct [:name, :sheet, :sheet_public_path, :sprite_id]

  @type t :: %__MODULE__{
          name: String.t(),
          sheet: String.t(),
          sheet_public_path: String.t(),
          sprite_id: String.t()
        }
end
