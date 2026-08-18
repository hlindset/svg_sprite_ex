defmodule SvgSpriteEx.Xmerl do
  @moduledoc false

  @doc false
  @spec characters_to_binary(binary() | list()) :: binary()
  def characters_to_binary(characters) when is_binary(characters), do: characters
  def characters_to_binary(characters) when is_list(characters), do: List.to_string(characters)
end
