{ config, pkgs, lib, commonConfig, ... }:

{
  # ============================================================================
  # VAULTWARDEN (BITWARDEN-COMPATIBLE PASSWORD MANAGER)
  # ============================================================================

  services.vaultwarden = {
    enable = true;
    environmentFile = config.sops.secrets.vaultwarden_env.path;
    config = {
      DOMAIN = "https://${commonConfig.services.vaultwarden}";
      SIGNUPS_ALLOWED = false;
      ROCKET_ADDRESS = "127.0.0.1";
      ROCKET_PORT = 8222;
      # ADMIN_TOKEN comes from environmentFile (sops-encrypted)

      # SMTP for Posteo
      SMTP_HOST = "posteo.de";
      SMTP_PORT = 587;
      SMTP_SECURITY = "starttls";
      SMTP_FROM = commonConfig.adminEmail;
      SMTP_USERNAME = commonConfig.adminEmail;
      # SMTP_PASSWORD comes from environmentFile (sops-encrypted)

      # Additional security
      SENDS_ALLOWED = true;
      EMERGENCY_ACCESS_ALLOWED = true;
      ORG_CREATION_USERS = "none";  # Only admins can create organizations
      SHOW_PASSWORD_HINT = false;
    };
  };
}
