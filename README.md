# SvgSpriteEx

`SvgSpriteEx` lets you turn svg files into compile-time svg refs for Phoenix
components and LiveView.

You can render svgs in two ways:

- `ref={sprite_ref("...")}` renders a `<svg><use ... /></svg>` wrapper backed
  by a generated sprite sheet
- `ref={inline_ref("...")}` renders the full svg inline in the document

## Installation

Add `svg_sprite_ex` to your dependencies:

```elixir
def deps do
  [
    {:svg_sprite_ex, "~> 0.2.0"}
  ]
end
```

Then register the sprite compiler ahead of the default Mix compilers so it can
install its Elixir compile callback and collect `sprite_ref/1`, `sprite_ref/2`,
and `inline_ref/1` usages after module compilation.

```elixir
def project do
  [
    app: :my_app,
    version: "0.2.0",
    elixir: "~> 1.19",
    compilers: [:svg_sprite_ex_assets] ++ Mix.compilers(),
    deps: deps()
  ]
end
```

Note that `:svg_sprite_ex_assets` **must** appear before the `:elixir` compiler.

When using Phoenix code reloading in development, add `:svg_sprite_ex_assets`
to `reloadable_compilers`. Phoenix only reruns the compilers listed there
during request-time reloads, so omitting it can still reload the page before
the generated sprite sheet or runtime metadata file has been rebuilt.

```elixir
config :my_app, MyAppWeb.Endpoint,
  reloadable_compilers: [:svg_sprite_ex_assets, :elixir, :app]
```

Adjust the list to match the compilers used in your project.

## Upgrade notes

- `%SvgSpriteEx.InlineRef{}` is now a one-field struct with only `:name`.
  Code that manually constructs or pattern matches on the old `:registry` field
  must be updated.
- Upgrading from older compiler snapshot/runtime data formats requires a clean
  rebuild. Run `mix clean && mix compile`, or delete the app's
  `.mix/svg_sprite_ex` compiler state directory before recompiling.
- When multiple apps share the same code path, stale `runtime_data.etf` files
  from sibling apps are ignored until those apps rebuild with the current
  schema.

## Configuration

```elixir
import Config

config :svg_sprite_ex,
  source_root: Path.expand("../priv/icons", __DIR__),
  build_path: Path.expand("../priv/static/svgs", __DIR__),
  public_path: "/svgs",
  default_sheet: "sprites",
  static_path_resolver: MyAppWeb.Endpoint
```

### Required configuration

- `source_root` - absolute path to the directory that contains source svg files.
- `build_path` - absolute path where the compiler generates sprite sheets.
- `public_path` - nondigested public URL prefix for generated sprite sheets.

### Optional configuration

- `default_sheet` - default sprite sheet name when no `sheet` option is
  given. Defaults to `sprites`.
- `static_path_resolver` - runtime resolver for sprite sheet URLs. This can be
  a module that exports `static_path/1`, or `{module, function}` /
  `{module, function, extra_args}`. When omitted, `SvgSpriteEx` renders the
  configured `public_path` unchanged.

Given the config above, if your svg file lives at
`priv/icons/regular/xmark.svg`, the logical svg name is `regular/xmark`.

Note that `sprite_ref` and `inline_ref` only accept compile-time literal
values. This is how the compiler discovers which svgs need to be included in
the generated outputs.

## How it works

When you run `mix compile`, the compiler:

- persists one ref snapshot per module that uses the macros
- hashes the referenced svg files and compiler inputs to detect asset changes
- writes one svg sprite sheet per sheet name into `build_path`
- writes a runtime data artifact that powers inline svg lookup and metadata APIs

Active modules contribute refs directly from their compiled exports, while
persisted ref snapshots remain on disk for incremental compiler state and stale
snapshot cleanup.

Generated sprite refs carry the sheet public path and sprite id separately. At
render time, `<.svg>` resolves the public path through `static_path_resolver`
when configured, so Phoenix digested asset URLs work without changing
`sprite_ref(...)` call sites.

Your application must serve the generated files from the same public path you
configured. For example: Write sprite sheets into `priv/static/svgs`, and
serve them from `/svgs`.

## Phoenix usage

Use `SvgSpriteEx` in any component, LiveView, or HTML module that renders svgs:

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

By default the svgs are placed in a sprite sheet called `sprites.svg`, but you
can also compile svgs to other named sheets:

```elixir
<.svg ref={sprite_ref("regular/xmark", sheet: "dashboard")} class="size-4" />
```

When `static_path_resolver` is configured, the rendered `<use href="...">`
points at the resolved sheet URL plus `#sprite-id`.
`SvgSpriteEx.sprite_sheet/1` metadata does not change: `%SpriteSheetMeta{}` and
`@sheet_meta.public_path` still carry the original unresolved `public_path`
from compile time.

### Render inline svgs

Inline mode skips the sprite sheet and renders the svg inline in the document.

```elixir
<.svg ref={inline_ref("regular/xmark")} class="size-4" />
```

This lets you serve the raw svg markup in the page instead of a `<use>`
reference, without doing runtime file reads.

If you construct inline refs manually, use `%SvgSpriteEx.InlineRef{name: "..."}`
with no `:registry` field.

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

In umbrella or multi-app code paths, runtime metadata APIs skip stale
`runtime_data.etf` files from sibling apps until those apps rebuild with the
current schema.

## Patterns

### Preload a single sprite sheet

When a layout or component knows it will use a specific sprite sheet, you can
preload it by looking up the compiled sheet metadata with `sprite_sheet/1` and
rendering a `<link rel="preload" ...>` tag.

When `static_path_resolver` is configured, make sure the preload helper calls
that same resolver before emitting the URL. Otherwise the preload `href` can
drift from the runtime `<use href="...">` request in digested setups.

In a helper or function component:

```elixir
defmodule MyAppWeb.MyComponents do
  use Phoenix.Component

  attr :sheet, :string, required: true

  def sprite_sheet_preload(assigns) do
    sheet_meta = SvgSpriteEx.sprite_sheet(assigns.sheet)

    resolved_public_path =
      case sheet_meta do
        nil -> nil
        %{public_path: public_path} -> MyAppWeb.Endpoint.static_path(public_path)
      end

    assigns =
      assigns
      |> assign(:sheet_meta, sheet_meta)
      |> assign(:resolved_public_path, resolved_public_path)

    ~H"""
    <link
      :if={@sheet_meta}
      rel="preload"
      href={@resolved_public_path}
      as="image"
      type="image/svg+xml"
    />
    """
  end
end
```

If you configured a different `static_path_resolver`, call that same resolver in
the preload helper instead of `MyAppWeb.Endpoint.static_path/1`.

Then in a layout or page template:

```elixir
<.sprite_sheet_preload sheet="dashboard" />
```
