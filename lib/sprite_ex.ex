defmodule SpriteEx do
  @moduledoc """
  Public entrypoint for SpriteEx in Phoenix component modules.

  `use SpriteEx` imports:

  - the `<.svg>` component from `SpriteEx.Svg`
  - the `sprite_ref/1`, `sprite_ref/2`, and `inline_ref/1` macros from
    `SpriteEx.Ref`
  """

  @doc """
  Imports the SpriteEx component and compile-time ref helpers into the caller.

  ## Examples

      iex> {:module, SpriteExDocTestUsingExample, _, _} =
      ...>   defmodule Elixir.SpriteExDocTestUsingExample do
      ...>   use Phoenix.Component
      ...>   use SpriteEx
      ...>
      ...>   def icon_ref, do: sprite_ref("regular/xmark")
      ...> end
      iex> ref = SpriteExDocTestUsingExample.icon_ref()
      iex> {ref.name, ref.sheet, String.starts_with?(ref.href, "/assets/sprites/sprites.svg#")}
      {"regular/xmark", "sprites", true}
  """
  defmacro __using__(_opts) do
    quote do
      import SpriteEx.Svg
      use SpriteEx.Ref
    end
  end
end
