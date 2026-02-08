{ config, pkgs, lib, inputs, commonConfig, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./modules/secrets.nix
    ./modules/common/security-hardening.nix
    ./modules/services/nginx/default.nix
    ./modules/services/containers/podman.nix
    ./modules/services/containers/ghostfolio.nix
    ./modules/services/containers/simplelogin.nix
  ];

  # --- Benutzer-Hardening ---
  # Separater Admin-Benutzer statt direktem Root-Login
  users.users.admin = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIC7i5Y0mgk0vYZRypv6lbM4AnuY1IrCLKrSwoFbB8Y2C achim@hetzner-vps"
    ];
  };

  # Root SSH-Keys behalten fuer Notfall/initrd
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIC7i5Y0mgk0vYZRypv6lbM4AnuY1IrCLKrSwoFbB8Y2C achim@hetzner-vps"
  ];

  # Sudo-Konfiguration
  security.sudo = {
    enable = true;
    wheelNeedsPassword = false;  # Fuer Key-only SSH sinnvoll
    execWheelOnly = true;
  };

  # Passwort-Hashes schuetzen
  users.mutableUsers = false;

  # ============================================================================
  # SSH HARDENING
  # ============================================================================

  services.openssh = {
    enable = true;
    openFirewall = true;

    settings = {
      # Nur Key-Authentifizierung
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "prohibit-password";

      # Starke Krypto
      KexAlgorithms = [
        "curve25519-sha256"
        "curve25519-sha256@libssh.org"
        "diffie-hellman-group16-sha512"
        "diffie-hellman-group18-sha512"
      ];
      Ciphers = [
        "chacha20-poly1305@openssh.com"
        "aes256-gcm@openssh.com"
        "aes128-gcm@openssh.com"
      ];
      Macs = [
        "hmac-sha2-512-etm@openssh.com"
        "hmac-sha2-256-etm@openssh.com"
      ];

      # Weitere Haertung
      X11Forwarding = false;
      AllowAgentForwarding = false;
      AllowTcpForwarding = false;
      PermitTunnel = "no";
      MaxAuthTries = 3;
      LoginGraceTime = 30;
      ClientAliveInterval = 300;
      ClientAliveCountMax = 2;
    };

    # Nur sichere Host-Key-Typen
    hostKeys = [
      { path = "/etc/ssh/ssh_host_ed25519_key"; type = "ed25519"; }
      { path = "/etc/ssh/ssh_host_rsa_key"; type = "rsa"; bits = 4096; }
    ];
  };

  # --- Fail2ban ---
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

  # ============================================================================
  # BOOTLOADER
  # ============================================================================

  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/sda";

  # --- REMOTE UNLOCK (SSH beim Booten) ---
  boot.initrd.network = {
    enable = true;
    ssh = {
      enable = true;
      port = 22;
      authorizedKeys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIC7i5Y0mgk0vYZRypv6lbM4AnuY1IrCLKrSwoFbB8Y2C achim@hetzner-vps" ];
      hostKeys = [ "/etc/secrets/initrd/ssh_host_ed25519_key" ];
    };
  };

  boot.initrd.availableKernelModules = [ "virtio_net" "virtio_pci" ];

  # ============================================================================
  # SYSTEM SETTINGS
  # ============================================================================

  networking.hostName = "nixos-server";

  # IPv6-Konfiguration fuer Hetzner
  networking.interfaces.enp1s0 = {
    ipv6.addresses = [{
      address = "2a01:4f9:c013:5ee7::1";
      prefixLength = 64;
    }];
  };
  networking.defaultGateway6 = {
    address = "fe80::1";
    interface = "enp1s0";
  };

  environment.systemPackages = with pkgs; [
    vim
    git
    htop
    wget
  ];

  # ============================================================================
  # SYNCTHING RELAY SERVER
  # ============================================================================

  services.syncthing.relay = {
    enable = true;

    # Relay-Einstellungen
    listenAddress = "0.0.0.0";
    port = 22067;
    statusListenAddress = "127.0.0.1";
    statusPort = 22070;

    # Pool-Einstellungen (oeffentlich im Syncthing-Pool registrieren)
    pools = [ "https://relays.syncthing.net/endpoint" ];

    # Bandbreiten-Limits (null = unbegrenzt)
    globalRateBps = null;
    perSessionRateBps = null;

    # Identifikation
    providedBy = "rusty-vault.de";
  };

  # ============================================================================
  # VEILID NODE
  # ============================================================================

  services.veilid = {
    enable = true;
    openFirewall = true;  # Oeffnet Port 5150 TCP/UDP
  };

  # ============================================================================
  # MINIFLUX RSS READER
  # ============================================================================

  services.miniflux = {
    enable = true;
    createDatabaseLocally = true;  # Automatisches PostgreSQL Setup
    adminCredentialsFile = config.sops.secrets.miniflux_admin.path;
    config = {
      LISTEN_ADDR = "127.0.0.1:8080";
      BASE_URL = "https://rusty-vault.de/miniflux/";
      CLEANUP_FREQUENCY = "48";  # Stunden zwischen Cleanup
      POLLING_FREQUENCY = 60;  # Feed-Polling in Minuten
    };
  };

  # ============================================================================
  # VAULTWARDEN
  # ============================================================================

  services.vaultwarden = {
    enable = true;
    environmentFile = config.sops.secrets.vaultwarden_env.path;
    config = {
      DOMAIN = "https://rusty-vault.de";
      SIGNUPS_ALLOWED = false;
      ROCKET_ADDRESS = "127.0.0.1";
      ROCKET_PORT = 8222;
      # ADMIN_TOKEN kommt aus environmentFile (sops-verschluesselt)

      # SMTP fuer Posteo
      SMTP_HOST = "posteo.de";
      SMTP_PORT = 587;
      SMTP_SECURITY = "starttls";
      SMTP_FROM = "achim.schneider@posteo.de";
      SMTP_USERNAME = "achim.schneider@posteo.de";
      # SMTP_PASSWORD kommt aus environmentFile (sops-verschluesselt)

      # Zusaetzliche Sicherheit
      SENDS_ALLOWED = true;
      EMERGENCY_ACCESS_ALLOWED = true;
      ORG_CREATION_USERS = "none";  # Nur Admins koennen Organisationen erstellen
      SHOW_PASSWORD_HINT = false;
    };
  };

  # ============================================================================
  # POSTFIX (MAIL SERVER FOR SIMPLELOGIN)
  # ============================================================================

  services.postfix = {
    enable = true;

    # Transport: All sl.rusty-vault.de emails to SimpleLogin email handler
    transport = ''
      sl.rusty-vault.de smtp:[127.0.0.1]:20381
    '';

    setSendmail = true;

    settings.main = {
      myhostname = "mail.rusty-vault.de";
      # SimpleLogin Relay Domain - accept and relay all mail to SimpleLogin
      relay_domains = [ "sl.rusty-vault.de" ];
      relay_recipient_maps = [];

      # Allow container network to relay outbound mail (for SimpleLogin forwarding)
      mynetworks = [ "127.0.0.0/8" "10.89.0.0/16" "[::1]/128" ];

      # SMTP Settings
      smtpd_banner = "$myhostname ESMTP";

      # TLS for incoming connections
      smtpd_tls_cert_file = "/var/lib/acme/mail.rusty-vault.de/cert.pem";
      smtpd_tls_key_file = "/var/lib/acme/mail.rusty-vault.de/key.pem";
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

  # ACME Certificate for mail.rusty-vault.de
  security.acme.certs."mail.rusty-vault.de" = {
    email = "achim.schneider@posteo.de";
    webroot = "/var/lib/acme/acme-challenge";
    postRun = "systemctl reload postfix";
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

  # ============================================================================
  # PRIVATEBIN (PASTEBIN)
  # ============================================================================

  services.privatebin = {
    enable = true;
    enableNginx = true;
    virtualHost = "privatebin.rusty-vault.de";

    settings = {
      main = {
        name = "rusty-vault PrivateBin";
        discussion = true;
        opendiscussion = true;
        fileupload = true;
        burnafterreadingselected = false;
        defaultformatter = "plaintext";
        languageselection = true;
        sizelimit = 10485760;  # 10MB
        template = "bootstrap";
        languagedefault = "de";
      };

      expire = {
        default = "1month";
      };

      expire_options = {
        "5min" = 300;
        "10min" = 600;
        "1hour" = 3600;
        "1day" = 86400;
        "1week" = 604800;
        "1month" = 2592000;
        "1year" = 31536000;
        "never" = 0;
      };

      formatter_options = {
        plaintext = "Plain Text";
        syntaxhighlighting = "Source Code";
        markdown = "Markdown";
      };

      model = {
        class = "Filesystem";
      };

      model_options = {
        dir = "/var/lib/privatebin/data";
      };

      purge = {
        limit = 300;
      };
    };
  };

  # ============================================================================
  # FIREWALL (HARDENED)
  # ============================================================================

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      22      # SSH
      25      # SMTP for SimpleLogin incoming emails
      80      # HTTP
      443     # HTTPS
      22067   # Syncthing Relay
    ];

    # ICMP Rate Limiting
    extraCommands = ''
      # Schutz gegen SYN-Flood
      iptables -A INPUT -p tcp --syn -m limit --limit 1/s --limit-burst 3 -j ACCEPT

      # Ping Rate Limiting
      iptables -A INPUT -p icmp --icmp-type echo-request -m limit --limit 1/s --limit-burst 4 -j ACCEPT
    '';

    # Regeln beim Stoppen entfernen
    extraStopCommands = ''
      iptables -D INPUT -p tcp --syn -m limit --limit 1/s --limit-burst 3 -j ACCEPT 2>/dev/null || true
      iptables -D INPUT -p icmp --icmp-type echo-request -m limit --limit 1/s --limit-burst 4 -j ACCEPT 2>/dev/null || true
    '';

    # Logging fuer abgelehnte Pakete
    logRefusedConnections = true;
    logRefusedPackets = true;
  };

  # Diese Version nicht aendern (definiert Kompatibilitaet)
  system.stateVersion = "25.05";
}
