{ lib, commonConfig, pkgs }:

{
  # ============================================================================
  # NGINX HELPERS
  # ============================================================================

  # Reusable security headers for all NGINX vhosts
  nginxSecurityHeaders = ''
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Permissions-Policy "accelerometer=(), camera=(), geolocation=(), gyroscope=(), magnetometer=(), microphone=(), payment=(), usb=()" always;
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
  '';

  # Standard rate limiting configuration
  nginxRateLimiting = ''
    limit_req zone=general burst=20 nodelay;
    limit_conn addr 10;
  '';

  # Strict rate limiting for admin endpoints
  nginxRateLimitingStrict = ''
    limit_req zone=general burst=5 nodelay;
  '';

  # ============================================================================
  # PODMAN HELPERS
  # ============================================================================

  # Helper to create Podman network creation service
  mkPodmanNetwork = { name, description ? "Create Podman network for ${name}" }: pkgs: {
    systemd.services."create-${name}-network" = {
      inherit description;
      after = [ "podman.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        ${pkgs.podman}/bin/podman network exists ${name} || \
        ${pkgs.podman}/bin/podman network create ${name}
      '';
    };
  };
}
