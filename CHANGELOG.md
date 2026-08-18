# Changelog

## Unreleased

- Replaced generated runtime registry modules with a runtime data artifact and
  static loader modules, removing the extra generated-source compile pass.
- Collects macro refs directly from compiled module exports without persisting
  a separate per-module snapshot subsystem.
- Made compiler invalidation aware of compiler pipeline changes, so library
  upgrades rebuild stale sprite sheets and runtime metadata artifacts instead of
  silently reusing them.
- Changed `%SvgSpriteEx.InlineRef{}` to a one-field struct containing only
  `:name`.
- Removed `:href` from `%SvgSpriteEx.SpriteRef{}` and
  `%SvgSpriteEx.SpriteMeta{}`. Refs now carry `:sheet_public_path` and
  `:sprite_id`, which renderers resolve at render time.
- Automatically migrates the legacy compiler manifest and removes obsolete
  generated artifacts during normal `mix compile` upgrades.
- Runtime metadata loading fails fast when it encounters a stale sibling
  `runtime_data.etf` on the code path, identifies its artifact path, and
  requires rebuilding the app or dependency that produced it.

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
