{ config, pkgs, lib, commonConfig, customLib, ... }:

let
  rmfakecloudPort = "3000";

  # All reMarkable domains that the tablet/apps connect to
  remarkableDomains = [
    "hwr-production-dot-remarkable-production.appspot.com"
    "service-manager-production-dot-remarkable-production.appspot.com"
    "local.appspot.com"
    "my.remarkable.com"
    "ping.remarkable.com"
    "internal.cloud.remarkable.com"
    "webapp-prod.cloud.remarkable.engineering"
    "eu.tectonic.remarkable.com"
  ];
in
{
  # ============================================================================
  # RMFAKECLOUD (PODMAN CONTAINER)
  # ============================================================================

  # Persistent data directory (Cert-Permissions managed by sops-nix)
  systemd.tmpfiles.rules = [
    "d /var/lib/rmfakecloud 0750 root root -"
    "d /var/lib/rmfakecloud/data 0750 root root -"
  ];

  # OCI Container
  virtualisation.oci-containers.containers.rmfakecloud = {
    image = "docker.io/ddvk/rmfakecloud:latest";
    ports = [ "127.0.0.1:${rmfakecloudPort}:3000" ];
    volumes = [
      "/var/lib/rmfakecloud/data:/data"
    ];
    environment = {
      STORAGE_URL = "https://local.appspot.com";
      DATADIR = "/data";
      LOGLEVEL = "info";
      RM_HTTPS_COOKIE = "true";
      RM_TRUST_PROXY = "true";
    };
    environmentFiles = [
      config.sops.secrets.rmfakecloud_jwt_secret.path
    ];
    extraOptions = [
      "--cap-drop=ALL"
      "--cap-add=SETGID"
      "--cap-add=SETUID"
      "--security-opt=no-new-privileges:true"
    ];
  };

  # ============================================================================
  # NGINX VIRTUAL HOSTS
  # ============================================================================

  services.nginx.virtualHosts = {
    # ------------------------------------------------------------------
    # Web UI: remarkable.rusty-vault.de (Let's Encrypt)
    # ------------------------------------------------------------------
    ${commonConfig.services.remarkable} = {
      enableACME = true;
      forceSSL = true;

      extraConfig = ''
        ${customLib.nginxRateLimiting}
        ${customLib.nginxSecurityHeaders}
        client_max_body_size 1G;
      '';

      locations."/" = {
        proxyPass = "http://127.0.0.1:${rmfakecloudPort}";
        proxyWebsockets = true;
        extraConfig = ''
          proxy_read_timeout 10800;
          proxy_send_timeout 10800;
          proxy_hide_header X-Powered-By;
          proxy_hide_header Server;
        '';
      };
    };

    # ------------------------------------------------------------------
    # reMarkable device domains (Self-Signed CA Certificate)
    # ------------------------------------------------------------------
    "remarkable-device-api" = {
      serverName = builtins.head remarkableDomains;
      serverAliases = builtins.tail remarkableDomains;

      addSSL = true;
      sslCertificate    = config.sops.secrets."rmfakecloud-ca/server.crt".path;
      sslCertificateKey = config.sops.secrets."rmfakecloud-ca/server.key".path;

      extraConfig = ''
        client_max_body_size 1G;
        proxy_read_timeout 10800;
        proxy_send_timeout 10800;
      '';

      locations."/" = {
        proxyPass = "http://127.0.0.1:${rmfakecloudPort}";
        proxyWebsockets = true;
        extraConfig = ''
          proxy_hide_header X-Powered-By;
          proxy_hide_header Server;
        '';
      };
    };
  };
}
