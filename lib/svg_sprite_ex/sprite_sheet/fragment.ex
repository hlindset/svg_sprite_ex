defmodule SvgSpriteEx.SpriteSheet.Fragment do
  @moduledoc false

  @doc false
  @spec decode(String.t()) :: {:ok, String.t()} | :malformed
  def decode(target) when is_binary(target) do
    decode(target, [])
  end

  @doc false
  @spec encode(String.t()) :: String.t()
  def encode(target) when is_binary(target) do
    URI.encode(target, &URI.char_unreserved?/1)
  end

  defp decode("", output) do
    decoded = output |> Enum.reverse() |> IO.iodata_to_binary()

    case String.valid?(decoded) do
      true -> {:ok, decoded}
      false -> :malformed
    end
  end

  defp decode(<<"%", high, low, rest::binary>>, output) do
    with {:ok, high_value} <- hex_value(high),
         {:ok, low_value} <- hex_value(low) do
      decode(rest, [<<high_value * 16 + low_value>> | output])
    else
      :error -> :malformed
    end
  end

  defp decode(<<"%", _rest::binary>>, _output), do: :malformed
  defp decode(<<byte, rest::binary>>, output), do: decode(rest, [<<byte>> | output])

  defp hex_value(byte) when byte in ?0..?9, do: {:ok, byte - ?0}
  defp hex_value(byte) when byte in ?a..?f, do: {:ok, byte - ?a + 10}
  defp hex_value(byte) when byte in ?A..?F, do: {:ok, byte - ?A + 10}
  defp hex_value(_byte), do: :error
end
