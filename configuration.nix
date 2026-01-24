{ config, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

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

  # Diese Version nicht ändern (definiert Kompatibilität)
  system.stateVersion = "25.05"; 
}
