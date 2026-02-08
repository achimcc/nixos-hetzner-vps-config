{ config, pkgs, lib, ... }:

{
  # ============================================================================
  # BASE SYSTEM PACKAGES
  # ============================================================================

  environment.systemPackages = with pkgs; [
    vim
    git
    htop
    wget
  ];
}
