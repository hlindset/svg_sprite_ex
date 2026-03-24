defmodule SvgSpriteEx.InlineSvgInfo do
  @moduledoc """
  Metadata for one compiled inline SVG.
  """

  @enforce_keys [:name, :source_path]
  defstruct [:name, :source_path]

  @type t :: %__MODULE__{
          name: String.t(),
          source_path: String.t()
        }
end
