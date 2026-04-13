defmodule SvgSpriteEx.SpriteMeta do
  @moduledoc """
  Metadata for one compiled sprite entry within a sprite sheet.

  `sheet_public_path` is the non-digested public sheet path that callers should
  resolve at render time.
  """

  @enforce_keys [:name, :sheet, :sheet_public_path, :source_path, :sprite_id]
  defstruct [:name, :sheet, :sheet_public_path, :source_path, :sprite_id]

  @type t :: %__MODULE__{
          name: String.t(),
          sheet: String.t(),
          sheet_public_path: String.t(),
          source_path: String.t(),
          sprite_id: String.t()
        }
end
