{ config, pkgs, lib, ... }:

{
  # ============================================================================
  # PODMAN CONTAINER RUNTIME
  # ============================================================================

  virtualisation.podman = {
    enable = true;
    defaultNetwork.settings.dns_enabled = true;
  };

  # Set OCI container backend to Podman
  virtualisation.oci-containers.backend = "podman";
}
