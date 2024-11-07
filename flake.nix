{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    let
      flake = flake-utils.lib.eachDefaultSystem (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
            crossSystem = "x86_64-linux";
          };

          helm_with_plugins =
            with pkgs;
            wrapHelm kubernetes-helm {
              # https://search.nixos.org/packages?channel=unstable&from=0&size=50&sort=relevance&type=packages&query=kubernetes-helmPlugins
              plugins = with kubernetes-helmPlugins; [
                helm-diff # Required for `helm diff` and `helmfile apply`
              ];
            };
          helmfile_with_plugins = pkgs.helmfile-wrapped.override { inherit (helm_with_plugins) pluginsDir; };

          pipelines_image = pkgs.callPackage ./pipelines_image.nix { };

        in
        {
          packages = {
            miner = pkgs.callPackage ./miner_image.nix { };
            default = pipelines_image;
          };

          apps = {
            deploy = flake-utils.lib.mkApp {
              drv = pkgs.writeShellApplication {
                name = "deploy";
                runtimeInputs = [
                  helmfile_with_plugins
                  helm_with_plugins
                ];
                text = ''
                  helmfile apply -f ${./helmfile.yaml}
                '';
              };
            };
          };

          devShells.default = pkgs.mkShellNoCC {
            packages = [
              (pkgs.python3.withPackages (
                ps: with ps; [
                  jedi-language-server
                  python-lsp-server
                ]
              ))
              pkgs.ruff
              helm_with_plugins
              helmfile_with_plugins
            ];
          };

          formatter = pkgs.nixpkgs-rfc-style;
        }
      );

    in
    flake;
}
