{ config, pkgs, lib, commonConfig, ... }:

{
  # ============================================================================
  # SYNCTHING RELAY SERVER
  # ============================================================================

  services.syncthing.relay = {
    enable = true;

    # Relay settings
    listenAddress = "0.0.0.0";
    port = 22067;
    statusListenAddress = "127.0.0.1";
    statusPort = 22070;

    # Pool settings (register publicly in Syncthing pool)
    pools = [ "https://relays.syncthing.net/endpoint" ];

    # Bandwidth limits (null = unlimited)
    globalRateBps = null;
    perSessionRateBps = null;

    # Identification
    providedBy = commonConfig.domain;
  };
}
