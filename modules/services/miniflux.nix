{ config, pkgs, lib, commonConfig, ... }:

{
  # ============================================================================
  # MINIFLUX RSS READER
  # ============================================================================

  services.miniflux = {
    enable = true;
    createDatabaseLocally = true;  # Automatic PostgreSQL setup
    adminCredentialsFile = config.sops.secrets.miniflux_admin.path;
    config = {
      LISTEN_ADDR = "127.0.0.1:8081";
      BASE_URL = "https://${commonConfig.domain}/miniflux/";
      CLEANUP_FREQUENCY = "48";              # Hours between cleanup
      CLEANUP_ARCHIVE_UNREAD_DAYS = "7";     # Auto-mark unread entries older than 7 days as read
      POLLING_FREQUENCY = 60;                # Feed polling in minutes
    };
  };
}
