{ config, pkgs, lib, ... }:

{
  # ============================================================================
  # USER MANAGEMENT & HARDENING
  # ============================================================================

  # Admin user (separate from root)
  users.users.admin = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIC7i5Y0mgk0vYZRypv6lbM4AnuY1IrCLKrSwoFbB8Y2C achim@hetzner-vps"
    ];
  };

  # Root SSH keys for emergency/initrd access
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIC7i5Y0mgk0vYZRypv6lbM4AnuY1IrCLKrSwoFbB8Y2C achim@hetzner-vps"
  ];

  # Sudo configuration
  security.sudo = {
    enable = true;
    wheelNeedsPassword = false;  # Key-only SSH makes this reasonable
    execWheelOnly = true;
  };

  # Protect password hashes
  users.mutableUsers = false;
}
