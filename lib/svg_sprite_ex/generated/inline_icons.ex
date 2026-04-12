defmodule SvgSpriteEx.Generated.InlineIcons do
  @moduledoc false

  alias SvgSpriteEx.Generated.RuntimeData

  def fetch(name), do: RuntimeData.fetch_inline_asset(name)
  def names, do: RuntimeData.inline_names()
end
