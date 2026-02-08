{ config, pkgs, lib, ... }:

{
  # ============================================================================
  # NETWORK CONFIGURATION
  # ============================================================================

  networking.hostName = "nixos-server";

  # IPv6 Configuration for Hetzner
  networking.interfaces.enp1s0 = {
    ipv6.addresses = [{
      address = "2a01:4f9:c013:5ee7::1";
      prefixLength = 64;
    }];
  };
  networking.defaultGateway6 = {
    address = "fe80::1";
    interface = "enp1s0";
  };
}
