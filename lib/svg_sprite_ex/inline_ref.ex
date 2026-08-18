defmodule SvgSpriteEx.InlineRef do
  @moduledoc """
  Compile-time inline SVG reference.

  `SvgSpriteEx.Ref.inline_ref/1` returns this struct for the
  `SvgSpriteEx.LiveView.Svg` component. The Hologram component does not accept
  inline refs.
  """

  @enforce_keys [:name]
  defstruct [:name]

  @type t :: %__MODULE__{
          name: String.t()
        }
end
