{ config, pkgs, lib, ... }:

{
  # ============================================================================
  # FIREWALL (HARDENED)
  # ============================================================================

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      22      # SSH
      25      # SMTP for SimpleLogin incoming emails
      80      # HTTP
      443     # HTTPS
      22067   # Syncthing Relay
    ];

    # ICMP Rate Limiting
    extraCommands = ''
      # Protection against SYN-Flood
      iptables -A INPUT -p tcp --syn -m limit --limit 1/s --limit-burst 3 -j ACCEPT

      # Ping Rate Limiting
      iptables -A INPUT -p icmp --icmp-type echo-request -m limit --limit 1/s --limit-burst 4 -j ACCEPT
    '';

    # Remove rules on stop
    extraStopCommands = ''
      iptables -D INPUT -p tcp --syn -m limit --limit 1/s --limit-burst 3 -j ACCEPT 2>/dev/null || true
      iptables -D INPUT -p icmp --icmp-type echo-request -m limit --limit 1/s --limit-burst 4 -j ACCEPT 2>/dev/null || true
    '';

    # Logging for rejected packets
    logRefusedConnections = true;
    logRefusedPackets = true;
  };
}
