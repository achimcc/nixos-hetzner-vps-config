{ config, pkgs, lib, commonConfig, customLib, ... }:

{
  # ============================================================================
  # MAIN DOMAIN (rusty-vault.de)
  # ============================================================================

  ${commonConfig.domain} = {
    enableACME = true;
    forceSSL = true;

    # ACME Challenge without rate limiting
    locations."/.well-known/acme-challenge" = {
      root = "/var/lib/acme/acme-challenge";
      extraConfig = ''
        auth_basic off;
      '';
    };

    # Security Headers & Rate Limiting
    extraConfig = ''
      ${customLib.nginxRateLimiting}
      ${customLib.nginxSecurityHeaders}
    '';

    # Vaultwarden (main page)
    locations."/" = {
      proxyPass = "http://127.0.0.1:8222";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_hide_header X-Powered-By;
        proxy_hide_header Server;
      '';
    };

    # Admin Panel with strict rate limiting
    locations."/admin" = {
      proxyPass = "http://127.0.0.1:8222";
      extraConfig = ''
        ${customLib.nginxRateLimitingStrict}
        proxy_hide_header X-Powered-By;
        proxy_hide_header Server;
      '';
    };

    # Syncthing Relay Status
    locations."/relay-status" = {
      proxyPass = "http://127.0.0.1:22070/status";
      extraConfig = ''
        proxy_hide_header X-Powered-By;
        proxy_hide_header Server;
      '';
    };

    # Miniflux RSS Reader
    locations."/miniflux/" = {
      proxyPass = "http://127.0.0.1:8080/miniflux/";
      extraConfig = ''
        proxy_hide_header X-Powered-By;
        proxy_hide_header Server;
      '';
    };
  };

  # ============================================================================
  # GHOSTFOLIO
  # ============================================================================

  ${commonConfig.services.ghostfolio} = {
    enableACME = true;
    forceSSL = true;

    extraConfig = customLib.nginxSecurityHeaders;

    locations."/" = {
      proxyPass = "http://127.0.0.1:3333";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_hide_header X-Powered-By;
        proxy_hide_header Server;
      '';
    };
  };

  # ============================================================================
  # PRIVATEBIN
  # ============================================================================

  ${commonConfig.services.privatebin} = {
    enableACME = true;
    forceSSL = true;
    serverAliases = [ "pastebin.${commonConfig.domain}" ];

    extraConfig = ''
      # Rate Limiting (relaxed burst for initial JS load)
      limit_req zone=general burst=30 nodelay;
      limit_conn addr 10;

      ${customLib.nginxSecurityHeaders}

      # PrivateBin sets its own CSP headers - don't override them

      # Upload size limit
      client_max_body_size 10M;
    '';
  };

  # ============================================================================
  # SIMPLELOGIN
  # ============================================================================

  ${commonConfig.services.simplelogin} = {
    enableACME = true;
    forceSSL = true;

    extraConfig = ''
      ${customLib.nginxRateLimiting}

      # WORKAROUND: Fix malformed redirects with duplicate hostname
      # Rewrite URLs like "simplelogin.rusty-vault.de,simplelogin.rusty-vault.de/path" to "/path"
      if ($request_uri ~ "^/${commonConfig.services.simplelogin},${commonConfig.services.simplelogin}(.*)$") {
        return 301 https://${commonConfig.services.simplelogin}$1;
      }

      ${customLib.nginxSecurityHeaders}

      # Upload size limit for email attachments
      client_max_body_size 25M;
    '';

    locations."/" = {
      proxyPass = "http://127.0.0.1:7777";
      extraConfig = ''
        # Override X-Forwarded-Proto to ensure HTTPS is used
        proxy_set_header X-Forwarded-Proto $scheme;

        # Rewrite Location header from http to https for this hostname only
        proxy_redirect ~^http://([^/]+)(.*)$ https://$1$2;
      '';
    };
  };
}
