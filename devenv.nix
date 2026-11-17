{pkgs, ...}: let
  libs = with pkgs; [
    wayland
    vulkan-loader
    vulkan-headers
    libxkbcommon
    libX11
    libGL
    sdl3
  ];
in {
  packages = with pkgs;
    [
      pkg-config
      vulkan-tools
      glslang
    ]
    ++ libs;

  languages.zig = {
    enable = true;
    package = pkgs.zig;
  };
  env = {
    C_INCLUDE_PATH = "${pkgs.libGL}/include";
    CPLUS_INCLUDE_PATH = "${pkgs.libGL}/include";
    VULKAN_SDK = "${pkgs.vulkan-headers}";
  };
}
