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

    # Redis Cache
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

    # Ghostfolio Application
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
  };

  # Container services must wait for network
  systemd.services.podman-ghostfolio-postgres.after = [ "create-ghostfolio-network.service" ];
  systemd.services.podman-ghostfolio-postgres.requires = [ "create-ghostfolio-network.service" ];
  systemd.services.podman-ghostfolio-redis.after = [ "create-ghostfolio-network.service" ];
  systemd.services.podman-ghostfolio-redis.requires = [ "create-ghostfolio-network.service" ];
  systemd.services.podman-ghostfolio.after = [ "create-ghostfolio-network.service" ];
  systemd.services.podman-ghostfolio.requires = [ "create-ghostfolio-network.service" ];
}
