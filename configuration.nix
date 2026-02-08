{ config, pkgs, lib, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      # sops-nix fuer verschluesselte Secrets
      (builtins.fetchTarball {
        url = "https://github.com/Mic92/sops-nix/archive/master.tar.gz";
        # Optional: Pin auf eine spezifische Version fuer Reproduzierbarkeit
        # sha256 = "...";
      } + "/modules/sops")
    ];

  # --- SOPS Konfiguration ---
  sops = {
    defaultSopsFile = ./secrets/secrets.yaml;
    age.keyFile = "/var/lib/sops-nix/key.txt";
    secrets.miniflux_admin = {
      # Der miniflux user wird automatisch vom Service erstellt
      # Wir setzen owner/group manuell um das Problem zu umgehen
      mode = "0400";
    };
    secrets.vaultwarden_env = {
      sopsFile = ./secrets/vaultwarden.yaml;
      mode = "0400";
    };
    secrets.ghostfolio_env = {
      sopsFile = ./secrets/ghostfolio.yaml;
      mode = "0400";
    };
    secrets.simplelogin_db_password = {
      sopsFile = ./secrets/simplelogin.yaml;
      mode = "0400";
    };
    secrets.simplelogin_db_uri = {
      sopsFile = ./secrets/simplelogin.yaml;
      mode = "0400";
    };
    secrets.simplelogin_flask_secret = {
      sopsFile = ./secrets/simplelogin.yaml;
      mode = "0400";
    };
    secrets.simplelogin_email_secret = {
      sopsFile = ./secrets/simplelogin.yaml;
      mode = "0400";
    };
  };

  # ============================================================================
  # SECURITY HARDENING
  # ============================================================================

  # --- Kernel Hardening ---
  boot.kernel.sysctl = {
    # Netzwerk-Hardening
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.default.accept_redirects" = 0;
    "net.ipv4.conf.all.secure_redirects" = 0;
    "net.ipv4.conf.default.secure_redirects" = 0;
    "net.ipv6.conf.all.accept_redirects" = 0;
    "net.ipv6.conf.default.accept_redirects" = 0;
    "net.ipv4.conf.all.send_redirects" = 0;
    "net.ipv4.conf.default.send_redirects" = 0;
    "net.ipv4.conf.all.accept_source_route" = 0;
    "net.ipv4.conf.default.accept_source_route" = 0;
    "net.ipv6.conf.all.accept_source_route" = 0;
    "net.ipv6.conf.default.accept_source_route" = 0;
    "net.ipv4.conf.all.log_martians" = 1;
    "net.ipv4.conf.default.log_martians" = 1;
    "net.ipv4.icmp_echo_ignore_broadcasts" = 1;
    "net.ipv4.icmp_ignore_bogus_error_responses" = 1;
    "net.ipv4.conf.all.rp_filter" = 1;
    "net.ipv4.conf.default.rp_filter" = 1;
    "net.ipv4.tcp_syncookies" = 1;
    "net.ipv4.tcp_timestamps" = 0;

    # Speicher-Hardening
    "kernel.randomize_va_space" = 2;
    "kernel.kptr_restrict" = 2;
    "kernel.dmesg_restrict" = 1;
    "kernel.perf_event_paranoid" = 3;
    "kernel.yama.ptrace_scope" = 2;
    "kernel.unprivileged_bpf_disabled" = 1;
    "net.core.bpf_jit_harden" = 2;

    # Filesystem-Hardening
    "fs.protected_hardlinks" = 1;
    "fs.protected_symlinks" = 1;
    "fs.protected_fifos" = 2;
    "fs.protected_regular" = 2;
    "fs.suid_dumpable" = 0;
  };

  # Kernel-Module Blacklist (ungenutzte/unsichere Module)
  boot.blacklistedKernelModules = [
    "dccp" "sctp" "rds" "tipc"  # Ungenutzte Netzwerk-Protokolle
    "cramfs" "freevxfs" "jffs2" "hfs" "hfsplus" "udf"  # Ungenutzte Dateisysteme
    "firewire-core" "firewire-ohci" "firewire-sbp2"  # FireWire
    "thunderbolt"  # Thunderbolt (nicht auf VPS benoetigt)
  ];

  # --- Automatische Sicherheitsupdates ---
  system.autoUpgrade = {
    enable = true;
    allowReboot = false;  # Manueller Reboot nach Updates
    dates = "04:00";
    randomizedDelaySec = "30min";
  };

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
  # GHOSTFOLIO (Podman Container)
  # ============================================================================

  # Podman als Container-Runtime
  virtualisation.podman = {
    enable = true;
    defaultNetwork.settings.dns_enabled = true;
  };

  # Podman-Netzwerk fuer Ghostfolio erstellen
  systemd.services.create-ghostfolio-network = {
    description = "Create Podman network for Ghostfolio";
    after = [ "podman.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.podman}/bin/podman network exists ghostfolio-net || \
      ${pkgs.podman}/bin/podman network create ghostfolio-net
    '';
  };

  # Podman-Netzwerk fuer SimpleLogin erstellen
  systemd.services.create-simplelogin-network = {
    description = "Create Podman network for SimpleLogin";
    after = [ "podman.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.podman}/bin/podman network exists simplelogin-net || \
      ${pkgs.podman}/bin/podman network create simplelogin-net
    '';
  };

  # Directory structure for SimpleLogin
  systemd.tmpfiles.rules = [
    # SimpleLogin directories
    "d /var/lib/simplelogin 0755 root root -"
    "d /var/lib/simplelogin/postgres 0750 70 70 -"
    "d /var/lib/simplelogin/redis 0755 999 999 -"
    "d /var/lib/simplelogin/data 0750 root root -"
    "d /var/lib/simplelogin/upload 0750 root root -"
    "d /var/lib/simplelogin/dkim 0700 root root -"
  ];

  # OCI-Container
  virtualisation.oci-containers.backend = "podman";
  virtualisation.oci-containers.containers = {

    ghostfolio-postgres = {
      image = "docker.io/library/postgres:15-alpine";
      environmentFiles = [ config.sops.secrets.ghostfolio_env.path ];
      volumes = [ "ghostfolio-pgdata:/var/lib/postgresql/data" ];
      extraOptions = [
        "--network=ghostfolio-net"
        "--cap-drop=ALL"
        "--cap-add=DAC_OVERRIDE"
        "--cap-add=SETGID"
        "--cap-add=SETUID"
        "--cap-add=FOWNER"
        "--cap-add=CHOWN"
        "--security-opt=no-new-privileges:true"
        "--health-cmd=pg_isready -U ghostfolio"
        "--health-interval=10s"
        "--health-timeout=5s"
        "--health-retries=5"
      ];
    };

    ghostfolio-redis = {
      image = "docker.io/library/redis:alpine";
      extraOptions = [
        "--network=ghostfolio-net"
        "--cap-drop=ALL"
        "--cap-add=SETGID"
        "--cap-add=SETUID"
        "--security-opt=no-new-privileges:true"
        "--health-cmd=redis-cli ping"
        "--health-interval=10s"
        "--health-timeout=5s"
        "--health-retries=5"
      ];
    };

    ghostfolio = {
      image = "docker.io/ghostfolio/ghostfolio:latest";
      ports = [ "127.0.0.1:3333:3333" ];
      environmentFiles = [ config.sops.secrets.ghostfolio_env.path ];
      dependsOn = [ "ghostfolio-postgres" "ghostfolio-redis" ];
      extraOptions = [
        "--network=ghostfolio-net"
        "--cap-drop=ALL"
        "--cap-add=SETGID"
        "--cap-add=SETUID"
        "--security-opt=no-new-privileges:true"
      ];
    };

    # SimpleLogin PostgreSQL Database
    simplelogin-postgres = {
      image = "docker.io/library/postgres:15-alpine";
      autoStart = true;

      environment = {
        POSTGRES_DB = "simplelogin";
        POSTGRES_USER = "simplelogin";
      };

      environmentFiles = [
        config.sops.secrets.simplelogin_db_password.path
      ];

      volumes = [
        "/var/lib/simplelogin/postgres:/var/lib/postgresql/data"
      ];

      extraOptions = [
        "--network=simplelogin-net"
        "--cap-drop=ALL"
        "--cap-add=DAC_OVERRIDE"
        "--cap-add=SETGID"
        "--cap-add=SETUID"
        "--cap-add=FOWNER"
        "--cap-add=CHOWN"
        "--security-opt=no-new-privileges:true"
        "--health-cmd=pg_isready -U simplelogin"
        "--health-interval=10s"
        "--health-timeout=5s"
        "--health-retries=5"
      ];
    };

    # SimpleLogin Redis Cache
    simplelogin-redis = {
      image = "docker.io/library/redis:7-alpine";
      autoStart = true;

      volumes = [
        "/var/lib/simplelogin/redis:/data"
      ];

      extraOptions = [
        "--network=simplelogin-net"
        "--cap-drop=ALL"
        "--cap-add=SETGID"
        "--cap-add=SETUID"
        "--security-opt=no-new-privileges:true"
        "--health-cmd=redis-cli ping"
        "--health-interval=10s"
        "--health-timeout=5s"
        "--health-retries=5"
      ];
    };

    # SimpleLogin Application
    simplelogin-app = {
      image = "docker.io/simplelogin/app:latest";
      autoStart = true;

      ports = [
        "127.0.0.1:7777:7777"
      ];

      environment = {
        # URLs & Domains
        URL = "https://simplelogin.rusty-vault.de";
        SERVER_NAME = "simplelogin.rusty-vault.de";
        PREFERRED_URL_SCHEME = "https";
        EMAIL_DOMAIN = "sl.rusty-vault.de";
        SUPPORT_EMAIL = "support@sl.rusty-vault.de";
        SUPPORT_NAME = "SimpleLogin Support";

        # Premium Features (all enabled for self-hosting)
        PREMIUM = "true";
        MAX_NB_EMAIL_FREE_PLAN = "999999";

        # Database connection - DB_URI comes from environmentFiles with password
        # (cannot hardcode password here due to security)

        # Redis
        REDIS_URL = "redis://simplelogin-redis:6379";

        # Email via Postfix on host
        POSTFIX_SERVER = "host.containers.internal";
        POSTFIX_PORT = "25";
        POSTFIX_SUBMISSION_TLS = "false";
        EMAIL_SERVERS_WITH_PRIORITY = "[(\"host.containers.internal\", 25)]";

        # DKIM signing
        DKIM_PRIVATE_KEY_PATH = "/dkim/dkim.key";
        DKIM_PUBLIC_KEY_PATH = "/dkim/dkim.pub.key";

        # OpenID/JWT keys (optional but app may require them)
        OPENID_PRIVATE_KEY_PATH = "/dkim/openid.key";
        OPENID_PUBLIC_KEY_PATH = "/dkim/openid.pub.key";

        # Word list for random alias suffixes
        WORDS_FILE_PATH = "/code/local_data/words.txt";

        # DNS nameservers
        NAMESERVERS = "8.8.8.8,1.1.1.1";

        # Flask configuration
        FLASK_SECRET = "/run/secrets/simplelogin_flask_secret";

        # Disable email sending for now (can enable later)
        NOT_SEND_EMAIL = "false";

        # Disable local email server (we use host Postfix)
        LOCAL_FILE_UPLOAD = "1";
      };

      environmentFiles = [
        config.sops.secrets.simplelogin_db_password.path  # POSTGRES_PASSWORD for DB container
        config.sops.secrets.simplelogin_db_uri.path       # DB_URI with embedded password
      ];

      volumes = [
        "/var/lib/simplelogin/data:/sl/data"
        "/var/lib/simplelogin/upload:/code/static/upload"
        "/var/lib/simplelogin/dkim:/dkim"
        "${config.sops.secrets.simplelogin_flask_secret.path}:/run/secrets/simplelogin_flask_secret:ro"
      ];

      extraOptions = [
        "--network=simplelogin-net"
        "--add-host=host.containers.internal:host-gateway"
        "--cap-drop=ALL"
        "--cap-add=NET_BIND_SERVICE"
        "--security-opt=no-new-privileges:true"
      ];

      dependsOn = [
        "simplelogin-postgres"
        "simplelogin-redis"
      ];
    };
  };

  # Container-Services muessen auf das Netzwerk warten
  systemd.services.podman-ghostfolio-postgres.after = [ "create-ghostfolio-network.service" ];
  systemd.services.podman-ghostfolio-postgres.requires = [ "create-ghostfolio-network.service" ];
  systemd.services.podman-ghostfolio-redis.after = [ "create-ghostfolio-network.service" ];
  systemd.services.podman-ghostfolio-redis.requires = [ "create-ghostfolio-network.service" ];
  systemd.services.podman-ghostfolio.after = [ "create-ghostfolio-network.service" ];
  systemd.services.podman-ghostfolio.requires = [ "create-ghostfolio-network.service" ];

  # ============================================================================
  # POSTFIX (MAIL SERVER FOR SIMPLELOGIN)
  # ============================================================================

  services.postfix = {
    enable = true;
    hostname = "mail.rusty-vault.de";

    # SimpleLogin as Virtual Alias Domain
    virtual = ''
      @sl.rusty-vault.de simplelogin
    '';

    # Transport: All sl.rusty-vault.de emails to SimpleLogin
    transport = ''
      sl.rusty-vault.de smtp:[127.0.0.1]:7777
    '';

    # Relay Host (empty = direct sending)
    relayHost = "";

    config = {
      # SimpleLogin Virtual Domain
      virtual_alias_domains = "sl.rusty-vault.de";

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

      # Message size limit (25MB)
      message_size_limit = "26214400";

      # Rate Limiting
      smtpd_client_connection_rate_limit = "10";
      smtpd_error_sleep_time = "1s";
      smtpd_soft_error_limit = "10";
      smtpd_hard_error_limit = "20";

      # Reject invalid recipients early
      smtpd_recipient_restrictions = lib.concatStringsSep "," [
        "reject_non_fqdn_recipient"
        "reject_unknown_recipient_domain"
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
  # NGINX REVERSE PROXY (HARDENED)
  # ============================================================================

  services.nginx = {
    enable = true;
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;

    # Globale Sicherheitseinstellungen
    appendHttpConfig = ''
      # Rate Limiting
      limit_req_zone $binary_remote_addr zone=general:10m rate=10r/s;
      limit_conn_zone $binary_remote_addr zone=addr:10m;
    '';

    virtualHosts."rusty-vault.de" = {
      enableACME = true;
      forceSSL = true;

      # ACME Challenge ohne Rate-Limiting
      locations."/.well-known/acme-challenge" = {
        root = "/var/lib/acme/acme-challenge";
        extraConfig = ''
          auth_basic off;
        '';
      };

      # Security Headers
      extraConfig = ''
        # Rate Limiting anwenden
        limit_req zone=general burst=20 nodelay;
        limit_conn addr 10;

        # Security Headers
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header X-XSS-Protection "1; mode=block" always;
        add_header Referrer-Policy "strict-origin-when-cross-origin" always;
        add_header Permissions-Policy "accelerometer=(), camera=(), geolocation=(), gyroscope=(), magnetometer=(), microphone=(), payment=(), usb=()" always;

        # HSTS (2 Jahre)
        add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
      '';

      locations."/" = {
        proxyPass = "http://127.0.0.1:8222";
        proxyWebsockets = true;
        extraConfig = ''
          # Proxy-spezifische Sicherheit
          proxy_hide_header X-Powered-By;
          proxy_hide_header Server;
        '';
      };

      # Admin-Panel zusaetzlich schuetzen (optional: IP-Whitelist)
      locations."/admin" = {
        proxyPass = "http://127.0.0.1:8222";
        extraConfig = ''
          # Strengeres Rate Limiting fuer Admin
          limit_req zone=general burst=5 nodelay;

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

    virtualHosts."ghostfolio.rusty-vault.de" = {
      enableACME = true;
      forceSSL = true;

      extraConfig = ''
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header X-XSS-Protection "1; mode=block" always;
        add_header Referrer-Policy "strict-origin-when-cross-origin" always;
        add_header Permissions-Policy "accelerometer=(), camera=(), geolocation=(), gyroscope=(), magnetometer=(), microphone=(), payment=(), usb=()" always;
        add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
      '';

      locations."/" = {
        proxyPass = "http://127.0.0.1:3333";
        proxyWebsockets = true;
        extraConfig = ''
          proxy_hide_header X-Powered-By;
          proxy_hide_header Server;
        '';
      };
    };

    virtualHosts."privatebin.rusty-vault.de" = {
      enableACME = true;
      forceSSL = true;
      serverAliases = [ "pastebin.rusty-vault.de" ];

      extraConfig = ''
        # Rate Limiting (relaxed burst for initial JS load)
        limit_req zone=general burst=30 nodelay;
        limit_conn addr 10;

        # Security Headers (consistent with other services)
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header X-XSS-Protection "1; mode=block" always;
        add_header Referrer-Policy "strict-origin-when-cross-origin" always;
        add_header Permissions-Policy "accelerometer=(), camera=(), geolocation=(), gyroscope=(), magnetometer=(), microphone=(), payment=(), usb=()" always;
        add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;

        # PrivateBin sets its own CSP headers - don't override them

        # Upload size limit
        client_max_body_size 10M;
      '';
    };

    virtualHosts."simplelogin.rusty-vault.de" = {
      enableACME = true;
      forceSSL = true;

      extraConfig = ''
        # Rate Limiting
        limit_req zone=general burst=20 nodelay;
        limit_conn addr 10;

        # WORKAROUND: Fix malformed redirects with duplicate hostname
        # Rewrite URLs like "simplelogin.rusty-vault.de,simplelogin.rusty-vault.de/path" to "/path"
        if ($request_uri ~ "^/simplelogin.rusty-vault.de,simplelogin.rusty-vault.de(.*)$") {
          return 301 https://simplelogin.rusty-vault.de$1;
        }

        # Security Headers (consistent with other services)
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header X-XSS-Protection "1; mode=block" always;
        add_header Referrer-Policy "strict-origin-when-cross-origin" always;
        add_header Permissions-Policy "accelerometer=(), camera=(), geolocation=(), gyroscope=(), magnetometer=(), microphone=(), payment=(), usb=()" always;
        add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;

        # Upload size limit for email attachments
        client_max_body_size 25M;
      '';

      locations."/" = {
        proxyPass = "http://127.0.0.1:7777";
        extraConfig = ''
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto https;
          proxy_set_header X-Forwarded-Host $host;

          # Fix redirects to use HTTPS
          proxy_redirect http://127.0.0.1:7777/ https://$host/;
          proxy_redirect http://$host/ https://$host/;
        '';
      };
    };
  };

  # ============================================================================
  # ACME / LET'S ENCRYPT
  # ============================================================================

  security.acme = {
    acceptTerms = true;
    defaults = {
      email = "achim.schneider@posteo.de";
      # ECDSA-Zertifikate (moderner, schneller)
      keyType = "ec384";
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

  # ============================================================================
  # AUDIT & LOGGING
  # ============================================================================

  # Auditd fuer Security-Monitoring
  security.auditd.enable = true;
  security.audit = {
    enable = true;
    rules = [
      # Login-Versuche ueberwachen
      "-w /var/log/faillog -p wa -k logins"
      "-w /var/log/lastlog -p wa -k logins"

      # Sudo-Nutzung ueberwachen
      "-w /etc/sudoers -p wa -k sudoers"
      "-w /etc/sudoers.d -p wa -k sudoers"

      # SSH-Konfiguration ueberwachen
      "-w /etc/ssh/sshd_config -p wa -k sshd"

      # Systemd-Units ueberwachen
      "-w /etc/systemd -p wa -k systemd"
    ];
  };

  # Journald-Konfiguration
  services.journald = {
    extraConfig = ''
      Storage=persistent
      Compress=yes
      SystemMaxUse=500M
      MaxRetentionSec=1month
    '';
  };

  # ============================================================================
  # ZUSAETZLICHE SICHERHEIT
  # ============================================================================

  # AppArmor aktivieren
  security.apparmor.enable = true;

  # Polkit (Rechteverwaltung)
  security.polkit.enable = true;

  # Coredumps deaktivieren (Datenleck-Risiko)
  systemd.coredump.enable = false;

  # DNS-over-TLS mit systemd-resolved
  services.resolved = {
    enable = true;
    dnssec = "allow-downgrade";
    extraConfig = ''
      DNSOverTLS=opportunistic
    '';
    fallbackDns = [
      "9.9.9.9#dns.quad9.net"
      "149.112.112.112#dns.quad9.net"
    ];
  };

  # Chrony statt ntpd (sicherer)
  services.chrony = {
    enable = true;
    servers = [
      "0.de.pool.ntp.org"
      "1.de.pool.ntp.org"
      "2.de.pool.ntp.org"
    ];
  };

  # NTP deaktivieren (Chrony uebernimmt)
  services.timesyncd.enable = false;

  # Cron deaktivieren (systemd-timer verwenden)
  services.cron.enable = false;

  # Diese Version nicht aendern (definiert Kompatibilitaet)
  system.stateVersion = "25.05";
}
