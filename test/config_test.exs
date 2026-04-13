defmodule SvgSpriteEx.ConfigTest do
  use ExUnit.Case

  defmodule StaticPathResolverFixture do
    def static_path(path), do: "/digested" <> path
    def prepend_prefix(path, prefix), do: prefix <> path
  end

  test "build_path! rejects blank values" do
    module = compile_config_fixture!(build_path: "   ")

    assert_raise ArgumentError,
                 "invalid config :svg_sprite_ex, :build_path must not be blank",
                 fn ->
                   module.build_path!()
                 end
  end

  test "public_path! rejects blank values" do
    module = compile_config_fixture!(public_path: "   ")

    assert_raise ArgumentError,
                 "invalid config :svg_sprite_ex, :public_path must not be blank",
                 fn ->
                   module.public_path!()
                 end
  end

  test "default_sheet! rejects blank values" do
    module = compile_config_fixture!(default_sheet: "   ")

    assert_raise ArgumentError,
                 "invalid config :svg_sprite_ex, :default_sheet must not be blank",
                 fn ->
                   module.default_sheet!()
                 end
  end

  test "resolve_public_path!/1 falls back to the configured public path when no resolver is set" do
    previous_resolver = Application.get_env(:svg_sprite_ex, :static_path_resolver)
    Application.delete_env(:svg_sprite_ex, :static_path_resolver)

    on_exit(fn ->
      if is_nil(previous_resolver) do
        Application.delete_env(:svg_sprite_ex, :static_path_resolver)
      else
        Application.put_env(:svg_sprite_ex, :static_path_resolver, previous_resolver)
      end
    end)

    assert SvgSpriteEx.Config.resolve_public_path!("/sprites/icons.svg") == "/sprites/icons.svg"
  end

  test "resolve_public_path!/1 supports module and mfa resolvers" do
    previous_resolver = Application.get_env(:svg_sprite_ex, :static_path_resolver)

    on_exit(fn ->
      if is_nil(previous_resolver) do
        Application.delete_env(:svg_sprite_ex, :static_path_resolver)
      else
        Application.put_env(:svg_sprite_ex, :static_path_resolver, previous_resolver)
      end
    end)

    Application.put_env(:svg_sprite_ex, :static_path_resolver, StaticPathResolverFixture)

    assert SvgSpriteEx.Config.resolve_public_path!("/sprites/icons.svg") ==
             "/digested/sprites/icons.svg"

    Application.put_env(
      :svg_sprite_ex,
      :static_path_resolver,
      {StaticPathResolverFixture, :prepend_prefix, ["/prefix"]}
    )

    assert SvgSpriteEx.Config.resolve_public_path!("/sprites/icons.svg") ==
             "/prefix/sprites/icons.svg"
  end

  defp compile_config_fixture!(overrides) do
    module = unique_module()
    original_env = Application.get_all_env(:svg_sprite_ex)

    on_exit(fn ->
      for {key, _value} <- Application.get_all_env(:svg_sprite_ex),
          not Keyword.has_key?(original_env, key) do
        Application.delete_env(:svg_sprite_ex, key)
      end

      Application.put_all_env(svg_sprite_ex: original_env)
      :code.purge(module)
      :code.delete(module)
    end)

    default_env = [
      source_root: Path.expand("fixtures/icons", __DIR__),
      build_path: Path.expand("../tmp/sprites", __DIR__),
      public_path: "/sprites",
      default_sheet: "sprites"
    ]

    Application.put_all_env(svg_sprite_ex: Keyword.merge(default_env, overrides))

    source =
      "lib/svg_sprite_ex/config.ex"
      |> Path.expand(File.cwd!())
      |> File.read!()
      |> String.replace("defmodule SvgSpriteEx.Config do", "defmodule #{inspect(module)} do")

    Code.compile_string(source, "lib/svg_sprite_ex/config.ex")

    module
  end

  defp unique_module do
    Module.concat([
      SvgSpriteEx,
      ConfigFixtures,
      :"fixture_#{System.unique_integer([:positive])}"
    ])
  end
end
