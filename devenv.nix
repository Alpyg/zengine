{
  pkgs,
  lib,
  config,
  inputs,
  ...
}:
let
  libs = with pkgs; [
    wayland
    vulkan-loader
    libxkbcommon
    libX11
  ];
in
{
  packages =
    with pkgs;
    [
      pkg-config
      vulkan-tools
    ]
    ++ libs;

  languages.zig = {
    enable = true;
    package = pkgs.zig_0_15;
  };
}
