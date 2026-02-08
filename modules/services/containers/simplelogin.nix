{ config, pkgs, lib, commonConfig, ... }:

{
  # ============================================================================
  # SIMPLELOGIN (PODMAN CONTAINERS)
  # ============================================================================

  # Create directory structure
  systemd.tmpfiles.rules = [
    "d /var/lib/simplelogin 0755 root root -"
    "d /var/lib/simplelogin/postgres 0750 70 70 -"
    "d /var/lib/simplelogin/redis 0755 999 999 -"
    "d /var/lib/simplelogin/data 0750 root root -"
    "d /var/lib/simplelogin/upload 0750 root root -"
    "d /var/lib/simplelogin/dkim 0700 root root -"
  ];

  # Create Podman network for SimpleLogin
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

  # OCI Containers
  virtualisation.oci-containers.containers = {
    # PostgreSQL Database
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

    # Redis Cache
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

      # Run both web server and email handler
      cmd = [ "sh" "-c" "gunicorn wsgi:app -b 0.0.0.0:7777 -w 2 --timeout 15 & python /code/email_handler.py" ];

      ports = [
        "127.0.0.1:7777:7777"      # Web UI
        "127.0.0.1:20381:20381"    # Email handler (SMTP)
      ];

      environment = {
        # URLs & Domains
        URL = "https://${commonConfig.services.simplelogin}";
        EMAIL_DOMAIN = commonConfig.emailDomain;
        SUPPORT_EMAIL = "support@${commonConfig.emailDomain}";
        SUPPORT_NAME = "SimpleLogin Support";

        # Premium Features (all enabled for self-hosting)
        PREMIUM = "true";
        MAX_NB_EMAIL_FREE_PLAN = "999999";

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
}
