# SvgSpriteEx

`SvgSpriteEx` lets you turn SVG files into compile-time icon refs for Phoenix
components and LiveView.

You can render icons in two ways:

- `ref={sprite_ref("...")}` renders a `<svg><use ... /></svg>` wrapper backed
  by a generated sprite sheet
- `ref={inline_ref("...")}` renders the full SVG inline in the document

## Installation

Add `svg_sprite_ex` to your dependencies:

```elixir
def deps do
  [
    {:svg_sprite_ex, "~> 0.1.0"}
  ]
end
```

Then register the sprite compiler after the default Mix compilers so it can
discover `sprite_ref/1`, `sprite_ref/2`, and `inline_ref/1` usages.

```elixir
def project do
  [
    app: :my_app,
    version: "0.1.0",
    elixir: "~> 1.19",
    compilers: Mix.compilers() ++ [:svg_sprite_ex_assets],
    deps: deps()
  ]
end
```

## Configuration

```elixir
import Config

config :svg_sprite_ex,
  source_root: Path.expand("../priv/icons", __DIR__),
  build_path: Path.expand("../priv/static/svgs", __DIR__),
  public_path: "/svgs"
```

### Required configuration

- `source_root` - absolute path to the directory that contains source SVG files.
- `build_path` - absolute path where the compiler generates sprite sheets.
- `public_path` - public URL prefix for `sprite_ref/1` hrefs.

### Optional configuration

- `default_sheet` - default sprite sheet name when no `sheet` option is
  given. Defaults to `sprites`.

Given the config above, if your icon file lives at
`priv/icons/regular/xmark.svg`, the logical icon name is `regular/xmark`.

Note that `sprite_ref` and `inline_ref` only accept compile-time literal
values. This is how the compiler discovers which icons need to be included in
the generated outputs.

## How it works

When you run `mix compile`, the compiler:

- scans compiled modules for `sprite_ref` and `inline_ref` calls
- writes one SVG sprite sheet per sheet name into `build_path`
- compiles generated modules for inline SVG lookup and runtime metadata lookup

With the config above, `sprite_ref("regular/xmark")` returns a
`%SvgSpriteEx.SpriteRef{}` whose `href` looks like
`/svgs/sprites.svg#icon-812c65654d41`.

Your application must serve the generated files from the same public path you
configured. For example: Write sprite sheets into `priv/static/svgs`, and
serve them from `/svgs`.

## Phoenix usage

Use `SvgSpriteEx` in any component, LiveView, or HTML module that renders icons:

```elixir
defmodule MyAppWeb.MyComponents do
  use Phoenix.Component
  use SvgSpriteEx
end
```

This will import:

- the `<.svg>` function component from `SvgSpriteEx.Svg`
- the `sprite_ref` and `inline_ref` macros from `SvgSpriteEx.Ref`

### Render using a sprite sheet

```elixir
defmodule MyAppWeb.MyComponents do
  use Phoenix.Component
  use SvgSpriteEx

  def close_icon(assigns) do
    ~H"""
    <.svg ref={sprite_ref("regular/xmark")} class="size-4" />
    """
  end
end
```

By default the SVGs are placed in a sprite sheet called `sprites.svg`, but you
can also compile icons to other named sheets:

```elixir
<.svg ref={sprite_ref("regular/xmark", sheet: "dashboard")} class="size-4" />
```

### Render inline SVGs

Inline mode skips the sprite sheet and renders the SVG inline in the document.

```elixir
<.svg ref={inline_ref("regular/xmark")} class="size-4" />
```

This lets you serve the raw SVG markup in the page instead of a `<use>`
reference, without doing runtime file reads.

## Runtime metadata

`SvgSpriteEx` also exposes runtime metadata for compiled outputs:

```elixir
SvgSpriteEx.sprite_sheets()
#=> [%SvgSpriteEx.SpriteSheetMeta{...}]

SvgSpriteEx.sprite_sheet("dashboard")
#=> %SvgSpriteEx.SpriteSheetMeta{...}

SvgSpriteEx.sprites_in_sheet("dashboard")
#=> [%SvgSpriteEx.SpriteMeta{...}]

SvgSpriteEx.inline_svgs()
#=> [%SvgSpriteEx.InlineSvgMeta{...}]

SvgSpriteEx.inline_svg("regular/xmark")
#=> %SvgSpriteEx.InlineSvgMeta{...}
```

## Patterns

### Preload a single sprite sheet

When a layout or component knows it will use a specific sprite sheet, you can
preload it by looking up the compiled sheet metadata with `sprite_sheet/1` and
rendering a `<link rel="preload" ...>` tag.

In a helper or function component:

```elixir
defmodule MyAppWeb.MyComponents do
  use Phoenix.Component

  attr :sheet, :string, required: true

  def sprite_sheet_preload(assigns) do
    assigns = assign(assigns, :sheet_meta, SvgSpriteEx.sprite_sheet(assigns.sheet))

    ~H"""
    <link
      :if={@sheet_meta}
      rel="preload"
      href={@sheet_meta.public_path}
      as="image"
      type="image/svg+xml"
    />
    """
  end
end
```

Then in a layout or page template:

```elixir
<.sprite_sheet_preload sheet="dashboard" />
```
