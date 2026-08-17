import Config

config :svg_sprite_ex,
  source_root: Path.expand("../../icons", __DIR__),
  build_path: Path.join(System.tmp_dir!(), "svg_sprite_ex_adapter_consumer/sprites"),
  public_path: "/assets/sprites"
