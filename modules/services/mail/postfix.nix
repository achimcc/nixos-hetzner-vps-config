{ config, pkgs, lib, commonConfig, ... }:

{
  # ============================================================================
  # POSTFIX (MAIL SERVER FOR SIMPLELOGIN)
  # ============================================================================

  services.postfix = {
    enable = true;

    # Transport: All sl.rusty-vault.de emails to SimpleLogin email handler
    transport = ''
      ${commonConfig.emailDomain} smtp:[127.0.0.1]:20381
    '';

    setSendmail = true;

    settings.main = {
      myhostname = commonConfig.services.mail;

      # SimpleLogin Relay Domain - accept and relay all mail to SimpleLogin
      relay_domains = [ commonConfig.emailDomain ];
      relay_recipient_maps = [];

      # Allow container network to relay outbound mail (for SimpleLogin forwarding)
      mynetworks = [ "127.0.0.0/8" "10.89.0.0/16" "[::1]/128" ];

      # SMTP Settings
      smtpd_banner = "$myhostname ESMTP";

      # TLS for incoming connections
      smtpd_tls_cert_file = "/var/lib/acme/${commonConfig.services.mail}/cert.pem";
      smtpd_tls_key_file = "/var/lib/acme/${commonConfig.services.mail}/key.pem";
      smtpd_use_tls = "yes";
      smtpd_tls_security_level = "may";

      # TLS for outgoing connections
      smtp_tls_security_level = "may";
      smtp_tls_loglevel = "1";

      # SASL Authentication for relay (Brevo SMTP on port 587)
      relayhost = [ "smtp-relay.brevo.com:587" ];
      smtp_sasl_auth_enable = "yes";
      smtp_sasl_password_maps = "hash:/var/lib/postfix/sasl_passwd";
      smtp_sasl_security_options = "noanonymous";
      smtp_sasl_tls_security_options = "noanonymous";
      smtp_tls_wrappermode = "no";
      smtp_use_tls = "yes";

      # Message size limit (25MB)
      message_size_limit = 26214400;

      # Rate Limiting
      smtpd_client_connection_rate_limit = 10;
      smtpd_error_sleep_time = "1s";
      smtpd_soft_error_limit = 10;
      smtpd_hard_error_limit = 20;

      # Reject invalid recipients early
      # Note: reject_unknown_recipient_domain removed to allow relay_domains
      # even when DNS is not yet fully propagated
      smtpd_recipient_restrictions = lib.concatStringsSep "," [
        "reject_non_fqdn_recipient"
        "permit_mynetworks"
        "reject_unauth_destination"
      ];
    };
  };

  # Generate Postfix SASL password file from SOPS secrets
  systemd.services.postfix-sasl-passwd = {
    description = "Generate Postfix SASL password file";
    wantedBy = [ "multi-user.target" ];
    after = [ "sops-nix.service" ];
    before = [ "postfix.service" ];
    wants = [ "sops-nix.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -x
      mkdir -p /var/lib/postfix
      chown postfix:postfix /var/lib/postfix
      USERNAME=$(cat ${config.sops.secrets.brevo_smtp_username.path})
      PASSWORD=$(cat ${config.sops.secrets.brevo_smtp_password.path})
      echo "[smtp-relay.brevo.com]:587 $USERNAME:$PASSWORD" > /var/lib/postfix/sasl_passwd
      chmod 600 /var/lib/postfix/sasl_passwd
      ${pkgs.postfix}/bin/postmap /var/lib/postfix/sasl_passwd
      chmod 600 /var/lib/postfix/sasl_passwd.db
      chown postfix:postfix /var/lib/postfix/sasl_passwd*
      ls -la /var/lib/postfix/sasl_passwd*
    '';
  };
}
