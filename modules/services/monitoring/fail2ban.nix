{ config, pkgs, lib, ... }:

{
  # ============================================================================
  # FAIL2BAN INTRUSION PREVENTION
  # ============================================================================

  services.fail2ban = {
    enable = true;
    maxretry = 5;
    bantime = "1h";
    bantime-increment = {
      enable = true;
      maxtime = "48h";
      factor = "4";
    };
    jails = {
      sshd = {
        settings = {
          enabled = true;
          filter = "sshd";
          maxretry = 3;
          findtime = "10m";
          bantime = "1h";
        };
      };
      nginx-botsearch = {
        settings = {
          enabled = true;
          filter = "nginx-botsearch";
          maxretry = 5;
          findtime = "10m";
          bantime = "1h";
        };
      };
    };
  };
}
