import Config

config :svg_sprite_ex,
  source_root: Path.expand("../../icons", __DIR__),
  build_path: Path.join(Mix.Project.app_path(), "priv/static/assets/sprites"),
  public_path: "/assets/sprites"
