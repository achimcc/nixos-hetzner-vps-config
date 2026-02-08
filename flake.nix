{
  description = "NixOS server configuration for rusty-vault.de";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, sops-nix, ... }@inputs:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      # Common configuration shared across modules
      commonConfig = {
        domain = "rusty-vault.de";
        adminEmail = "achim.schneider@posteo.de";
        services = {
          vaultwarden = "rusty-vault.de";
          ghostfolio = "ghostfolio.rusty-vault.de";
          privatebin = "privatebin.rusty-vault.de";
          simplelogin = "simplelogin.rusty-vault.de";
          mail = "mail.rusty-vault.de";
        };
        emailDomain = "sl.rusty-vault.de";
      };

      # Custom library functions
      customLib = import ./lib { inherit (nixpkgs) lib; inherit commonConfig pkgs; };
    in
    {
      nixosConfigurations.nixos-server = nixpkgs.lib.nixosSystem {
        inherit system;

        specialArgs = {
          inherit inputs commonConfig customLib;
        };

        modules = [
          ./configuration.nix
          sops-nix.nixosModules.sops
        ];
      };
    };
}
