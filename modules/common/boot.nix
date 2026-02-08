{ config, pkgs, lib, ... }:

{
  # ============================================================================
  # BOOTLOADER & INITRD CONFIGURATION
  # ============================================================================

  # GRUB Bootloader
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/sda";

  # Remote Unlock (SSH during boot)
  boot.initrd.network = {
    enable = true;
    ssh = {
      enable = true;
      port = 22;
      authorizedKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIC7i5Y0mgk0vYZRypv6lbM4AnuY1IrCLKrSwoFbB8Y2C achim@hetzner-vps"
      ];
      hostKeys = [ "/etc/secrets/initrd/ssh_host_ed25519_key" ];
    };
  };

  boot.initrd.availableKernelModules = [ "virtio_net" "virtio_pci" ];
}
