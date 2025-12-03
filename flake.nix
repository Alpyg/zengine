{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    zig.url = "github:Fryuni/zig-overlay";
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    flake-utils,
    ...
  }: let
    overlays = [(final: prev: {zigpkgs = inputs.zig.packages.${prev.system};})];
  in
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs {
        inherit overlays system;
        config.allowUnfree = true;
      };
    in {
      devShells.default = pkgs.mkShell {
        nativeBuildInputs = with pkgs; [
          zigpkgs."0.14.1"
          zigpkgs."0.14.0".zls

          vulkan-tools
          vulkan-headers
          vulkan-loader
          xorg.libX11
          xorg.libXcursor
          xorg.libXi
          xorg.libXrandr
          xorg.libXinerama
          libxkbcommon
          wayland
          wayland-scanner
        ];
      };

      devShell = self.devShells.${system}.default;
    });
}
