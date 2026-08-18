defmodule SvgSpriteEx.SourceTest do
  use ExUnit.Case, async: true

  alias SvgSpriteEx.Source

  test "read!/2 returns parsed source data" do
    svg_source_root = unique_tmp_dir!("read")
    File.mkdir_p!(Path.join(svg_source_root, "icons"))

    file_path = Path.join(svg_source_root, "icons/check.svg")

    File.write!(
      file_path,
      """
      <svg viewBox="0 0 24 24" fill="currentColor">
        <path d="M0 0h24v24H0z" />
      </svg>
      """
    )

    source = Source.read!("icons/check", svg_source_root)

    assert source.name == "icons/check"
    assert source.file_path == file_path
    assert source.attributes["viewBox"] == "0 0 24 24"
    assert source.attributes["fill"] == "currentColor"
    assert source.inner_content =~ "<path"
  end

  test "read!/2 converts xmerl Unicode attributes and content to UTF-8" do
    svg_source_root = unique_tmp_dir!("unicode")
    File.mkdir_p!(Path.join(svg_source_root, "icons"))

    File.write!(
      Path.join(svg_source_root, "icons/unicode.svg"),
      """
      <svg viewBox="0 0 24 24" data-label="caf&#xE9;">
        <text>snow &#x2603;</text>
      </svg>
      """
    )

    source = Source.read!("icons/unicode", svg_source_root)

    assert source.attributes["data-label"] == "café"
    assert source.inner_content =~ "<text>snow ☃</text>"
    assert String.valid?(source.inner_content)
  end

  test "read!/2 parses literal UTF-8 attributes and content" do
    svg_source_root = unique_tmp_dir!("literal-unicode")
    File.mkdir_p!(Path.join(svg_source_root, "icons"))

    File.write!(
      Path.join(svg_source_root, "icons/literal_unicode.svg"),
      """
      <svg viewBox="0 0 24 24" data-label="café">
        <text>snow ☃</text>
      </svg>
      """
    )

    source = Source.read!("icons/literal_unicode", svg_source_root)

    assert source.attributes["data-label"] == "café"
    assert source.inner_content =~ "<text>snow ☃</text>"
    assert String.valid?(source.inner_content)
  end

  test "read!/2 rejects embedded style elements" do
    Enum.each(
      [
        {"direct", "<style>#shape { fill: red }</style>"},
        {"nested", "<defs><style>.cls-1 { fill: red }</style></defs>"},
        {"empty", "<style></style>"}
      ],
      fn {name, content} ->
        svg_source_root = unique_tmp_dir!("embedded-style-#{name}")
        File.mkdir_p!(Path.join(svg_source_root, "icons"))

        File.write!(
          Path.join(svg_source_root, "icons/#{name}.svg"),
          ~s(<svg viewBox="0 0 24 24">#{content}<path id="shape" /></svg>)
        )

        assert_raise ArgumentError,
                     ~r/svg asset "icons\/#{name}" contains an unsupported <style> element.*SVGO/,
                     fn -> Source.read!("icons/#{name}", svg_source_root) end
      end
    )
  end

  test "read!/2 preserves inline style attributes" do
    svg_source_root = unique_tmp_dir!("inline-style-attribute")
    File.mkdir_p!(Path.join(svg_source_root, "icons"))

    File.write!(
      Path.join(svg_source_root, "icons/styled.svg"),
      ~s|<svg viewBox="0 0 24 24"><path style="fill: url(#paint); color: #fff" /></svg>|
    )

    assert Source.read!("icons/styled", svg_source_root).inner_content =~
             ~s|style="fill: url(#paint); color: #fff"|
  end

  test "source_file_path!/2 accepts files under a relative source root" do
    svg_source_root = unique_tmp_dir!("relative-root")
    relative_root = Path.relative_to(svg_source_root, File.cwd!(), force: true)

    File.mkdir_p!(Path.join(svg_source_root, "icons"))

    file_path = Path.join(svg_source_root, "icons/check.svg")

    File.write!(
      file_path,
      """
      <svg viewBox="0 0 24 24">
        <path d="M0 0h24v24H0z" />
      </svg>
      """
    )

    assert Source.source_file_path!("icons/check", relative_root) ==
             Path.join(relative_root, "icons/check.svg")
  end

  test "normalize_name!/2 canonicalizes safe relative paths" do
    svg_source_root = unique_tmp_dir!("canonical-paths")
    relative_root = Path.relative_to(svg_source_root, File.cwd!(), force: true)

    assert Source.normalize_name!("./icons//check", relative_root) == "icons/check"
    assert Source.normalize_name!("icons\\nested\\check", relative_root) == "icons/nested/check"
  end

  test "normalize_name!/2 allows dots in logical names when they are not svg extensions" do
    svg_source_root = unique_tmp_dir!("dotted-names")

    assert Source.normalize_name!("icons/check.dark", svg_source_root) == "icons/check.dark"

    assert Source.normalize_name!("icons/v1.filled/check", svg_source_root) ==
             "icons/v1.filled/check"
  end

  test "normalize_name!/2 rejects traversal outside the source root" do
    svg_source_root = unique_tmp_dir!("traversal-root")
    relative_root = Path.relative_to(svg_source_root, File.cwd!(), force: true)

    for input <- ["../escape", "/etc/passwd", "dir/../../icon", "//server/share"] do
      assert_raise ArgumentError, ~r/must stay within the configured source root/, fn ->
        Source.normalize_name!(input, relative_root)
      end
    end
  end

  test "normalize_name!/2 rejects blank names" do
    assert_raise ArgumentError, ~r/svg asset name cannot be blank/, fn ->
      Source.normalize_name!("   ", unique_tmp_dir!("blank-name"))
    end
  end

  test "normalize_name!/2 rejects query params and fragments" do
    svg_source_root = unique_tmp_dir!("query-fragment")

    assert_raise ArgumentError, ~r/must not include query params or fragments/, fn ->
      Source.normalize_name!("icons/check?variant=filled", svg_source_root)
    end

    assert_raise ArgumentError, ~r/must not include query params or fragments/, fn ->
      Source.normalize_name!("icons/check#fragment", svg_source_root)
    end
  end

  test "normalize_name!/2 rejects trailing svg extensions" do
    assert_raise ArgumentError, ~r/must omit the trailing \.svg extension/, fn ->
      Source.normalize_name!("icons/check.svg", unique_tmp_dir!("extension"))
    end
  end

  test "normalize_name!/2 rejects blank source roots" do
    assert_raise ArgumentError, ~r/source_root cannot be blank/, fn ->
      Source.normalize_name!("icons/check", "   ")
    end
  end

  test "read!/2 and source_file_path!/2 reject non-directory source roots" do
    svg_source_root = unique_tmp_dir!("source-root-file")
    source_root_file = Path.join(svg_source_root, "config.txt")
    File.write!(source_root_file, "not a directory")

    for {fun, args} <- [
          {:read!, ["icons/check", source_root_file]},
          {:source_file_path!, ["icons/check", source_root_file]}
        ] do
      assert_raise ArgumentError, ~r/source_root must point to an existing directory/, fn ->
        apply(Source, fun, args)
      end
    end
  end

  test "source_file_path!/2 raises when the asset cannot be resolved" do
    assert_raise ArgumentError, ~r/could not be resolved under the configured source root/, fn ->
      Source.source_file_path!("icons/missing", unique_tmp_dir!("missing-file"))
    end
  end

  test "public functions reject non-binary inputs" do
    root = unique_tmp_dir!("invalid-inputs")

    for {fun, args} <- [
          {:read!, [nil, root]},
          {:normalize_name!, [nil, root]},
          {:source_file_path!, [nil, root]},
          {:sprite_id, [nil, root]}
        ] do
      assert_raise ArgumentError, ~r/expects binary name and source_root/, fn ->
        apply(Source, fun, args)
      end
    end
  end

  test "sprite_id_from_normalized/1 rejects non-binary input" do
    assert_raise ArgumentError, ~r/expects a binary normalized_name/, fn ->
      Source.sprite_id_from_normalized(nil)
    end
  end

  test "sprite_id_from_normalized/1 derives the same stable id without re-normalizing" do
    normalized_name = "icons/check"

    assert Source.sprite_id_from_normalized(normalized_name) ==
             Source.sprite_id(normalized_name, unique_tmp_dir!("normalized-sprite-id"))
  end

  test "read!/2 raises for invalid xml" do
    svg_source_root = unique_tmp_dir!("invalid-xml")
    File.mkdir_p!(Path.join(svg_source_root, "icons"))

    File.write!(Path.join(svg_source_root, "icons/bad.svg"), "<svg><path></svg")

    assert_raise ArgumentError, ~r/does not contain valid XML/, fn ->
      Source.read!("icons/bad", svg_source_root)
    end
  end

  test "read!/2 reports invalid UTF-8 bytes as asset-aware invalid XML" do
    svg_source_root = unique_tmp_dir!("invalid-utf8")
    File.mkdir_p!(Path.join(svg_source_root, "icons"))
    file_path = Path.join(svg_source_root, "icons/invalid_utf8.svg")

    File.write!(file_path, ["<svg><text>", <<0xFF>>, "</text></svg>"])

    error =
      assert_raise ArgumentError, fn ->
        Source.read!("icons/invalid_utf8", svg_source_root)
      end

    assert Exception.message(error) =~
             "svg asset #{inspect(file_path)} does not contain valid XML:"
  end

  test "read!/2 raises when the root element is not svg" do
    svg_source_root = unique_tmp_dir!("invalid-root")
    File.mkdir_p!(Path.join(svg_source_root, "icons"))

    File.write!(
      Path.join(svg_source_root, "icons/not_svg.svg"),
      """
      <g>
        <path d="M0 0h24v24H0z" />
      </g>
      """
    )

    assert_raise ArgumentError, ~r/does not contain a valid <svg> root/, fn ->
      Source.read!("icons/not_svg", svg_source_root)
    end
  end

  defp unique_tmp_dir!(suffix) do
    path =
      System.tmp_dir!()
      |> Path.join("svg_sprite_ex_test_#{suffix}_#{System.unique_integer([:positive])}")
      |> Path.expand()

    File.mkdir_p!(path)
    ExUnit.Callbacks.on_exit(fn -> File.rm_rf!(path) end)
    path
  end
end
