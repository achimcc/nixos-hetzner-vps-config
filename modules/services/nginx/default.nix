{ config, pkgs, lib, commonConfig, customLib, ... }:

{
  # ============================================================================
  # NGINX REVERSE PROXY (HARDENED)
  # ============================================================================

  services.nginx = {
    enable = true;
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;

    # Increase hash bucket size for long server names (rmfakecloud domains)
    serverNamesHashBucketSize = 128;

    # ── Listener-Topologie ───────────────────────────────────────────────────
    # Port 443 wird vom stream-SNI-Preread-Block unten belegt (siehe streamConfig).
    # Alle HTTP-vhosts laufen auf 127.0.0.1:8443 mit PROXY-Protocol und bekommen
    # ihre Verbindungen ueber den stream-Layer von aussen oder ueber
    # 10.77.0.2:8443 (proxy-01 via wg-vps) weitergeleitet.
    defaultListen = [
      { addr = "0.0.0.0"; port = 8443; ssl = true; extraParameters = [ "proxy_protocol" ]; }
      { addr = "[::]";    port = 8443; ssl = true; extraParameters = [ "proxy_protocol" ]; }
      { addr = "0.0.0.0"; port = 80; }
      { addr = "[::]";    port = 80; }
    ];

    # Global security settings + PROXY-Protocol real-IP trust (nur von localhost).
    appendHttpConfig = ''
      # Rate Limiting Zones
      limit_req_zone $binary_remote_addr zone=general:10m rate=10r/s;
      limit_conn_zone $binary_remote_addr zone=addr:10m;

      # Client-IP aus dem PROXY-Header uebernehmen (gesendet vom stream-Block
      # auf localhost). Nur Verbindungen von 127.0.0.1 duerfen PROXY-Header
      # senden — alle anderen Quellen werden nicht getrustet.
      set_real_ip_from 127.0.0.1;
      set_real_ip_from ::1;
      real_ip_header proxy_protocol;
    '';

    # ── Stream-SNI-Preread auf :443 ──────────────────────────────────────────
    # Terminiert kein TLS, liest nur den SNI per ssl_preread. Home-SNIs werden
    # ueber den WG-Tunnel an proxy-01 durchgereicht, alles andere an den lokalen
    # nginx-http-Block auf :8443. Jeder Pfad bekommt einen PROXY-Protocol-Header
    # mit der Original-Client-IP.
    streamConfig = ''
      map $ssl_preread_server_name $upstream {
        ~^(auth|cloud|files|grafana|jellyfin|seerr|status|vault)\.rusty-vault\.de$  home_ingress;
        default                                                                      local_ingress;
      }

      upstream home_ingress  { server 10.77.0.2:8443; }
      upstream local_ingress { server 127.0.0.1:8443; }

      server {
        listen 443;
        listen [::]:443;
        ssl_preread on;
        proxy_pass $upstream;
        proxy_protocol on;
      }
    '';

    # Virtual Hosts - imported from vhosts.nix
    virtualHosts = import ./vhosts.nix { inherit config pkgs lib commonConfig customLib; };
  };

  # ============================================================================
  # ACME / LET'S ENCRYPT
  # ============================================================================

  security.acme = {
    acceptTerms = true;
    defaults = {
      email = commonConfig.adminEmail;
      # ECDSA certificates (modern, faster)
      keyType = "ec384";
    };
  };

  # ACME Certificate for mail subdomain
  security.acme.certs.${commonConfig.services.mail} = {
    email = commonConfig.adminEmail;
    webroot = "/var/lib/acme/acme-challenge";
    postRun = "systemctl reload postfix";
  };
}
