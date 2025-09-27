{
  description = "Talos Manager Development Environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/8bffdd4ccfc94eedd84b56d346adb9fac46b5ff6";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = import ./shell.nix { inherit pkgs; };
      });
}