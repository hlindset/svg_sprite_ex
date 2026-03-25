defmodule SvgSpriteEx.SpriteSheetMeta do
  @moduledoc """
  Metadata for a compiled sprite sheet.
  """

  @enforce_keys [:name, :filename, :build_path, :public_path]
  defstruct [:name, :filename, :build_path, :public_path]

  @type t :: %__MODULE__{
          name: String.t(),
          filename: String.t(),
          build_path: String.t(),
          public_path: String.t()
        }
end
