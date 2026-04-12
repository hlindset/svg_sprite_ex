# Changelog

## Unreleased

- Made compiler invalidation aware of compiler pipeline changes, so library
  upgrades rebuild stale sprite and metadata artifacts instead of silently
  reusing them.
- Replaced module scanning with persisted per-module ref snapshots written from
  the macro layer after compilation.
- Replaced generated runtime registry modules with a runtime data artifact and
  static loader modules, removing the extra generated-source compile pass.

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
