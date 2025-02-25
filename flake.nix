{
  description = "NixOS configuration of our builders";

  nixConfig.extra-substituters = [
    "https://nix-community.cachix.org"
    "https://nixpkgs-update.cachix.org"
  ];
  nixConfig.extra-trusted-public-keys = [
    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    "nixpkgs-update.cachix.org-1:6y6Z2JdoL3APdu6/+Iy8eZX2ajf09e4EE9SnxSML1W8="
  ];

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable-small";
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";
    nix-darwin.url = "github:LnL7/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
    sops-nix.inputs.nixpkgs-stable.follows = "";
    srvos.url = "github:numtide/srvos";
    # actually not used when using the modules but than nothing ever will try to fetch this nixpkgs variant
    srvos.inputs.nixpkgs.follows = "nixpkgs";

    nixpkgs-update.url = "github:ryantm/nixpkgs-update/074e47e7a813312c758f8f121d82041d312b9413";
    nixpkgs-update.inputs.mmdoc.follows = "";
    nixpkgs-update-github-releases.url = "github:ryantm/nixpkgs-update-github-releases";
    nixpkgs-update-github-releases.flake = false;

    nur-update.url = "github:nix-community/nur-update";
    nur-update.inputs.nixpkgs.follows = "nixpkgs";

    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    hercules-ci-effects.url = "github:hercules-ci/hercules-ci-effects";
    hercules-ci-effects.inputs.flake-parts.follows = "flake-parts";
    hercules-ci-effects.inputs.hercules-ci-agent.follows = "";
    hercules-ci-effects.inputs.nixpkgs.follows = "nixpkgs";

    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";

    tf-pkgs.url = "github:NixOS/nixpkgs/5cc930fbdf3e069df2efc5de6dd728a9f13e9ba9";
  };

  outputs = inputs @ { flake-parts, self, ... }:
    flake-parts.lib.mkFlake
      { inherit inputs; }
      {
        systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];

        herculesCI = { lib, ... }: {
          ciSystems = [ "x86_64-linux" "aarch64-linux" ];
          onPush.default.outputs = {
            checks = lib.mkForce self.outputs.checks.x86_64-linux;
          };
        };

        hercules-ci.flake-update = {
          enable = true;
          createPullRequest = true;
          autoMergeMethod = "rebase";
          when = {
            hour = [ 2 ];
            dayOfWeek = [ "Mon" "Thu" ];
          };
        };

        imports = [
          inputs.hercules-ci-effects.flakeModule
          inputs.treefmt-nix.flakeModule
          ./dev/effect.nix
        ];

        hercules-ci.github-pages.branch = "master";

        perSystem = { config, pkgs, ... }: {
          imports = [ ./dev/shell.nix ./terraform/shell.nix ];
          treefmt.imports = [ ./dev/treefmt.nix ];

          checks = pkgs.lib.optionalAttrs (pkgs.stdenv.hostPlatform.system == "x86_64-linux") {
            nixosTests-hydra = pkgs.nixosTests.hydra.hydra_unstable;
            nixosTests-lemmy = pkgs.nixosTests.lemmy;
            nixosTests-pict-rs = pkgs.nixosTests.pict-rs;
          };

          hercules-ci.github-pages.settings.contents = pkgs.runCommand "pages"
            {
              buildInputs = [ config.devShells.mkdocs.nativeBuildInputs ];
            } ''
            cd ${self}
            mkdocs build --strict --site-dir $out
          '';
        };

        flake.darwinConfigurations =
          let
            inherit (self.lib) darwinSystem;
          in
          {
            darwin02 = darwinSystem {
              system = "aarch64-darwin";
              modules = [ ./hosts/darwin02/configuration.nix ];
            };
            darwin03 = darwinSystem {
              system = "aarch64-darwin";
              modules = [ ./hosts/darwin03/configuration.nix ];
            };
          };

        flake.nixosConfigurations =
          let
            inherit (self.lib) nixosSystem;
          in
          {
            build01 = nixosSystem {
              system = "x86_64-linux";
              modules = [ ./hosts/build01/configuration.nix ];
            };
            build02 = nixosSystem {
              system = "x86_64-linux";
              modules = [ ./hosts/build02/configuration.nix ];
            };
            build03 = nixosSystem {
              system = "x86_64-linux";
              modules = [ ./hosts/build03/configuration.nix ];
            };
            build04 = nixosSystem {
              system = "aarch64-linux";
              modules = [ ./hosts/build04/configuration.nix ];
            };
            web01 = nixosSystem {
              system = "x86_64-linux";
              modules = [ ./hosts/web01/configuration.nix ];
            };
            web02 = nixosSystem {
              system = "x86_64-linux";
              modules = [ ./hosts/web02/configuration.nix ];
            };
          };

        flake.darwinModules = {
          common = ./modules/darwin/common;

          builder = ./modules/darwin/builder.nix;
          hercules-ci = ./modules/darwin/hercules-ci;
          remote-builder = ./modules/darwin/remote-builder.nix;
        };

        flake.nixosModules = {
          common = ./modules/nixos/common;

          builder = ./modules/nixos/builder.nix;
          cachix-deploy = ./modules/nixos/cachix-deploy;
          community-builder = ./modules/nixos/community-builder;
          github-org-backup = ./modules/nixos/github-org-backup.nix;
          hercules-ci = ./modules/nixos/hercules-ci;
          hydra = ./modules/nixos/hydra.nix;
          monitoring = ./modules/nixos/monitoring;
          nur-update = ./modules/nixos/nur-update.nix;
          remote-builder = ./modules/nixos/remote-builder/default.nix;
          remote-builder-build04 = ./modules/nixos/remote-builder/build04.nix;
          remote-builder-darwin02 = ./modules/nixos/remote-builder/darwin02.nix;
          remote-builder-darwin03 = ./modules/nixos/remote-builder/darwin03.nix;
          watch-store = ./modules/nixos/cachix/watch-store.nix;
          zfs = ./modules/nixos/zfs.nix;
        };

        flake.lib.darwinSystem = args:
          inputs.nix-darwin.lib.darwinSystem ({ specialArgs = { inherit inputs; }; } // args);
        flake.lib.nixosSystem = args:
          inputs.nixpkgs.lib.nixosSystem ({ specialArgs = { inherit inputs; }; } // args);
      };
}
