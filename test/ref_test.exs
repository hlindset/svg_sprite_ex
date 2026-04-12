defmodule SvgSpriteEx.RefTest do
  use ExUnit.Case

  alias SvgSpriteEx.InlineRef
  alias SvgSpriteEx.Config
  alias SvgSpriteEx.Ref
  alias SvgSpriteEx.SpriteRef

  test "sprite_ref/2 returns a sprite ref and registers sorted unique refs" do
    module = unique_module(:sheeted_fixture)

    compile_module!(
      module,
      """
      def ui_ref, do: sprite_ref("regular/xmark", sheet: :" UI Actions ")
      def duplicate_ref, do: sprite_ref("regular/xmark", sheet: "ui_actions")
      """
    )

    ref = module.ui_ref()

    assert %SpriteRef{} = ref
    assert ref.sheet == "ui_actions"
    assert ref.href == "/assets/sprites/ui_actions.svg##{ref.sprite_id}"
    assert module.__sprite_refs__() == [{"ui_actions", "regular/xmark"}]
  end

  test "inline_ref/1 returns an inline ref and registers sorted unique refs" do
    module = unique_module(:inline_fixture)

    compile_module!(
      module,
      """
      def icon_ref, do: inline_ref("regular/xmark")
      def duplicate_ref, do: inline_ref("regular/xmark")
      """
    )

    ref = module.icon_ref()

    assert %InlineRef{} = ref
    assert ref.name == "regular/xmark"
    assert ref.registry == SvgSpriteEx.Generated.InlineIcons
    assert module.__inline_refs__() == ["regular/xmark"]
  end

  test "inline_ref does not track the source file as an external resource" do
    module = unique_module(:inline_without_external_resource)

    compile_module!(module, """
    def ref, do: inline_ref("regular/xmark")
    """)

    refute Enum.any?(module_external_resources(module))
  end

  test "sheet path helpers normalize sheet names" do
    assert Ref.sheet_build_path(:" UI Actions ", "/tmp/sprites") == "/tmp/sprites/ui_actions.svg"

    assert Ref.sheet_build_path(" UI Actions ", "/tmp/sprites") == "/tmp/sprites/ui_actions.svg"

    assert Ref.sheet_public_path(:" UI Actions ", "/assets/sprites") ==
             "/assets/sprites/ui_actions.svg"

    assert Ref.sheet_public_path(" UI Actions ", "/assets/sprites") ==
             "/assets/sprites/ui_actions.svg"

    assert Ref.sprite_href("regular/xmark", "/tmp/svg-root", :" UI Actions ", "/assets/sprites") =~
             "/assets/sprites/ui_actions.svg#"

    assert Ref.sprite_href("regular/xmark", "/tmp/svg-root", " UI Actions ", "/assets/sprites") =~
             "/assets/sprites/ui_actions.svg#"
  end

  test "normalize_sheet!/2 falls back to the default sheet for blank values" do
    assert Ref.normalize_sheet!("   ", "sprites") == "sprites"
    assert Ref.normalize_sheet!(nil, "sprites") == "sprites"
  end

  test "default_sheet! falls back to sprites when config is omitted" do
    assert Config.default_sheet!() == "sprites"
  end

  test "normalize_sheet!/2 rejects invalid sheet names" do
    assert_raise ArgumentError, ~r/must be strings/, fn ->
      Ref.normalize_sheet!(123, "sprites")
    end

    assert_raise ArgumentError, ~r/default_sheet must be strings/, fn ->
      Ref.normalize_sheet!("alerts", 123)
    end

    assert_raise ArgumentError, ~r/must contain at least one alphanumeric character/, fn ->
      Ref.normalize_sheet!("___", "sprites")
    end
  end

  test "sprite_ref raises a compile error for invalid sheet values" do
    module = unique_module(:invalid_sheet_type)

    assert_raise CompileError, ~r/must be strings/, fn ->
      compile_module!(module, """
      def ref, do: sprite_ref("regular/xmark", sheet: 123)
      """)
    end

    module = unique_module(:invalid_sheet_atom)

    assert_raise CompileError, ~r/must contain at least one alphanumeric character/, fn ->
      compile_module!(module, """
      def ref, do: sprite_ref("regular/xmark", sheet: :___)
      """)
    end

    module = unique_module(:invalid_sheet_name)

    assert_raise CompileError, ~r/must contain at least one alphanumeric character/, fn ->
      compile_module!(module, """
      def ref, do: sprite_ref("regular/xmark", sheet: "___")
      """)
    end
  end

  test "sprite_ref raises a compile error outside a module context" do
    assert_raise CompileError, ~r/must be used inside a module that uses SvgSpriteEx/, fn ->
      Code.eval_string("""
      require SvgSpriteEx.Ref
      SvgSpriteEx.Ref.sprite_ref("regular/xmark")
      """)
    end
  end

  test "sprite_ref raises a compile error for non-literal names" do
    module = unique_module(:non_literal_name)

    assert_raise CompileError, ~r/compile-time literal string asset names/, fn ->
      compile_module!(module, """
      def ref, do: sprite_ref(Path.join("regular", "xmark"))
      """)
    end
  end

  test "inline_ref raises a compile error for non-literal names" do
    module = unique_module(:non_literal_inline_name)

    assert_raise CompileError, ~r/compile-time literal string asset names/, fn ->
      compile_module!(module, """
      def ref, do: inline_ref(Path.join("regular", "xmark"))
      """)
    end
  end

  test "sprite_ref raises a compile error for non-literal keyword options" do
    module = unique_module(:non_literal_opts)

    assert_raise CompileError, ~r/compile-time literal keyword options/, fn ->
      compile_module!(module, """
      def ref, do: sprite_ref("regular/xmark", Enum.into([sheet: "alerts"], []))
      """)
    end
  end

  test "sprite_ref raises a compile error for unsupported options" do
    module = unique_module(:bad_opts)

    assert_raise CompileError, ~r/only supports the :sheet option/, fn ->
      compile_module!(module, """
      def ref, do: sprite_ref("regular/xmark", color: "red")
      """)
    end
  end

  test "sprite_ref raises a compile error when the source asset is missing" do
    module = unique_module(:missing_asset)

    assert_raise CompileError, ~r/could not be resolved under the configured source root/, fn ->
      compile_module!(module, """
      def ref, do: sprite_ref("regular/missing")
      """)
    end
  end

  test "sprite_ref raises a compile error when the source asset cannot be read" do
    module = unique_module(:unreadable_asset)

    with_unreadable_asset_source_root("svg_sprite_ex_unreadable_source", fn source_root ->
      assert_raise CompileError, ~r/could not read file/, fn ->
        compile_module!(module, """
        @svg_sprite_ex_source_root #{inspect(source_root)}
        @svg_sprite_ex_default_sheet "sprites"
        @svg_sprite_ex_public_path "/assets/sprites"

        def ref, do: sprite_ref("regular/xmark")
        """)
      end
    end)
  end

  test "inline_ref raises a compile error when the source asset cannot be read" do
    module = unique_module(:unreadable_inline_asset)

    with_unreadable_asset_source_root("svg_sprite_ex_unreadable_inline_source", fn source_root ->
      assert_raise CompileError, ~r/could not read file/, fn ->
        compile_module!(module, """
        @svg_sprite_ex_source_root #{inspect(source_root)}
        @svg_sprite_ex_default_sheet "sprites"
        @svg_sprite_ex_public_path "/assets/sprites"

        def ref, do: inline_ref("regular/xmark")
        """)
      end
    end)
  end

  test "inline_ref raises a compile error when the source asset is missing" do
    module = unique_module(:missing_inline_asset)

    assert_raise CompileError, ~r/could not be resolved under the configured source root/, fn ->
      compile_module!(module, """
      def ref, do: inline_ref("regular/missing")
      """)
    end
  end

  defp compile_module!(module, body) do
    path =
      System.tmp_dir!()
      |> Path.join("svg_sprite_ex_ref_test_#{System.unique_integer([:positive])}.exs")
      |> Path.expand()

    compiler_state_path =
      System.tmp_dir!()
      |> Path.join("svg_sprite_ex_ref_state_#{System.unique_integer([:positive])}")
      |> Path.expand()

    File.write!(
      path,
      """
      defmodule #{inspect(module)} do
        use SvgSpriteEx

        #{body}
      end
      """
    )

    previous_override = Application.get_env(:svg_sprite_ex, :compiler_state_path_override)
    Application.put_env(:svg_sprite_ex, :compiler_state_path_override, compiler_state_path)

    ExUnit.Callbacks.on_exit(fn ->
      File.rm_rf!(path)
      File.rm_rf!(compiler_state_path)
    end)

    try do
      Code.compile_file(path)
    after
      if is_nil(previous_override) do
        Application.delete_env(:svg_sprite_ex, :compiler_state_path_override)
      else
        Application.put_env(:svg_sprite_ex, :compiler_state_path_override, previous_override)
      end
    end
  end

  defp module_external_resources(module) do
    module.module_info(:attributes)
    |> Keyword.get(:external_resource, [])
  end

  defp unique_module(suffix) do
    Module.concat([SvgSpriteEx, RefFixtures, :"#{suffix}_#{System.unique_integer([:positive])}"])
  end

  defp with_unreadable_asset_source_root(prefix, fun) when is_function(fun, 1) do
    source_root =
      System.tmp_dir!()
      |> Path.join("#{prefix}_#{System.unique_integer([:positive])}")

    asset_path = Path.join([source_root, "regular", "xmark.svg"])
    File.mkdir_p!(Path.dirname(asset_path))
    File.write!(asset_path, "<svg xmlns=\"http://www.w3.org/2000/svg\"></svg>")
    File.chmod!(asset_path, 0o000)

    ExUnit.Callbacks.on_exit(fn ->
      File.chmod!(asset_path, 0o644)
      File.rm_rf!(source_root)
    end)

    fun.(source_root)
  end
end
