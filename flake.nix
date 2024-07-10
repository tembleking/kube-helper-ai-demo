{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    poetry2nix-flake.url = "github:nix-community/poetry2nix";
    utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    poetry2nix-flake,
    utils,
  }:
    utils.lib.eachDefaultSystem (
      system: let
        pythonVersion = pkgs.python3; # <- Your python version here, in case you want a different one. For example, one of: python3, python310, python311, python312, etc

        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
          overlays = [poetry2nix-flake.overlays.default];
        };
      in {
        devShells.default = with pkgs; mkShellNoCC {
          packages = [
            (poetry2nix.mkPoetryEnv {
              projectDir = self;
              python = python3;
            })
            poetry
          ];
        };

        formatter = pkgs.alejandra;
      }
    );
}
