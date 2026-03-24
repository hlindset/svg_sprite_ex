defmodule SpriteEx.ConfigTest do
  use ExUnit.Case

  test "build_path! rejects blank values" do
    module = compile_config_fixture!(build_path: "   ")

    assert_raise ArgumentError, "invalid config :sprite_ex, :build_path must not be blank", fn ->
      module.build_path!()
    end
  end

  test "public_path! rejects blank values" do
    module = compile_config_fixture!(public_path: "   ")

    assert_raise ArgumentError, "invalid config :sprite_ex, :public_path must not be blank", fn ->
      module.public_path!()
    end
  end

  test "default_sheet! rejects blank values" do
    module = compile_config_fixture!(default_sheet: "   ")

    assert_raise ArgumentError,
                 "invalid config :sprite_ex, :default_sheet must not be blank",
                 fn ->
                   module.default_sheet!()
                 end
  end

  defp compile_config_fixture!(overrides) do
    module = unique_module()
    original_env = Application.get_all_env(:sprite_ex)

    on_exit(fn ->
      for {key, _value} <- Application.get_all_env(:sprite_ex),
          not Keyword.has_key?(original_env, key) do
        Application.delete_env(:sprite_ex, key)
      end

      Application.put_all_env(sprite_ex: original_env)
      :code.purge(module)
      :code.delete(module)
    end)

    default_env = [
      source_root: Path.expand("fixtures/icons", __DIR__),
      build_path: Path.expand("../tmp/sprites", __DIR__),
      public_path: "/sprites",
      default_sheet: "sprites"
    ]

    Application.put_all_env(sprite_ex: Keyword.merge(default_env, overrides))

    source =
      "lib/sprite_ex/config.ex"
      |> Path.expand(File.cwd!())
      |> File.read!()
      |> String.replace("defmodule SpriteEx.Config do", "defmodule #{inspect(module)} do")

    Code.compile_string(source, "lib/sprite_ex/config.ex")

    module
  end

  defp unique_module do
    Module.concat([
      SpriteEx,
      ConfigFixtures,
      :"fixture_#{System.unique_integer([:positive])}"
    ])
  end
end
