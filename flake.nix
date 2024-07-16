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

        helm_with_plugins = with pkgs;
          wrapHelm kubernetes-helm {
            # https://search.nixos.org/packages?channel=unstable&from=0&size=50&sort=relevance&type=packages&query=kubernetes-helmPlugins
            plugins = with kubernetes-helmPlugins; [
              helm-diff # Required for `helm diff` and `helmfile apply`
            ];
          };
        helmfile_with_plugins = pkgs.helmfile-wrapped.override {
          inherit (helm_with_plugins) pluginsDir;
        };

        pipelines_image = pkgs.callPackage ./pipelines_image.nix {};
      in {
        packages = {
          miner = pkgs.callPackage ./miner_image.nix {};
          default = pipelines_image;
        };
        devShells.default = with pkgs;
          mkShellNoCC {
            packages = [
              (poetry2nix.mkPoetryEnv {
                projectDir = self;
                python = python3;
              })
              poetry
              helm_with_plugins
              helmfile_with_plugins
            ];
          };

        formatter = pkgs.alejandra;
      }
    );
}
