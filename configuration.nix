{ config, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      # sops-nix fuer verschluesselte Secrets
      (builtins.fetchTarball {
        url = "https://github.com/Mic92/sops-nix/archive/master.tar.gz";
        # Optional: Pin auf eine spezifische Version fuer Reproduzierbarkeit
        # sha256 = "...";
      } + "/modules/sops")
    ];

  # --- SOPS Konfiguration ---
  sops = {
    defaultSopsFile = ./secrets/secrets.yaml;
    age.keyFile = "/var/lib/sops-nix/key.txt";
    secrets.smtp_password = {};
  };

  # --- 1. BOOTLOADER ---
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/sda";
  # Falls es Probleme gibt, erzwinge die Installation:
  # boot.loader.grub.forceInstall = true;

  # --- 2. REMOTE UNLOCK (SSH beim Booten) ---
  boot.initrd.network = {
    enable = true;
    ssh = {
      enable = true;
      port = 22;
      # !!! WICHTIG: Füge hier deinen echten Public Key ein !!!
      authorizedKeys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIC7i5Y0mgk0vYZRypv6lbM4AnuY1IrCLKrSwoFbB8Y2C achim@hetzner-vps" ];

      # Habe ich auskommentiert, da diese Datei bei der Installation oft noch fehlt.
      # NixOS generiert temporäre Keys für den Boot-Vorgang.
      # hostKeys = [ "/etc/secrets/initrd/ssh_host_ed25519_key" ];
hostKeys = [ "/etc/secrets/initrd/ssh_host_ed25519_key" ];
    };
  };

  # Treiber für Hetzner Netzwerkkarte laden, damit SSH beim Booten geht
  boot.initrd.availableKernelModules = [ "virtio_net" "virtio_pci" ];

  # --- 3. SYSTEM EINSTELLUNGEN ---
  networking.hostName = "nixos-server"; # Du kannst den Namen ändern

  # SSH für das laufende System
  services.openssh.enable = true;
  users.users.root.openssh.authorizedKeys.keys = [
    # !!! WICHTIG: Auch hier deinen echten Public Key einfügen !!!
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIC7i5Y0mgk0vYZRypv6lbM4AnuY1IrCLKrSwoFbB8Y2C achim@hetzner-vps"
  ];

  # Nützliche Standard-Pakete (damit du Editoren hast)
  environment.systemPackages = with pkgs; [
    vim
    git
    htop
    wget
  ];

  # --- 4. VAULTWARDEN ---
  services.vaultwarden = {
    enable = true;
    environmentFile = config.sops.secrets.smtp_password.path;
    config = {
      DOMAIN = "https://rusty-vault.de";
      SIGNUPS_ALLOWED = false;  # Nach erstem Account auf false setzen!
      ROCKET_ADDRESS = "127.0.0.1";
      ROCKET_PORT = 8222;
      ADMIN_TOKEN = "$argon2id$v=19$m=65540,t=3,p=4$I0fPqJOynHKXxBUj5iur0ZMigOS806LGRgYwpg9euvc$SVRz1fv4YdoOoFYOI72d+UIbZElt9XVF9d6LNomZ2lw";

      # SMTP fuer Posteo
      SMTP_HOST = "posteo.de";
      SMTP_PORT = 587;
      SMTP_SECURITY = "starttls";
      SMTP_FROM = "achim.schneider@posteo.de";
      SMTP_USERNAME = "achim.schneider@posteo.de";
      # SMTP_PASSWORD kommt aus environmentFile
    };
  };

  # --- 5. NGINX REVERSE PROXY ---
  services.nginx = {
    enable = true;
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;

    virtualHosts."rusty-vault.de" = {
      enableACME = true;
      forceSSL = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:8222";
        proxyWebsockets = true;
      };
    };
  };

  # --- 6. ACME / LET'S ENCRYPT ---
  security.acme = {
    acceptTerms = true;
    defaults.email = "achim.schneider@posteo.de";
  };

  # --- 7. FIREWALL ---
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 80 443 ];
  };

  # Diese Version nicht ändern (definiert Kompatibilität)
  system.stateVersion = "25.05";
}
