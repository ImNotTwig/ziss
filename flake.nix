{
  outputs = { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in 
    {
      devShells.${system}.default =
        pkgs.mkShell { 
          packages = [
            pkgs.zig
            pkgs.zls
            pkgs.age
          ];
        };
    };
}
