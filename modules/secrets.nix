{ config, ... }:

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
  };
}
