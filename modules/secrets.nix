{ config, pkgs, ... }:

{
  # ============================================================================
  # SOPS SECRET MANAGEMENT
  # ============================================================================

  sops = {
    defaultSopsFile = ../secrets/secrets.yaml;
    age.keyFile = "/var/lib/sops-nix/key.txt";

    # Miniflux Admin Credentials
    secrets.miniflux_admin = {
      mode = "0400";
    };

    # Vaultwarden Environment Variables
    secrets.vaultwarden_env = {
      sopsFile = ../secrets/vaultwarden.yaml;
      mode = "0400";
    };

    # Ghostfolio Environment Variables
    secrets.ghostfolio_env = {
      sopsFile = ../secrets/ghostfolio.yaml;
      mode = "0400";
    };

    # SimpleLogin Secrets
    secrets.simplelogin_db_password = {
      sopsFile = ../secrets/simplelogin.yaml;
      mode = "0400";
    };

    secrets.simplelogin_db_uri = {
      sopsFile = ../secrets/simplelogin.yaml;
      mode = "0400";
    };

    secrets.simplelogin_flask_secret = {
      sopsFile = ../secrets/simplelogin.yaml;
      mode = "0400";
    };

    secrets.simplelogin_email_secret = {
      sopsFile = ../secrets/simplelogin.yaml;
      mode = "0400";
    };

    # Brevo SMTP Credentials (used by Postfix for relay)
    secrets.brevo_smtp_username = {
      sopsFile = ../secrets/simplelogin.yaml;
      mode = "0400";
    };

    secrets.brevo_smtp_password = {
      sopsFile = ../secrets/simplelogin.yaml;
      mode = "0400";
    };

    # Jitsi Meet Moderator Credentials
    secrets.jitsi_moderator_password = {
      sopsFile = ../secrets/jitsi.yaml;
      mode = "0400";
      owner = "prosody";
      group = "prosody";
    };

    # rmfakecloud JWT Secret
    secrets.rmfakecloud_jwt_secret = {
      sopsFile = ../secrets/rmfakecloud.yaml;
      mode = "0400";
    };

    # WireGuard-Reverse-Tunnel zu proxy-01 (Homeserver)
    secrets.wg_reverse_tunnel_private_key = {
      mode = "0400";
    };

    # rmfakecloud Self-Signed CA + Server-Cert
    # Werte sind base64-encoded (siehe secrets/rmfakecloud-ca.yaml) — sops-nix
    # schreibt den encodeten Rohinhalt; ein activationScript unten dekodiert
    # in-place. Grund fuer base64: mehrzeilige PEM-Strings sind in sops-Editor
    # fehleranfaellig (Trailing-Whitespace / Newline-Handling).
    secrets."rmfakecloud-ca/ca.crt" = {
      sopsFile = ../secrets/rmfakecloud-ca.yaml;
      key = "ca_crt_b64";
      mode = "0444";
      owner = "nginx";
      group = "nginx";
      restartUnits = [ "nginx.service" ];
    };
    secrets."rmfakecloud-ca/ca.key" = {
      sopsFile = ../secrets/rmfakecloud-ca.yaml;
      key = "ca_key_b64";
      mode = "0440";
      owner = "nginx";
      group = "nginx";
      restartUnits = [ "nginx.service" ];
    };
    secrets."rmfakecloud-ca/server.crt" = {
      sopsFile = ../secrets/rmfakecloud-ca.yaml;
      key = "server_crt_b64";
      mode = "0444";
      owner = "nginx";
      group = "nginx";
      restartUnits = [ "nginx.service" ];
    };
    secrets."rmfakecloud-ca/server.key" = {
      sopsFile = ../secrets/rmfakecloud-ca.yaml;
      key = "server_key_b64";
      mode = "0440";
      owner = "nginx";
      group = "nginx";
      restartUnits = [ "nginx.service" ];
    };
  };

  # sops-nix schreibt die 4 rmfakecloud-ca-Secrets als base64-encoded Strings.
  # Hier idempotent dekodieren, nachdem sops-install-secrets seine Arbeit getan
  # hat. Permissions bleiben identisch zu den sops.secrets-Definitionen oben.
  system.activationScripts.rmfakecloudCaDecode = {
    deps = [ "setupSecrets" ];
    text = ''
      for name in ca.crt ca.key server.crt server.key; do
        src="/run/secrets/rmfakecloud-ca/$name"
        if [ -f "$src" ]; then
          tmp="$src.decoded"
          ${pkgs.coreutils}/bin/base64 -d "$src" > "$tmp"
          ${pkgs.coreutils}/bin/chown nginx:nginx "$tmp"
          case "$name" in
            *.key) ${pkgs.coreutils}/bin/chmod 0440 "$tmp" ;;
            *)     ${pkgs.coreutils}/bin/chmod 0444 "$tmp" ;;
          esac
          ${pkgs.coreutils}/bin/mv "$tmp" "$src"
        fi
      done
    '';
  };
}
