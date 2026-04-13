# Changelog

## Unreleased

- Replaced generated runtime registry modules with a runtime data artifact and
  static loader modules, removing the extra generated-source compile pass.
- Persisted per-module ref snapshots from the macro layer after compilation and
  made the compiler fail fast on missing or outdated snapshots instead of
  bootstrapping legacy state. Upgrading now requires a clean rebuild.
- Made compiler invalidation aware of compiler pipeline changes, so library
  upgrades rebuild stale sprite sheets and runtime metadata artifacts instead of
  silently reusing them.
- Changed `%SvgSpriteEx.InlineRef{}` to a one-field struct containing only
  `:name`.
- Updated runtime metadata loading to ignore stale sibling `runtime_data.etf`
  files on the code path until those apps rebuild with the current schema.

## 0.2.0 - 2026-03-25

- Added a runtime metadata API for compiled sprite sheets, sprites, and inline
  SVGs through `SvgSpriteEx`.
- Reworked compiler change tracking so SVG asset updates are detected and
  rebuilt correctly in the after-Elixir compiler pipeline.

## 0.1.0 - 2026-03-24

- Initial public release of SvgSpriteEx.
- Compile-time `sprite_ref/1`, `sprite_ref/2`, and `inline_ref/1` helpers for
  Phoenix components and LiveView.
- SvgSpriteEx Mix compiler support for generating sprite sheets and inline SVG
  lookup modules during `mix compile`.
- `<.svg>` component for rendering sprite-backed or inline SVG output.
