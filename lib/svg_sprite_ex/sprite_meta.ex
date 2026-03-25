defmodule SvgSpriteEx.SpriteMeta do
  @moduledoc """
  Metadata for one compiled sprite entry within a sprite sheet.
  """

  @enforce_keys [:name, :sheet, :source_path, :sprite_id, :href]
  defstruct [:name, :sheet, :source_path, :sprite_id, :href]

  @type t :: %__MODULE__{
          name: String.t(),
          sheet: String.t(),
          source_path: String.t(),
          sprite_id: String.t(),
          href: String.t()
        }
end
