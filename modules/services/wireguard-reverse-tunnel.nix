{ config, pkgs, lib, ... }:

{
  # ============================================================================
  # WIREGUARD REVERSE TUNNEL (VPS ↔ proxy-01)
  # ============================================================================
  # VPS ist Server (stabile IPv4), proxy-01 ist Client (hinter CGNAT → dialt raus).
  # Zweck: IPv4-Ingress für Homeserver-Subdomains via SNI-Routing (Phase 2+).
  # Subnetz 10.77.0.0/30: VPS = .1, proxy-01 = .2.
  # (10.88.0.0/16 ist bereits durch podman0 belegt.)

  networking.wireguard.interfaces.wg-proxmox = {
    ips = [ "10.77.0.1/30" ];
    listenPort = 51820;
    privateKeyFile = config.sops.secrets.wg_reverse_tunnel_private_key.path;

    peers = [
      {
        # proxy-01 (Homeserver VM, VLAN 30)
        publicKey = "uXLqqEp35ekuFgl3XqgKfCqFPKZOJny20Qd04hM530k=";
        allowedIPs = [ "10.77.0.2/32" ];
      }
    ];
  };

  networking.firewall.allowedUDPPorts = [ 51820 ];
}
