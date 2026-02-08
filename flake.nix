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
          jitsi = "jitsi.rusty-vault.de";
        };
        emailDomain = "sl.rusty-vault.de";
      };

      # Custom library functions
      customLib = import ./lib { inherit (nixpkgs) lib; inherit commonConfig pkgs; };
    in
    {
      # ========================================================================
      # NIXOS CONFIGURATIONS
      # ========================================================================

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

      # ========================================================================
      # DEPLOYMENT COMMAND
      # ========================================================================

      packages.${system} = {
        # nrs - NixOS Rebuild Switch for remote deployment
        nrs = pkgs.writeShellScriptBin "nrs" ''
          set -euo pipefail

          # Colors for output
          RED='\033[0;31m'
          GREEN='\033[0;32m'
          YELLOW='\033[1;33m'
          BLUE='\033[0;34m'
          NC='\033[0m' # No Color

          # Configuration
          SERVER="''${NRS_SERVER:-root@${commonConfig.domain}}"
          FLAKE_DIR="$(cd "$(dirname "''${BASH_SOURCE[0]}")/../.." && pwd)"
          HOSTNAME="''${NRS_HOSTNAME:-nixos-server}"

          echo -e "''${BLUE}╔════════════════════════════════════════════════════════════╗''${NC}"
          echo -e "''${BLUE}║  NixOS Flake Deployment (nrs)                            ║''${NC}"
          echo -e "''${BLUE}╚════════════════════════════════════════════════════════════╝''${NC}"
          echo ""
          echo -e "''${YELLOW}Server:''${NC}   $SERVER"
          echo -e "''${YELLOW}Flake:''${NC}    $FLAKE_DIR"
          echo -e "''${YELLOW}Host:''${NC}     $HOSTNAME"
          echo ""

          # Check for uncommitted changes
          if [[ -n $(git -C "$FLAKE_DIR" status --porcelain) ]]; then
            echo -e "''${YELLOW}⚠️  Warning: You have uncommitted changes!''${NC}"
            git -C "$FLAKE_DIR" status --short
            echo ""
            read -p "Continue anyway? (y/N) " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
              echo -e "''${RED}Deployment cancelled.''${NC}"
              exit 1
            fi
          fi

          echo -e "''${BLUE}📤 Copying flake to server...''${NC}"
          rsync -av --delete \
            --exclude='.git' \
            --exclude='.worktrees' \
            --exclude='result' \
            --exclude='*.swp' \
            --exclude='.DS_Store' \
            "$FLAKE_DIR/" "$SERVER:/etc/nixos/"

          if [ $? -eq 0 ]; then
            echo -e "''${GREEN}✅ Flake copied successfully''${NC}"
          else
            echo -e "''${RED}❌ Failed to copy flake''${NC}"
            exit 1
          fi
          echo ""

          echo -e "''${BLUE}🔧 Rebuilding NixOS configuration...''${NC}"
          ssh "$SERVER" "cd /etc/nixos && nixos-rebuild switch --flake .#$HOSTNAME"

          if [ $? -eq 0 ]; then
            echo ""
            echo -e "''${GREEN}╔════════════════════════════════════════════════════════════╗''${NC}"
            echo -e "''${GREEN}║  ✅ Deployment successful!                                ║''${NC}"
            echo -e "''${GREEN}╚════════════════════════════════════════════════════════════╝''${NC}"
            echo ""
            echo -e "''${YELLOW}Verify deployment:''${NC}"
            echo "  ssh $SERVER systemctl is-failed '*' | grep -v not-found"
            echo "  ssh $SERVER podman ps"
          else
            echo ""
            echo -e "''${RED}╔════════════════════════════════════════════════════════════╗''${NC}"
            echo -e "''${RED}║  ❌ Deployment failed!                                    ║''${NC}"
            echo -e "''${RED}╚════════════════════════════════════════════════════════════╝''${NC}"
            exit 1
          fi
        '';

        default = self.packages.${system}.nrs;
      };

      # App for easier invocation with `nix run`
      apps.${system} = {
        nrs = {
          type = "app";
          program = "${self.packages.${system}.nrs}/bin/nrs";
        };
        default = self.apps.${system}.nrs;
      };
    };
}
