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
      overlays.default = final: pkgs: rec {
        helm-with-plugins = pkgs.wrapHelm pkgs.kubernetes-helm {
          # https://search.nixos.org/packages?channel=unstable&from=0&size=50&sort=relevance&type=packages&query=kubernetes-helmPlugins
          plugins = with pkgs.kubernetes-helmPlugins; [
            helm-diff
          ];
        };

        helmfile-with-plugins = pkgs.helmfile-wrapped.override { inherit (helm-with-plugins) pluginsDir; };

        gdk = pkgs.google-cloud-sdk.withExtraComponents (
          with pkgs.google-cloud-sdk.components;
          [
            gke-gcloud-auth-plugin
          ]
        );

        pipelines-image = pkgs.callPackage ./pipelines_image.nix { };
      };

      flake = flake-utils.lib.eachDefaultSystem (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
            overlays = [ self.overlays.default ];
          };

          linuxPkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
            overlays = [ self.overlays.default ];
            crossSystem = "x86_64-linux";
          };
        in
        {
          packages = {
            default = linuxPkgs.pipelines-image;
          };

          apps = {
            deploy = flake-utils.lib.mkApp { drv = pkgs.callPackage ./deploy.nix { }; };
          };

          devShells.default =
            with pkgs;
            mkShellNoCC {
              packages = [
                (python3.withPackages (
                  ps: with ps; [
                    jedi-language-server
                    python-lsp-server
                  ]
                ))
                ruff
                helm-with-plugins
                helmfile-with-plugins
                gdk
              ];
            };

          formatter = pkgs.nixfmt-rfc-style;
        }
      );

    in
    flake // { inherit overlays; };
}
