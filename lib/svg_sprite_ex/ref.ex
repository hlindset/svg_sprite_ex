defmodule SvgSpriteEx.Ref do
  @moduledoc """
  Compile-time SVG ref helpers.

  Import this module to register SVG sources at compile time with `sprite_ref/1`,
  `sprite_ref/2`, and `inline_ref/1`.

  The helper functions here also expose the derived sheet paths and normalized
  sheet names used by the compile pipeline.
  """

  alias SvgSpriteEx.Source
  alias SvgSpriteEx.SpriteRef

  @ref_snapshot_vsn 1

  @doc false
  defmacro __using__(_opts) do
    quote do
      import unquote(__MODULE__), only: [inline_ref: 1, sprite_ref: 1, sprite_ref: 2]

      Module.register_attribute(__MODULE__, :__sprite_refs__, accumulate: true)
      Module.register_attribute(__MODULE__, :__inline_refs__, accumulate: true)

      @svg_sprite_ex_source_root SvgSpriteEx.Config.source_root!()
      @svg_sprite_ex_default_sheet SvgSpriteEx.Config.default_sheet!()
      @svg_sprite_ex_public_path SvgSpriteEx.Config.public_path!()
      @svg_sprite_ex_compiler_state_path SvgSpriteEx.Ref.compiler_state_path!()
      @before_compile unquote(__MODULE__)
      @after_compile unquote(__MODULE__)
    end
  end

  @doc ~S'''
  Builds a sprite reference using the default sheet.

  This macro accepts a compile-time literal icon path such as `"regular/xmark"`
  and returns a `%SvgSpriteEx.SpriteRef{}` that points at the configured default
  sprite sheet.

  ## Examples

  ```elixir
  defmodule MyAppWeb.IconComponents do
    use Phoenix.Component
    use SvgSpriteEx

    def close_icon(assigns) do
      ~H"""
      <.svg ref={sprite_ref("regular/xmark")} class="size-4" />
      """
    end
  end
  ```
  '''
  defmacro sprite_ref(name), do: build_sprite_ref_ast(name, [], __CALLER__)

  @doc ~S'''
  Builds a sprite reference with explicit options.

  Supported options:

  - `sheet` - the target sheet name, as a string or atom

  This macro accepts a compile-time literal icon path such as `"regular/xmark"`
  and returns a `%SvgSpriteEx.SpriteRef{}` that points at the specified sprite
  sheet.

  ## Examples

  ```elixir
  defmodule MyAppWeb.IconComponents do
    use Phoenix.Component
    use SvgSpriteEx

    def dashboard_icon(assigns) do
      ~H"""
      <.svg ref={sprite_ref("regular/xmark", sheet: "dashboard")} class="size-4" />
      """
    end
  end
  ```
  '''
  defmacro sprite_ref(name, opts) do
    build_sprite_ref_ast(name, opts, __CALLER__)
  end

  @doc ~S'''
  Builds an inline SVG reference.

  This macro accepts a compile-time literal icon path such as `"regular/xmark"`
  and returns a `%SvgSpriteEx.InlineRef{}` for use with `<.svg ref={...} />`.

  ## Examples

  ```elixir
  defmodule MyAppWeb.IconComponents do
    use Phoenix.Component
    use SvgSpriteEx

    def close_icon(assigns) do
      ~H"""
      <.svg ref={inline_ref("regular/xmark")} class="size-4" />
      """
    end
  end
  ```
  '''
  defmacro inline_ref(name) do
    build_inline_ref_ast(name, __CALLER__)
  end

  @doc false
  def sprite_href(name, source_root, sheet, public_path) do
    "#{sheet_public_path(sheet, public_path)}##{Source.sprite_id(name, source_root)}"
  end

  @doc false
  def sheet_build_path(sheet, build_path) do
    normalized_sheet = normalize_explicit_sheet!(sheet)
    sheet_build_path_from_normalized(normalized_sheet, build_path)
  end

  @doc false
  def sheet_public_path(sheet, public_path) do
    normalized_sheet = normalize_explicit_sheet!(sheet)
    sheet_public_path_from_normalized(normalized_sheet, public_path)
  end

  @doc false
  def normalize_sheet!(sheet, default_sheet)

  def normalize_sheet!(nil, default_sheet), do: normalize_sheet!(default_sheet, default_sheet)

  def normalize_sheet!(sheet, default_sheet) do
    sheet = coerce_sheet_name!(sheet, :sheet)
    default_sheet = coerce_sheet_name!(default_sheet, :default_sheet)

    sheet
    |> String.trim()
    |> case do
      "" -> default_sheet
      value -> value
    end
    |> sanitize_sheet!()
  end

  @doc false
  def compiler_state_path! do
    case Application.get_env(:svg_sprite_ex, :compiler_state_path_override) do
      path when is_binary(path) ->
        Path.expand(path)

      nil ->
        Path.join([Mix.Project.app_path(), ".mix", "svg_sprite_ex"])

      other ->
        raise ArgumentError,
              "expected :svg_sprite_ex, :compiler_state_path_override to be a binary path, got: #{inspect(other)}"
    end
  end

  @doc false
  def ref_snapshot_path(module, compiler_state_path \\ compiler_state_path!())

  def ref_snapshot_path(module, compiler_state_path)
      when is_atom(module) and is_binary(compiler_state_path) do
    module_hash =
      module
      |> Atom.to_string()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    Path.join([compiler_state_path, "refs", module_hash <> ".term"])
  end

  @doc false
  def ref_snapshot_vsn, do: @ref_snapshot_vsn

  @doc false
  def build_ref_snapshot(module, sprite_refs, inline_refs) do
    %{
      vsn: @ref_snapshot_vsn,
      module: module,
      sprite_refs: sprite_refs |> Enum.uniq() |> Enum.sort(),
      inline_refs: inline_refs |> Enum.uniq() |> Enum.sort()
    }
  end

  defp normalize_explicit_sheet!(sheet), do: normalize_sheet!(sheet, sheet)

  defmacro __before_compile__(env) do
    sprite_refs =
      env.module
      |> Module.get_attribute(:__sprite_refs__)
      |> List.wrap()
      |> Enum.uniq()
      |> Enum.sort()

    inline_refs =
      env.module
      |> Module.get_attribute(:__inline_refs__)
      |> List.wrap()
      |> Enum.uniq()
      |> Enum.sort()

    quote do
      @doc false
      def __sprite_refs__, do: unquote(sprite_refs)

      @doc false
      def __inline_refs__, do: unquote(inline_refs)
    end
  end

  @doc false
  def __after_compile__(env, _bytecode) do
    compiler_state_path = Module.get_attribute(env.module, :svg_sprite_ex_compiler_state_path)

    snapshot =
      build_ref_snapshot(
        env.module,
        env.module
        |> Module.get_attribute(:__sprite_refs__)
        |> List.wrap(),
        env.module
        |> Module.get_attribute(:__inline_refs__)
        |> List.wrap()
      )

    snapshot_path = ref_snapshot_path(env.module, compiler_state_path)

    if snapshot.sprite_refs == [] and snapshot.inline_refs == [] do
      File.rm(snapshot_path)
    else
      File.mkdir_p!(Path.dirname(snapshot_path))
      write_atomically!(snapshot_path, :erlang.term_to_binary(snapshot))
    end

    :ok
  end

  defp write_atomically!(path, contents) do
    temp_path = "#{path}.tmp-#{System.unique_integer([:positive, :monotonic])}"

    try do
      File.write!(temp_path, contents)
      File.rename!(temp_path, path)
    after
      File.rm(temp_path)
    end
  end

  defp build_sprite_ref_ast(name, opts, caller) do
    source_root = module_attribute!(caller, :svg_sprite_ex_source_root)
    default_sheet = module_attribute!(caller, :svg_sprite_ex_default_sheet)
    public_path = module_attribute!(caller, :svg_sprite_ex_public_path)

    literal_name =
      expand_literal_string!(
        name,
        caller,
        "sprite_ref expects compile-time literal string asset names"
      )

    literal_opts = expand_literal_opts!(opts, caller)
    normalized_name = expand_literal_name!(literal_name, caller, source_root)

    normalized_sheet =
      expand_literal_sheet!(Keyword.get(literal_opts, :sheet), caller, default_sheet)

    ref =
      %SpriteRef{
        name: normalized_name,
        sheet: normalized_sheet,
        sprite_id: Source.sprite_id_from_normalized(normalized_name),
        href: sprite_href_from_normalized(normalized_name, normalized_sheet, public_path)
      }

    register_sprite_ref!(caller.module, normalized_name, normalized_sheet, source_root)

    quote do
      %SvgSpriteEx.SpriteRef{
        name: unquote(ref.name),
        sheet: unquote(ref.sheet),
        sprite_id: unquote(ref.sprite_id),
        href: unquote(ref.href)
      }
    end
  end

  defp build_inline_ref_ast(name, caller) do
    source_root = module_attribute!(caller, :svg_sprite_ex_source_root)

    literal_name =
      expand_literal_string!(
        name,
        caller,
        "inline_ref/1 only accepts compile-time literal string asset names"
      )

    normalized_name = expand_literal_name!(literal_name, caller, source_root)
    register_inline_ref!(caller.module, normalized_name, source_root)

    quote do
      %SvgSpriteEx.InlineRef{
        name: unquote(normalized_name)
      }
    end
  end

  defp expand_literal_name!(name, caller, source_root) when is_binary(name) do
    normalized_name = Source.normalize_name!(name, source_root)
    _source = Source.read!(normalized_name, source_root)
    normalized_name
  rescue
    error ->
      reraise CompileError,
              [file: caller.file, line: caller.line, description: Exception.message(error)],
              __STACKTRACE__
  end

  defp expand_literal_string!(value, caller, message) do
    case expand_literal!(value, caller) do
      literal when is_binary(literal) ->
        literal

      _other ->
        raise CompileError, file: caller.file, line: caller.line, description: message
    end
  end

  defp expand_literal_sheet!(sheet, caller, default_sheet) do
    normalize_sheet!(sheet, default_sheet)
  rescue
    error in ArgumentError ->
      reraise CompileError,
              [file: caller.file, line: caller.line, description: error.message],
              __STACKTRACE__
  end

  defp expand_literal_opts!(opts, caller) do
    literal_opts = expand_literal!(opts, caller)

    cond do
      literal_opts == [] ->
        []

      Keyword.keyword?(literal_opts) ->
        validate_opts!(literal_opts, caller)

      true ->
        raise CompileError,
          file: caller.file,
          line: caller.line,
          description: "sprite_ref/2 only accepts compile-time literal keyword options"
    end
  end

  defp expand_literal!(value, caller) do
    expanded = Macro.expand(value, caller)

    if Macro.quoted_literal?(expanded) do
      {literal, _binding} = Code.eval_quoted(expanded, [], caller)
      literal
    else
      expanded
    end
  end

  defp validate_opts!(opts, caller) do
    case Keyword.keys(opts) -- [:sheet] do
      [] ->
        opts

      invalid_keys ->
        raise CompileError,
          file: caller.file,
          line: caller.line,
          description:
            "sprite_ref/2 only supports the :sheet option, got: #{inspect(invalid_keys)}"
    end
  end

  defp register_sprite_ref!(module, normalized_name, normalized_sheet, _source_root) do
    Module.put_attribute(module, :__sprite_refs__, {normalized_sheet, normalized_name})
  end

  defp register_inline_ref!(module, normalized_name, _source_root) do
    Module.put_attribute(module, :__inline_refs__, normalized_name)
  end

  defp sprite_href_from_normalized(name, normalized_sheet, public_path) do
    "#{sheet_public_path_from_normalized(normalized_sheet, public_path)}##{Source.sprite_id_from_normalized(name)}"
  end

  defp sheet_build_path_from_normalized(normalized_sheet, build_path) do
    Path.join(build_path, sheet_filename_from_normalized(normalized_sheet))
  end

  defp sheet_public_path_from_normalized(normalized_sheet, public_path) do
    Path.join(public_path, sheet_filename_from_normalized(normalized_sheet))
  end

  defp sheet_filename_from_normalized(normalized_sheet) do
    normalized_sheet <> ".svg"
  end

  defp sanitize_sheet!(sheet) do
    sanitized_sheet =
      sheet
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9_-]+/u, "_")
      |> String.replace(~r/_+/, "_")
      |> String.trim("_")

    if sanitized_sheet == "" do
      raise ArgumentError, "sprite sheet names must contain at least one alphanumeric character"
    end

    sanitized_sheet
  end

  defp coerce_sheet_name!(value, argument_name) do
    cond do
      is_binary(value) ->
        value

      is_atom(value) and not is_nil(value) ->
        Atom.to_string(value)

      true ->
        raise ArgumentError,
              "sprite sheet #{argument_name} must be strings or non-nil atoms, got: #{inspect(value)}"
    end
  end

  defp module_attribute!(%{module: module} = caller, attribute)
       when is_atom(module) and not is_nil(module) do
    case Module.get_attribute(module, attribute) do
      nil ->
        raise CompileError,
          file: caller.file,
          line: caller.line,
          description: "missing required module attribute @#{attribute}"

      value ->
        value
    end
  end

  defp module_attribute!(caller, _attribute) do
    raise CompileError,
      file: caller.file,
      line: caller.line,
      description:
        "SvgSpriteEx.Ref macros must be used inside a module that uses SvgSpriteEx or SvgSpriteEx.Ref"
  end
end
