defmodule SvgSpriteEx.SpriteSheet.CSSRewriter do
  @moduledoc false

  @declaration_at_rules ~w(counter-style font-face page property)
  @css_whitespace [9, 10, 12, 13, 32]
  @newline [10, 12, 13]

  @type context :: :declarations | :keyframes | :rules

  @doc false
  @spec rewrite_stylesheet!(String.t(), String.t(), map()) :: String.t()
  def rewrite_stylesheet!(content, normalized_name, id_map) do
    content
    |> tokenize()
    |> rewrite_url_tokens!(normalized_name, id_map, "style")
    |> structural_tokens()
    |> rewrite_blocks([:rules], [], [], id_map)
    |> IO.iodata_to_binary()
  end

  @doc false
  @spec rewrite_urls!(String.t(), String.t(), map(), String.t()) :: String.t()
  def rewrite_urls!(content, normalized_name, id_map, source) do
    content
    |> tokenize()
    |> rewrite_url_tokens!(normalized_name, id_map, source)
    |> render_tokens()
  end

  defp tokenize(content), do: content |> do_tokenize([]) |> Enum.reverse()

  defp do_tokenize("", tokens), do: tokens

  defp do_tokenize(<<"/*", _rest::binary>> = content, tokens) do
    {comment, rest} = take_comment(content)
    do_tokenize(rest, [{:comment, comment} | tokens])
  end

  defp do_tokenize(<<byte, _rest::binary>> = content, tokens) when byte in @css_whitespace do
    {whitespace, rest} = take_css_whitespace(content)
    do_tokenize(rest, [{:whitespace, whitespace} | tokens])
  end

  defp do_tokenize(<<quote, _rest::binary>> = content, tokens) when quote in [?', ?"] do
    {token, rest} = take_string_token(content, quote)
    do_tokenize(rest, [token | tokens])
  end

  defp do_tokenize(<<"@", rest::binary>>, tokens), do: tokenize_at_keyword(rest, tokens)
  defp do_tokenize(<<"#", rest::binary>>, tokens), do: tokenize_hash(rest, tokens)

  defp do_tokenize(content, tokens) do
    case name_start?(content) do
      true -> tokenize_identifier(content, tokens)
      false -> tokenize_delimiter(content, tokens)
    end
  end

  defp tokenize_at_keyword(rest, tokens) do
    case name_start?(rest) do
      true ->
        {raw, decoded, tail} = take_name(rest)
        do_tokenize(tail, [{:at_keyword, "@" <> raw, decoded} | tokens])

      false ->
        do_tokenize(rest, [{:delim, "@"} | tokens])
    end
  end

  defp tokenize_hash(rest, tokens) do
    case name_codepoint_start?(rest) do
      true ->
        flag = hash_flag(rest)
        {raw, decoded, tail} = take_name(rest)
        do_tokenize(tail, [{:hash, "#" <> raw, decoded, flag} | tokens])

      false ->
        do_tokenize(rest, [{:delim, "#"} | tokens])
    end
  end

  defp tokenize_identifier(content, tokens) do
    {raw, decoded, rest} = take_name(content)

    case rest do
      <<"(", tail::binary>> ->
        tokenize_function(raw, decoded, tail, tokens)

      _other ->
        do_tokenize(rest, [{:ident, raw, decoded} | tokens])
    end
  end

  defp tokenize_function(raw, decoded, tail, tokens) do
    case String.downcase(decoded) == "url" and not quoted_url_function?(tail) do
      true ->
        {token, rest} = take_unquoted_url_token(raw, tail)
        do_tokenize(rest, [token | tokens])

      false ->
        do_tokenize(tail, [{:function, raw, decoded} | tokens])
    end
  end

  defp quoted_url_function?(content) do
    {_whitespace, rest} = take_css_whitespace(content)

    case rest do
      <<quote, _rest::binary>> when quote in [?', ?"] -> true
      _other -> false
    end
  end

  defp take_unquoted_url_token(raw_name, content) do
    {whitespace, rest} = take_css_whitespace(content)
    do_take_unquoted_url_token(rest, raw_name, [whitespace], [])
  end

  defp do_take_unquoted_url_token("", raw_name, raw, decoded) do
    {url_token(raw_name, raw, decoded, false), ""}
  end

  defp do_take_unquoted_url_token(<<")", rest::binary>>, raw_name, raw, decoded) do
    {url_token(raw_name, [")" | raw], decoded, true), rest}
  end

  defp do_take_unquoted_url_token(<<byte, _rest::binary>> = content, raw_name, raw, decoded)
       when byte in @css_whitespace do
    {whitespace, rest} = take_css_whitespace(content)
    raw = [whitespace | raw]

    case rest do
      "" -> {url_token(raw_name, raw, decoded, false), ""}
      <<")", tail::binary>> -> {url_token(raw_name, [")" | raw], decoded, true), tail}
      _other -> consume_bad_url(rest, raw_name, raw)
    end
  end

  defp do_take_unquoted_url_token(<<byte, _rest::binary>> = content, raw_name, raw, _decoded)
       when byte in [?', ?", ?(]
       when byte in 0..8
       when byte == 11
       when byte in 14..31
       when byte == 127 do
    consume_bad_url(content, raw_name, raw)
  end

  defp do_take_unquoted_url_token(<<"\\", _rest::binary>> = content, raw_name, raw, decoded) do
    case take_escape(content) do
      {true, escape, value, rest} ->
        do_take_unquoted_url_token(rest, raw_name, [escape | raw], [value | decoded])

      {false, _escape, _value, _rest} ->
        consume_bad_url(content, raw_name, raw)
    end
  end

  defp do_take_unquoted_url_token(content, raw_name, raw, decoded) do
    {codepoint, rest} = take_codepoint(content)
    do_take_unquoted_url_token(rest, raw_name, [codepoint | raw], [codepoint | decoded])
  end

  defp consume_bad_url("", raw_name, raw) do
    {{:bad_url, url_raw(raw_name, raw)}, ""}
  end

  defp consume_bad_url(<<")", rest::binary>>, raw_name, raw) do
    {{:bad_url, url_raw(raw_name, [")" | raw])}, rest}
  end

  defp consume_bad_url(<<"\\", _rest::binary>> = content, raw_name, raw) do
    {_valid?, escape, _value, rest} = take_escape(content)
    consume_bad_url(rest, raw_name, [escape | raw])
  end

  defp consume_bad_url(content, raw_name, raw) do
    {codepoint, rest} = take_codepoint(content)
    consume_bad_url(rest, raw_name, [codepoint | raw])
  end

  defp url_token(raw_name, raw, decoded, closed?) do
    {
      :url,
      url_raw(raw_name, raw),
      raw_name,
      decoded |> Enum.reverse() |> IO.iodata_to_binary(),
      closed?
    }
  end

  defp url_raw(raw_name, raw) do
    IO.iodata_to_binary([raw_name, "(", Enum.reverse(raw)])
  end

  defp tokenize_delimiter(<<"\\", _rest::binary>> = content, tokens) do
    {valid?, raw, _decoded, rest} = take_escape(content)
    token = bad_escape_token(valid?, raw)
    do_tokenize(rest, [token | tokens])
  end

  defp tokenize_delimiter(content, tokens) do
    {codepoint, rest} = take_codepoint(content)
    do_tokenize(rest, [{:delim, codepoint} | tokens])
  end

  defp bad_escape_token(true, raw), do: {:ident, raw, decode_valid_escape(raw)}
  defp bad_escape_token(false, raw), do: {:bad_escape, raw}

  defp name_start?(<<byte, _rest::binary>>)
       when byte in ?a..?z
       when byte in ?A..?Z
       when byte in [?_, ?-],
       do: true

  defp name_start?(<<codepoint::utf8, _rest::binary>>) when codepoint >= 0x80, do: true
  defp name_start?(<<"\\", rest::binary>>), do: valid_escape_tail?(rest)
  defp name_start?(_content), do: false

  defp name_codepoint_start?(<<byte, _rest::binary>>)
       when byte in ?a..?z
       when byte in ?A..?Z
       when byte in ?0..?9
       when byte in [?_, ?-],
       do: true

  defp name_codepoint_start?(<<codepoint::utf8, _rest::binary>>) when codepoint >= 0x80,
    do: true

  defp name_codepoint_start?(<<"\\", rest::binary>>), do: valid_escape_tail?(rest)
  defp name_codepoint_start?(_content), do: false

  defp hash_flag(content) do
    case identifier_start?(content) do
      true -> :id
      false -> :unrestricted
    end
  end

  defp identifier_start?(<<"--", _rest::binary>>), do: true

  defp identifier_start?(<<"-\\", rest::binary>>),
    do: valid_escape_tail?(rest)

  defp identifier_start?(<<"-", byte, _rest::binary>>)
       when byte in ?a..?z
       when byte in ?A..?Z
       when byte == ?_,
       do: true

  defp identifier_start?(<<"-", codepoint::utf8, _rest::binary>>) when codepoint >= 0x80,
    do: true

  defp identifier_start?(<<byte, _rest::binary>>)
       when byte in ?a..?z
       when byte in ?A..?Z
       when byte == ?_,
       do: true

  defp identifier_start?(<<codepoint::utf8, _rest::binary>>) when codepoint >= 0x80,
    do: true

  defp identifier_start?(<<"\\", rest::binary>>), do: valid_escape_tail?(rest)
  defp identifier_start?(_content), do: false

  defp valid_escape_tail?(""), do: false
  defp valid_escape_tail?(<<"\r\n", _rest::binary>>), do: false

  defp valid_escape_tail?(<<codepoint::utf8, _rest::binary>>) when codepoint in @newline,
    do: false

  defp valid_escape_tail?(_rest), do: true

  defp take_name(content), do: do_take_name(content, [], [])

  defp do_take_name(<<"\\", _rest::binary>> = content, raw, decoded) do
    case take_escape(content) do
      {true, escape, value, rest} ->
        do_take_name(rest, [escape | raw], [value | decoded])

      {false, _escape, _value, _rest} ->
        finish_name(content, raw, decoded)
    end
  end

  defp do_take_name(<<byte, rest::binary>>, raw, decoded)
       when byte in ?a..?z
       when byte in ?A..?Z
       when byte in ?0..?9
       when byte in [?_, ?-] do
    value = <<byte>>
    do_take_name(rest, [value | raw], [value | decoded])
  end

  defp do_take_name(<<codepoint::utf8, rest::binary>>, raw, decoded) when codepoint >= 0x80 do
    value = <<codepoint::utf8>>
    do_take_name(rest, [value | raw], [value | decoded])
  end

  defp do_take_name(rest, raw, decoded), do: finish_name(rest, raw, decoded)

  defp finish_name(rest, raw, decoded) do
    {
      raw |> Enum.reverse() |> IO.iodata_to_binary(),
      decoded |> Enum.reverse() |> IO.iodata_to_binary(),
      rest
    }
  end

  defp take_escape("\\"), do: {false, "\\", "", ""}

  defp take_escape(<<"\\\r\n", rest::binary>>),
    do: {false, "\\\r\n", "", rest}

  defp take_escape(<<"\\", codepoint::utf8, rest::binary>>) when codepoint in @newline,
    do: {false, <<?\\, codepoint::utf8>>, "", rest}

  defp take_escape(<<"\\", rest::binary>>) do
    {digits, after_digits} = take_hex_digits(rest, 6, [])

    case digits do
      "" ->
        {codepoint, tail} = take_codepoint(rest)
        {true, "\\" <> codepoint, codepoint, tail}

      hex ->
        {terminator, tail} = take_hex_terminator(after_digits)
        {true, IO.iodata_to_binary(["\\", hex, terminator]), css_codepoint(hex), tail}
    end
  end

  defp decode_valid_escape(raw) do
    {true, ^raw, decoded, ""} = take_escape(raw)
    decoded
  end

  defp take_hex_digits(rest, 0, acc) do
    {acc |> Enum.reverse() |> IO.iodata_to_binary(), rest}
  end

  defp take_hex_digits(<<byte, rest::binary>>, remaining, acc)
       when byte in ?0..?9
       when byte in ?a..?f
       when byte in ?A..?F do
    take_hex_digits(rest, remaining - 1, [<<byte>> | acc])
  end

  defp take_hex_digits(rest, _remaining, acc) do
    {acc |> Enum.reverse() |> IO.iodata_to_binary(), rest}
  end

  defp take_hex_terminator(<<"\r\n", rest::binary>>), do: {"\r\n", rest}

  defp take_hex_terminator(<<byte, rest::binary>>) when byte in @css_whitespace,
    do: {<<byte>>, rest}

  defp take_hex_terminator(rest), do: {"", rest}

  defp css_codepoint(hex) do
    {codepoint, ""} = Integer.parse(hex, 16)

    cond do
      codepoint == 0 -> <<0xFFFD::utf8>>
      codepoint in 0xD800..0xDFFF -> <<0xFFFD::utf8>>
      codepoint > 0x10FFFF -> <<0xFFFD::utf8>>
      true -> <<codepoint::utf8>>
    end
  end

  defp take_string_token(<<quote, rest::binary>>, quote) do
    do_take_string_token(rest, quote, [<<quote>>], [], true)
  end

  defp do_take_string_token("", quote, raw, decoded, _valid?) do
    {string_token(raw, decoded, quote, false), ""}
  end

  defp do_take_string_token(<<quote, rest::binary>>, quote, raw, decoded, valid?) do
    token = string_token([<<quote>> | raw], decoded, quote, valid?)
    {token, rest}
  end

  defp do_take_string_token(
         <<codepoint::utf8, _rest::binary>> = content,
         quote,
         raw,
         decoded,
         _valid?
       )
       when codepoint in @newline do
    {string_token(raw, decoded, quote, false), content}
  end

  defp do_take_string_token(<<"\\", _rest::binary>> = content, quote, raw, decoded, valid?) do
    {escape_valid?, escape, value, rest} = take_string_escape(content)

    do_take_string_token(
      rest,
      quote,
      [escape | raw],
      [value | decoded],
      valid? and escape_valid?
    )
  end

  defp do_take_string_token(content, quote, raw, decoded, valid?) do
    {codepoint, rest} = take_codepoint(content)
    still_valid? = valid? and not newline_codepoint?(codepoint)
    do_take_string_token(rest, quote, [codepoint | raw], [codepoint | decoded], still_valid?)
  end

  defp string_token(raw, decoded, quote, valid?) do
    {
      :string,
      raw |> Enum.reverse() |> IO.iodata_to_binary(),
      decoded |> Enum.reverse() |> IO.iodata_to_binary(),
      quote,
      valid?
    }
  end

  defp newline_codepoint?(<<codepoint::utf8>>), do: codepoint in @newline

  defp take_string_escape(content) do
    case take_escape(content) do
      {false, escape, "", rest} = result -> normalize_string_newline_escape(escape, rest, result)
      result -> result
    end
  end

  defp normalize_string_newline_escape(<<"\\\r\n">> = escape, rest, _result),
    do: {true, escape, "", rest}

  defp normalize_string_newline_escape(<<"\\", codepoint::utf8>> = escape, rest, _result)
       when codepoint in @newline,
       do: {true, escape, "", rest}

  defp normalize_string_newline_escape(_escape, _rest, result), do: result

  defp rewrite_url_tokens!(tokens, normalized_name, id_map, source) do
    do_rewrite_url_tokens(tokens, [], normalized_name, id_map, source)
  end

  defp do_rewrite_url_tokens([], output, _normalized_name, _id_map, _source) do
    Enum.reverse(output)
  end

  defp do_rewrite_url_tokens(
         [{:url, _raw, raw_name, decoded, true} = token | tokens],
         output,
         normalized_name,
         id_map,
         source
       ) do
    rewritten = rewrite_url_token!(token, raw_name, decoded, normalized_name, id_map, source)
    do_rewrite_url_tokens(tokens, [rewritten | output], normalized_name, id_map, source)
  end

  defp do_rewrite_url_tokens(
         [{:function, _raw, decoded} = function | tokens],
         output,
         normalized_name,
         id_map,
         source
       ) do
    case String.downcase(decoded) do
      "url" ->
        rewrite_url_function(function, tokens, output, normalized_name, id_map, source)

      _other ->
        do_rewrite_url_tokens(tokens, [function | output], normalized_name, id_map, source)
    end
  end

  defp do_rewrite_url_tokens(
         [token | tokens],
         output,
         normalized_name,
         id_map,
         source
       ) do
    do_rewrite_url_tokens(tokens, [token | output], normalized_name, id_map, source)
  end

  defp rewrite_url_function(function, tokens, output, normalized_name, id_map, source) do
    case take_parenthesized_tokens(tokens, 1, []) do
      {:ok, inner, closing, rest} ->
        rewritten = [
          function,
          rewrite_url_inner!(inner, normalized_name, id_map, source),
          closing
        ]

        do_rewrite_url_tokens(
          rest,
          prepend_tokens(rewritten, output),
          normalized_name,
          id_map,
          source
        )

      :error ->
        do_rewrite_url_tokens(tokens, [function | output], normalized_name, id_map, source)
    end
  end

  defp rewrite_url_token!(token, raw_name, decoded, normalized_name, id_map, source) do
    case local_url_fragment_target(decoded) do
      {:ok, target} ->
        rewritten = rewrite_reference_target!(target, source, normalized_name, id_map)
        {:raw, IO.iodata_to_binary([raw_name, "(#", escape_css_identifier(rewritten), ")"])}

      :not_local ->
        token
    end
  end

  defp rewrite_url_inner!(tokens, normalized_name, id_map, source) do
    {leading, value, trailing} = split_url_trivia(tokens)
    rewritten_value = rewrite_url_value!(value, normalized_name, id_map, source)

    case render_tokens(rewritten_value) == render_tokens(value) do
      true -> leading ++ value ++ trailing
      false -> preserve_url_comment_trivia(leading, rewritten_value, trailing)
    end
  end

  defp preserve_url_comment_trivia(leading, rewritten_value, trailing) do
    case Enum.any?(leading ++ trailing, &comment_token?/1) do
      true -> leading ++ rewritten_value ++ trailing
      false -> rewritten_value
    end
  end

  defp comment_token?({:comment, _raw}), do: true
  defp comment_token?(_token), do: false

  defp rewrite_url_value!(
         [{:string, _raw, decoded, quote, true} = string],
         normalized_name,
         id_map,
         source
       ) do
    case local_fragment_target(decoded) do
      {:ok, target} ->
        rewritten = rewrite_reference_target!(target, source, normalized_name, id_map)

        raw =
          IO.iodata_to_binary([<<quote>>, "#", escape_css_string(rewritten, quote), <<quote>>])

        [{:string, raw, "#" <> rewritten, quote, true}]

      :not_local ->
        [string]
    end
  end

  defp rewrite_url_value!(tokens, _normalized_name, _id_map, _source), do: tokens

  defp local_url_fragment_target(value) do
    case String.contains?(value, ["/*", "*/"]) do
      true -> :not_local
      false -> local_fragment_target(value)
    end
  end

  defp local_fragment_target(<<"##", _rest::binary>>), do: :not_local

  defp local_fragment_target(<<"#", target::binary>>) when target != "" do
    case contains_unicode_whitespace?(target) do
      true -> :not_local
      false -> {:ok, target}
    end
  end

  defp local_fragment_target(_value), do: :not_local

  defp contains_unicode_whitespace?(content) do
    content
    |> String.to_charlist()
    |> Enum.any?(&unicode_whitespace?/1)
  end

  defp unicode_whitespace?(codepoint)
       when codepoint in @css_whitespace
       when codepoint in [0x85, 0xA0, 0x1680, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000]
       when codepoint in 0x2000..0x200A,
       do: true

  defp unicode_whitespace?(_codepoint), do: false

  defp split_url_trivia(tokens) do
    {leading, rest} = Enum.split_while(tokens, &url_trivia?/1)

    {trailing_reversed, value_reversed} =
      rest |> Enum.reverse() |> Enum.split_while(&url_trivia?/1)

    {leading, Enum.reverse(value_reversed), Enum.reverse(trailing_reversed)}
  end

  defp url_trivia?({:comment, _raw}), do: true
  defp url_trivia?({:whitespace, _raw}), do: true
  defp url_trivia?(_token), do: false

  defp take_parenthesized_tokens([], _depth, _output), do: :error

  defp take_parenthesized_tokens([{:function, _raw, _decoded} = token | tokens], depth, output) do
    take_parenthesized_tokens(tokens, depth + 1, [token | output])
  end

  defp take_parenthesized_tokens([{:delim, "("} = token | tokens], depth, output) do
    take_parenthesized_tokens(tokens, depth + 1, [token | output])
  end

  defp take_parenthesized_tokens([{:delim, ")"} = closing | tokens], 1, output) do
    {:ok, Enum.reverse(output), closing, tokens}
  end

  defp take_parenthesized_tokens([{:delim, ")"} = token | tokens], depth, output) do
    take_parenthesized_tokens(tokens, depth - 1, [token | output])
  end

  defp take_parenthesized_tokens([token | tokens], depth, output) do
    take_parenthesized_tokens(tokens, depth, [token | output])
  end

  defp structural_tokens(tokens) do
    tokens
    |> do_structural_tokens(0, 0, [], [])
    |> Enum.reverse()
  end

  defp do_structural_tokens([], _parentheses, _brackets, buffer, tokens) do
    flush_structural_buffer(buffer, tokens)
  end

  defp do_structural_tokens([{:delim, "{"} | rest], 0, 0, buffer, tokens) do
    {tokens, buffer} = emit_structural_token(:open, buffer, tokens)
    do_structural_tokens(rest, 0, 0, buffer, tokens)
  end

  defp do_structural_tokens([{:delim, "}"} | rest], 0, 0, buffer, tokens) do
    {tokens, buffer} = emit_structural_token(:close, buffer, tokens)
    do_structural_tokens(rest, 0, 0, buffer, tokens)
  end

  defp do_structural_tokens([{:delim, ";"} | rest], 0, 0, buffer, tokens) do
    {tokens, buffer} = emit_structural_token(:semicolon, buffer, tokens)
    do_structural_tokens(rest, 0, 0, buffer, tokens)
  end

  defp do_structural_tokens(
         [{:function, _raw, _decoded} = token | rest],
         parentheses,
         brackets,
         buffer,
         tokens
       ) do
    do_structural_tokens(rest, parentheses + 1, brackets, [token | buffer], tokens)
  end

  defp do_structural_tokens(
         [{:delim, "("} = token | rest],
         parentheses,
         brackets,
         buffer,
         tokens
       ) do
    do_structural_tokens(rest, parentheses + 1, brackets, [token | buffer], tokens)
  end

  defp do_structural_tokens(
         [{:delim, ")"} = token | rest],
         parentheses,
         brackets,
         buffer,
         tokens
       ) do
    do_structural_tokens(rest, max(parentheses - 1, 0), brackets, [token | buffer], tokens)
  end

  defp do_structural_tokens(
         [{:delim, "["} = token | rest],
         parentheses,
         brackets,
         buffer,
         tokens
       ) do
    do_structural_tokens(rest, parentheses, brackets + 1, [token | buffer], tokens)
  end

  defp do_structural_tokens(
         [{:delim, "]"} = token | rest],
         parentheses,
         brackets,
         buffer,
         tokens
       ) do
    do_structural_tokens(rest, parentheses, max(brackets - 1, 0), [token | buffer], tokens)
  end

  defp do_structural_tokens([token | rest], parentheses, brackets, buffer, tokens) do
    do_structural_tokens(rest, parentheses, brackets, [token | buffer], tokens)
  end

  defp emit_structural_token(token, buffer, tokens) do
    {[token | flush_structural_buffer(buffer, tokens)], []}
  end

  defp flush_structural_buffer([], tokens), do: tokens
  defp flush_structural_buffer(buffer, tokens), do: [{:text, Enum.reverse(buffer)} | tokens]

  defp rewrite_blocks([], _contexts, buffer, output, _id_map) do
    Enum.reverse([render_block_buffer(buffer) | output])
  end

  defp rewrite_blocks([:open | tokens], [parent | _] = contexts, buffer, output, id_map) do
    prelude = block_buffer_tokens(buffer)
    {rewritten_prelude, child_context} = rewrite_prelude(prelude, parent, id_map)

    rewrite_blocks(
      tokens,
      [child_context | contexts],
      [],
      ["{", render_tokens(rewritten_prelude) | output],
      id_map
    )
  end

  defp rewrite_blocks([:close | tokens], [_context | parents], buffer, output, id_map) do
    rewrite_blocks(
      tokens,
      non_empty_contexts(parents),
      [],
      ["}", render_block_buffer(buffer) | output],
      id_map
    )
  end

  defp rewrite_blocks([:semicolon | tokens], contexts, buffer, output, id_map) do
    rewrite_blocks(
      tokens,
      contexts,
      [],
      [";", render_block_buffer(buffer) | output],
      id_map
    )
  end

  defp rewrite_blocks([{:text, text} | tokens], contexts, buffer, output, id_map) do
    rewrite_blocks(tokens, contexts, [text | buffer], output, id_map)
  end

  defp block_buffer_tokens(buffer), do: buffer |> Enum.reverse() |> Enum.concat()
  defp render_block_buffer(buffer), do: buffer |> block_buffer_tokens() |> render_tokens()

  defp rewrite_prelude(prelude, parent_context, id_map) do
    case at_rule_name(prelude) do
      nil ->
        rewrite_qualified_prelude(prelude, parent_context, id_map)

      "scope" ->
        {rewrite_selector_tokens(prelude, id_map), :rules}

      "supports" ->
        {rewrite_supports_selector_functions(prelude, id_map), :rules}

      name when name in @declaration_at_rules ->
        {prelude, :declarations}

      name ->
        {prelude, at_rule_child_context(name)}
    end
  end

  defp rewrite_qualified_prelude(prelude, :keyframes, _id_map),
    do: {prelude, :declarations}

  defp rewrite_qualified_prelude(prelude, _parent_context, id_map),
    do: {rewrite_selector_tokens(prelude, id_map), :declarations}

  defp at_rule_child_context(name) do
    case String.ends_with?(name, "keyframes") do
      true -> :keyframes
      false -> :rules
    end
  end

  defp at_rule_name(tokens) do
    case Enum.drop_while(tokens, &css_trivia?/1) do
      [{:at_keyword, _raw, decoded} | _rest] -> String.downcase(decoded)
      _other -> nil
    end
  end

  defp rewrite_supports_selector_functions(tokens, id_map) do
    do_rewrite_supports_selector_functions(tokens, [], id_map)
  end

  defp do_rewrite_supports_selector_functions([], output, _id_map), do: Enum.reverse(output)

  defp do_rewrite_supports_selector_functions(
         [{:function, _raw, decoded} = function | tokens],
         output,
         id_map
       ) do
    case String.downcase(decoded) do
      "selector" ->
        rewrite_selector_function(function, tokens, output, id_map)

      _other ->
        do_rewrite_supports_selector_functions(tokens, [function | output], id_map)
    end
  end

  defp do_rewrite_supports_selector_functions([token | tokens], output, id_map) do
    do_rewrite_supports_selector_functions(tokens, [token | output], id_map)
  end

  defp rewrite_selector_function(function, tokens, output, id_map) do
    case take_parenthesized_tokens(tokens, 1, []) do
      {:ok, inner, closing, rest} ->
        rewritten = [function, rewrite_selector_tokens(inner, id_map), closing]

        do_rewrite_supports_selector_functions(
          rest,
          prepend_tokens(rewritten, output),
          id_map
        )

      :error ->
        do_rewrite_supports_selector_functions(tokens, [function | output], id_map)
    end
  end

  defp rewrite_selector_tokens(tokens, id_map) do
    case malformed_selector_tokens?(tokens) do
      true -> tokens
      false -> do_rewrite_selector_tokens(tokens, [], id_map)
    end
  end

  defp malformed_selector_tokens?([{:delim, "#"} | tokens]) do
    case Enum.drop_while(tokens, &comment_token?/1) do
      [{:hash, _raw, _decoded, _flag} | _tokens] -> true
      _other -> malformed_selector_tokens?(tokens)
    end
  end

  defp malformed_selector_tokens?([{:bad_escape, _raw} | _tokens]), do: true

  defp malformed_selector_tokens?([{:string, _raw, _decoded, _quote, false} | _tokens]),
    do: true

  defp malformed_selector_tokens?([_token | tokens]), do: malformed_selector_tokens?(tokens)
  defp malformed_selector_tokens?([]), do: false

  defp do_rewrite_selector_tokens([], output, _id_map), do: Enum.reverse(output)

  defp do_rewrite_selector_tokens([{:delim, "["} = opening | tokens], output, id_map) do
    case take_bracketed_tokens(tokens, 1, []) do
      {:ok, inner, closing, rest} ->
        rewritten = [opening, rewrite_attribute_selector(inner, id_map), closing]
        do_rewrite_selector_tokens(rest, prepend_tokens(rewritten, output), id_map)

      :error ->
        do_rewrite_selector_tokens(tokens, [opening | output], id_map)
    end
  end

  defp do_rewrite_selector_tokens(
         [{:hash, _raw, decoded, :id} = token | tokens],
         output,
         id_map
       ) do
    rewritten = rewrite_known_selector_id(token, decoded, id_map)
    do_rewrite_selector_tokens(tokens, [rewritten | output], id_map)
  end

  defp do_rewrite_selector_tokens([token | tokens], output, id_map) do
    do_rewrite_selector_tokens(tokens, [token | output], id_map)
  end

  defp rewrite_known_selector_id(token, identifier, id_map) do
    case Map.fetch(id_map, identifier) do
      {:ok, rewritten_id} -> {:raw, "#" <> escape_css_identifier(rewritten_id)}
      :error -> token
    end
  end

  defp take_bracketed_tokens([], _depth, _output), do: :error

  defp take_bracketed_tokens([{:delim, "["} = token | tokens], depth, output) do
    take_bracketed_tokens(tokens, depth + 1, [token | output])
  end

  defp take_bracketed_tokens([{:delim, "]"} = closing | tokens], 1, output) do
    {:ok, Enum.reverse(output), closing, tokens}
  end

  defp take_bracketed_tokens([{:delim, "]"} = token | tokens], depth, output) do
    take_bracketed_tokens(tokens, depth - 1, [token | output])
  end

  defp take_bracketed_tokens([token | tokens], depth, output) do
    take_bracketed_tokens(tokens, depth, [token | output])
  end

  defp rewrite_attribute_selector(tokens, id_map) do
    with {leading, after_leading} <- take_css_trivia(tokens),
         {:ok, attribute, name, after_name} <- take_attribute_name(after_leading),
         true <- attribute in ["href", "xlink:href"],
         {before_operator, [{:delim, "="} = operator | after_operator]} <-
           take_css_trivia(after_name),
         {after_operator_trivia, [value | rest]} <- take_css_trivia(after_operator) do
      rewritten_value = rewrite_attribute_selector_value(value, id_map)

      leading ++
        name ++ before_operator ++ [operator] ++ after_operator_trivia ++ [rewritten_value | rest]
    else
      _other -> tokens
    end
  end

  defp take_attribute_name([{:ident, _raw, decoded} = token | rest]) do
    case take_namespaced_attribute_name(token, decoded, rest) do
      {:ok, _attribute, _name, _rest} = result -> result
      :error -> {:ok, String.downcase(decoded), [token], rest}
    end
  end

  defp take_attribute_name(_tokens), do: :error

  defp take_namespaced_attribute_name(prefix_token, prefix, tokens) do
    {before_separator, after_before_separator} = take_comment_tokens(tokens)

    case after_before_separator do
      [{:delim, "|"} = separator | after_separator] ->
        take_namespaced_attribute_local(
          prefix_token,
          prefix,
          before_separator,
          separator,
          after_separator
        )

      _other ->
        :error
    end
  end

  defp take_namespaced_attribute_local(
         prefix_token,
         prefix,
         before_separator,
         separator,
         tokens
       ) do
    {after_separator, rest} = take_comment_tokens(tokens)

    case rest do
      [{:ident, _local_raw, local} = local_token | tail] ->
        attribute = String.downcase(prefix <> ":" <> local)

        name =
          [prefix_token] ++
            before_separator ++ [separator] ++ after_separator ++ [local_token]

        {:ok, attribute, name, tail}

      _other ->
        :error
    end
  end

  defp rewrite_attribute_selector_value(
         {:string, _raw, decoded, quote, true} = token,
         id_map
       ) do
    with {:ok, target} <- local_fragment_target(decoded),
         {:ok, rewritten} <- Map.fetch(id_map, target) do
      raw = IO.iodata_to_binary([<<quote>>, "#", escape_css_string(rewritten, quote), <<quote>>])
      {:string, raw, "#" <> rewritten, quote, true}
    else
      _other -> token
    end
  end

  defp rewrite_attribute_selector_value(token, _id_map), do: token

  defp take_css_trivia(tokens), do: Enum.split_while(tokens, &css_trivia?/1)
  defp take_comment_tokens(tokens), do: Enum.split_while(tokens, &comment_token?/1)

  defp css_trivia?({:comment, _raw}), do: true
  defp css_trivia?({:whitespace, _raw}), do: true
  defp css_trivia?(_token), do: false

  defp rewrite_reference_target!(target, source, normalized_name, id_map) do
    case Map.fetch(id_map, target) do
      {:ok, rewritten_target} ->
        rewritten_target

      :error ->
        raise ArgumentError,
              "svg asset #{inspect(normalized_name)} references unknown local id #{inspect(target)} " <>
                "from #{source}"
    end
  end

  defp non_empty_contexts([]), do: [:rules]
  defp non_empty_contexts(contexts), do: contexts

  defp prepend_tokens(groups, output) do
    groups
    |> Enum.flat_map(&List.wrap/1)
    |> Enum.reverse(output)
  end

  defp render_tokens(tokens) do
    tokens
    |> Enum.map(&token_raw/1)
    |> IO.iodata_to_binary()
  end

  defp token_raw({:at_keyword, raw, _decoded}), do: raw
  defp token_raw({:bad_escape, raw}), do: raw
  defp token_raw({:bad_url, raw}), do: raw
  defp token_raw({:comment, raw}), do: raw
  defp token_raw({:delim, raw}), do: raw
  defp token_raw({:function, raw, _decoded}), do: raw <> "("
  defp token_raw({:hash, raw, _decoded, _flag}), do: raw
  defp token_raw({:ident, raw, _decoded}), do: raw
  defp token_raw({:raw, raw}), do: raw
  defp token_raw({:string, raw, _decoded, _quote, _valid?}), do: raw
  defp token_raw({:url, raw, _raw_name, _decoded, _closed?}), do: raw
  defp token_raw({:whitespace, raw}), do: raw

  defp take_comment(<<"/*", rest::binary>>) do
    case :binary.match(rest, "*/") do
      {index, 2} ->
        comment_size = index + 2
        <<body::binary-size(comment_size), tail::binary>> = rest
        {"/*" <> body, tail}

      :nomatch ->
        {"/*" <> rest, ""}
    end
  end

  defp take_css_whitespace(content), do: do_take_css_whitespace(content, [])

  defp do_take_css_whitespace(<<byte, rest::binary>>, acc) when byte in @css_whitespace do
    do_take_css_whitespace(rest, [<<byte>> | acc])
  end

  defp do_take_css_whitespace(rest, acc) do
    {acc |> Enum.reverse() |> IO.iodata_to_binary(), rest}
  end

  defp escape_css_identifier(identifier) do
    identifier
    |> String.to_charlist()
    |> Enum.map(&escape_css_identifier_codepoint/1)
    |> IO.iodata_to_binary()
  end

  defp escape_css_identifier_codepoint(codepoint)
       when codepoint in ?a..?z
       when codepoint in ?A..?Z
       when codepoint in ?0..?9
       when codepoint in [?_, ?-]
       when codepoint >= 0x80 do
    <<codepoint::utf8>>
  end

  defp escape_css_identifier_codepoint(0), do: <<0xFFFD::utf8>>

  defp escape_css_identifier_codepoint(codepoint) when codepoint in @newline do
    ["\\", Integer.to_string(codepoint, 16), " "]
  end

  defp escape_css_identifier_codepoint(codepoint), do: ["\\", <<codepoint::utf8>>]

  defp escape_css_string(content, quote) do
    content
    |> String.to_charlist()
    |> Enum.map(&escape_css_string_codepoint(&1, quote))
    |> IO.iodata_to_binary()
  end

  defp escape_css_string_codepoint(?\\, _quote), do: "\\\\"

  defp escape_css_string_codepoint(codepoint, quote) when codepoint == quote,
    do: ["\\", <<quote>>]

  defp escape_css_string_codepoint(codepoint, _quote) when codepoint in @newline do
    ["\\", Integer.to_string(codepoint, 16), " "]
  end

  defp escape_css_string_codepoint(codepoint, _quote), do: <<codepoint::utf8>>

  defp take_codepoint(<<codepoint::utf8, rest::binary>>), do: {<<codepoint::utf8>>, rest}
end
