{pkgs, ...}: let
  libs = with pkgs; [
    wayland
    vulkan-loader
    vulkan-headers
    stdenv.cc.cc.lib
    libxkbcommon
    libX11
    sdl3
  ];
in {
  packages = with pkgs;
    [
      pkg-config
      vulkan-tools
      stdenv.cc
    ]
    ++ libs;

  languages.zig = {
    enable = true;
    package = pkgs.zig;
  };
  env = {
    LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath libs;
  };
}
