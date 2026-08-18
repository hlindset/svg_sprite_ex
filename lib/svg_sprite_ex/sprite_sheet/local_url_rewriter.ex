defmodule SvgSpriteEx.SpriteSheet.LocalUrlRewriter do
  @moduledoc false

  alias SvgSpriteEx.SpriteSheet.Fragment

  @css_whitespace [9, 10, 12, 13, 32]

  @doc false
  @spec rewrite!(String.t(), String.t(), %{String.t() => String.t()}, String.t()) :: String.t()
  def rewrite!(content, normalized_name, id_map, source)
      when is_binary(content) and is_binary(normalized_name) and is_map(id_map) and
             is_binary(source) do
    validate_contract!(content, normalized_name, source)

    content
    |> rewrite(normalized_name, id_map, source, [])
    |> Enum.reverse()
    |> IO.iodata_to_binary()
  end

  defp rewrite("", _normalized_name, _id_map, _source, output), do: output

  defp rewrite(<<quote, _rest::binary>> = content, normalized_name, id_map, source, output)
       when quote in [?", ?'] do
    case take_quoted(content, quote) do
      {:ok, quoted, rest} ->
        rewrite(rest, normalized_name, id_map, source, [quoted | output])

      {:error, reason} ->
        unsupported!(normalized_name, source, reason)
    end
  end

  defp rewrite(content, normalized_name, id_map, source, output) do
    {identifier, rest} = take_identifier(content)

    cond do
      identifier != "" and String.downcase(identifier, :ascii) == "url" and
          match?(<<"(", _rest::binary>>, rest) ->
        <<"(", url_content::binary>> = rest
        {body, remaining} = rewrite_url(url_content, normalized_name, id_map, source)
        rewrite(remaining, normalized_name, id_map, source, [[identifier, "(", body] | output])

      identifier != "" ->
        rewrite(rest, normalized_name, id_map, source, [identifier | output])

      true ->
        <<byte, remaining::binary>> = rest
        rewrite(remaining, normalized_name, id_map, source, [<<byte>> | output])
    end
  end

  defp rewrite_url(content, normalized_name, id_map, source) do
    {leading_whitespace, value_and_rest} = take_leading_whitespace(content)

    case value_and_rest do
      <<")", rest::binary>> ->
        {[leading_whitespace, ")"], rest}

      <<quote, _rest::binary>> when quote in [?", ?'] ->
        rewrite_quoted_url(
          leading_whitespace,
          value_and_rest,
          quote,
          normalized_name,
          id_map,
          source
        )

      _other ->
        rewrite_unquoted_url(
          leading_whitespace,
          value_and_rest,
          normalized_name,
          id_map,
          source
        )
    end
  end

  defp rewrite_quoted_url(
         leading_whitespace,
         content,
         quote,
         normalized_name,
         id_map,
         source
       ) do
    case take_quoted_value(content, quote) do
      {:ok, value, after_quote} ->
        {trailing_whitespace, rest} = take_leading_whitespace(after_quote)

        case rest do
          <<")", remaining::binary>> ->
            rewritten = rewrite_value!(value, normalized_name, id_map, source)

            {[leading_whitespace, <<quote>>, rewritten, <<quote>>, trailing_whitespace, ")"],
             remaining}

          _other ->
            unsupported!(normalized_name, source, "malformed url()")
        end

      {:error, reason} ->
        unsupported!(normalized_name, source, reason)
    end
  end

  defp rewrite_unquoted_url(leading_whitespace, content, normalized_name, id_map, source) do
    case :binary.split(content, ")") do
      [inside, rest] ->
        {value, trailing_whitespace} = take_trailing_whitespace(inside)
        validate_unquoted_url_value!(value, normalized_name, source)
        rewritten = rewrite_value!(value, normalized_name, id_map, source)
        {[leading_whitespace, rewritten, trailing_whitespace, ")"], rest}

      [_unclosed] ->
        unsupported!(normalized_name, source, "unclosed url()")
    end
  end

  defp rewrite_value!("#", normalized_name, _id_map, source) do
    unsupported!(normalized_name, source, "ambiguous local fragment")
  end

  defp rewrite_value!(<<"#", target::binary>>, normalized_name, id_map, source)
       when target != "" do
    case Fragment.decode(target) do
      {:ok, decoded_target} ->
        rewrite_decoded_target!(decoded_target, normalized_name, id_map, source)

      :malformed ->
        unsupported!(normalized_name, source, "malformed local fragment")
    end
  end

  defp rewrite_value!(value, _normalized_name, _id_map, _source), do: value

  defp rewrite_decoded_target!(decoded_target, normalized_name, id_map, source) do
    case :binary.match(decoded_target, "#") do
      :nomatch -> fetch_rewritten_target!(decoded_target, normalized_name, id_map, source)
      {_position, _length} -> unsupported!(normalized_name, source, "ambiguous local fragment")
    end
  end

  defp fetch_rewritten_target!(decoded_target, normalized_name, id_map, source) do
    case Map.fetch(id_map, decoded_target) do
      {:ok, rewritten_target} ->
        "#" <> Fragment.encode(rewritten_target)

      :error ->
        raise ArgumentError,
              "svg asset #{inspect(normalized_name)} references unknown local id " <>
                "#{inspect(decoded_target)} from #{source}"
    end
  end

  defp take_identifier(content), do: take_identifier(content, [])

  defp take_identifier(<<byte, rest::binary>>, output)
       when byte in ?a..?z or byte in ?A..?Z or byte in ?0..?9 or byte in [?_, ?-] or byte >= 128 do
    take_identifier(rest, [<<byte>> | output])
  end

  defp take_identifier(rest, output) do
    {output |> Enum.reverse() |> IO.iodata_to_binary(), rest}
  end

  defp take_quoted(content, quote) do
    case take_quoted_value(content, quote) do
      {:ok, value, rest} -> {:ok, [<<quote>>, value, <<quote>>], rest}
      {:error, reason} -> {:error, reason}
    end
  end

  defp take_quoted_value(<<quote, rest::binary>>, quote) do
    take_quoted_value(rest, quote, [])
  end

  defp take_quoted_value("", _quote, _output), do: {:error, "unclosed string"}

  defp take_quoted_value(<<byte, _rest::binary>>, _quote, _output)
       when byte in [?\n, ?\r, ?\f],
       do: {:error, "malformed string"}

  defp take_quoted_value(<<quote, rest::binary>>, quote, output) do
    {:ok, output |> Enum.reverse() |> IO.iodata_to_binary(), rest}
  end

  defp take_quoted_value(<<byte, rest::binary>>, quote, output) do
    take_quoted_value(rest, quote, [<<byte>> | output])
  end

  defp take_leading_whitespace(content), do: take_leading_whitespace(content, [])

  defp take_leading_whitespace(<<byte, rest::binary>>, output) when byte in @css_whitespace do
    take_leading_whitespace(rest, [<<byte>> | output])
  end

  defp take_leading_whitespace(rest, output) do
    {output |> Enum.reverse() |> IO.iodata_to_binary(), rest}
  end

  defp take_trailing_whitespace(content) do
    content
    |> :binary.bin_to_list()
    |> Enum.reverse()
    |> Enum.split_while(&(&1 in @css_whitespace))
    |> then(fn {whitespace, value} ->
      trailing_whitespace = whitespace |> Enum.reverse() |> :binary.list_to_bin()
      {value |> Enum.reverse() |> :binary.list_to_bin(), trailing_whitespace}
    end)
  end

  defp validate_contract!(content, normalized_name, source) do
    cond do
      :binary.match(content, "/*") != :nomatch ->
        unsupported!(normalized_name, source, "CSS comments")

      :binary.match(content, "\\") != :nomatch ->
        unsupported!(normalized_name, source, "backslash escapes")

      true ->
        :ok
    end
  end

  defp validate_unquoted_url_value!(value, normalized_name, source) do
    invalid? =
      value
      |> :binary.bin_to_list()
      |> Enum.any?(&(&1 in @css_whitespace or &1 in [?', ?", ?(]))

    if invalid?, do: unsupported!(normalized_name, source, "malformed url()")
  end

  defp unsupported!(normalized_name, source, reason) do
    raise ArgumentError,
          "svg asset #{inspect(normalized_name)} contains unsupported CSS in #{source}: " <>
            "#{reason}; preprocess the SVG into canonical inline declarations or presentation " <>
            "attributes before compilation (for example with SVGO)"
  end
end
