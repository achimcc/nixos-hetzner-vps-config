{ config, pkgs, lib, inputs, commonConfig, customLib, ... }:

{
  imports = [
    # Hardware
    ./hardware-configuration.nix

    # Common modules
    ./modules/common/security-hardening.nix
    ./modules/common/users.nix
    ./modules/common/networking.nix
    ./modules/common/boot.nix
    ./modules/common/base-packages.nix
    ./modules/common/ssh.nix
    ./modules/common/firewall.nix

    # Secrets
    ./modules/secrets.nix

    # Services
    ./modules/services/nginx/default.nix
    ./modules/services/vaultwarden.nix
    ./modules/services/miniflux.nix
    ./modules/services/privatebin.nix
    ./modules/services/syncthing-relay.nix
    ./modules/services/veilid.nix
    ./modules/services/jitsi.nix
    ./modules/services/mail/postfix.nix
    ./modules/services/monitoring/fail2ban.nix

    # Containers
    ./modules/services/containers/podman.nix
    # ./modules/services/containers/ghostfolio.nix  # Temporarily disabled - placeholder secrets
    ./modules/services/containers/simplelogin.nix
  ];

  # Host-specific settings
  networking.hostName = "nixos-server";
  system.stateVersion = "25.05";
}
