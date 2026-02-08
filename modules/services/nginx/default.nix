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

    # Global security settings
    appendHttpConfig = ''
      # Rate Limiting Zones
      limit_req_zone $binary_remote_addr zone=general:10m rate=10r/s;
      limit_conn_zone $binary_remote_addr zone=addr:10m;
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
