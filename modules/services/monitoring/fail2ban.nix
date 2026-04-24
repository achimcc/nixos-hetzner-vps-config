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

      # Brute-Force auf nginx HTTP Basic Auth (z.B. Vaultwarden /admin)
      nginx-http-auth = {
        settings = {
          enabled = true;
          filter = "nginx-http-auth";
          logpath = "/var/log/nginx/error.log";
          maxretry = 5;
          findtime = "10m";
          bantime = "2h";
        };
      };

      # SASL-Auth-Fehler am Postfix (z.B. geraten auf Brevo-Relay-Creds)
      postfix-sasl = {
        settings = {
          enabled = true;
          filter = "postfix[mode=auth]";
          backend = "systemd";
          maxretry = 5;
          findtime = "10m";
          bantime = "2h";
        };
      };

      # Meta-Jail: wer innerhalb eines Tages 5x in anderen Jails gebannt
      # wird, wandert hier fuer eine Woche rein.
      recidive = {
        settings = {
          enabled = true;
          filter = "recidive";
          backend = "systemd";
          maxretry = 5;
          findtime = "1d";
          bantime = "1w";
        };
      };
    };
  };
}
