{
  inputs = {
    zls.url = "github:zigtools/zls";
    zig-overlay.url = "github:mitchellh/zig-overlay";
  };
  outputs = { zls, zig-overlay, nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in 
    {
      devShells.${system}.default =
        pkgs.mkShell { 
          packages = [
            pkgs.age
            zig-overlay.packages.${system}.master
            zls.packages.${system}.zls
          ];
        };
    };
}
