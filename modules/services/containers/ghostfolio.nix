{ config, pkgs, lib, ... }:

{
  # ============================================================================
  # GHOSTFOLIO (PODMAN CONTAINERS)
  # ============================================================================

  # Create Podman network for Ghostfolio
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

  # OCI Containers
  virtualisation.oci-containers.containers = {
    # PostgreSQL Database
    ghostfolio-postgres = {
      image = "docker.io/library/postgres:15-alpine@sha256:d326a0ce8bce59394a11fe4fedbf619611a3957dff4692b440646b75ea2e4498";
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
        "--memory=512m"
        "--pids-limit=256"
        "--health-cmd=pg_isready -U ghostfolio"
        "--health-interval=10s"
        "--health-timeout=5s"
        "--health-retries=5"
      ];
    };

    # Redis Cache
    ghostfolio-redis = {
      image = "docker.io/library/redis:alpine@sha256:0804c395e634e624243387d3c3a9c45fcaca876d313c2c8b52c3fdf9a912dded";
      extraOptions = [
        "--network=ghostfolio-net"
        "--cap-drop=ALL"
        "--cap-add=SETGID"
        "--cap-add=SETUID"
        "--security-opt=no-new-privileges:true"
        "--memory=256m"
        "--pids-limit=128"
        "--health-cmd=redis-cli ping"
        "--health-interval=10s"
        "--health-timeout=5s"
        "--health-retries=5"
      ];
    };

    # Ghostfolio Application
    ghostfolio = {
      image = "docker.io/ghostfolio/ghostfolio:latest@sha256:376df9280cf29938a5996b8eaddd42edf95c69a3661b4ef7ea12c7deb078777b";
      ports = [ "127.0.0.1:3333:3333" ];
      environmentFiles = [ config.sops.secrets.ghostfolio_env.path ];
      dependsOn = [ "ghostfolio-postgres" "ghostfolio-redis" ];
      extraOptions = [
        "--network=ghostfolio-net"
        "--cap-drop=ALL"
        "--cap-add=SETGID"
        "--cap-add=SETUID"
        "--security-opt=no-new-privileges:true"
        "--memory=1g"
        "--pids-limit=512"
      ];
    };
  };

  # Container services must wait for network
  systemd.services.podman-ghostfolio-postgres.after = [ "create-ghostfolio-network.service" ];
  systemd.services.podman-ghostfolio-postgres.requires = [ "create-ghostfolio-network.service" ];
  systemd.services.podman-ghostfolio-redis.after = [ "create-ghostfolio-network.service" ];
  systemd.services.podman-ghostfolio-redis.requires = [ "create-ghostfolio-network.service" ];
  systemd.services.podman-ghostfolio.after = [ "create-ghostfolio-network.service" ];
  systemd.services.podman-ghostfolio.requires = [ "create-ghostfolio-network.service" ];
}
