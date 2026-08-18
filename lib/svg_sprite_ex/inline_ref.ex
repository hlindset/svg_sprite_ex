defmodule SvgSpriteEx.InlineRef do
  @moduledoc """
  Compile-time inline SVG reference.

  `inline_ref/1` returns this struct for the `<.svg>` component.
  """

  @enforce_keys [:name]
  defstruct [:name]

  @type t :: %__MODULE__{
          name: String.t()
        }
end
