{ config, pkgs, lib, commonConfig, ... }:

{
  # ==========================================================================
  # NIXPKGS CONFIGURATION
  # ==========================================================================

  # Allow insecure Jitsi package (marked insecure due to deprecated libolm)
  # Note: The libolm library is deprecated but still functional
  # We're accepting this risk for now as Jitsi is actively working on migration
  nixpkgs.config.permittedInsecurePackages = [
    "jitsi-meet-1.0.8792"
  ];

  # ==========================================================================
  # JITSI MEET (VIDEO CONFERENCING) WITH SECURE DOMAIN AUTHENTICATION
  # ==========================================================================

  services.jitsi-meet = {
    enable = true;
    hostName = commonConfig.services.jitsi;

    # SECURE DOMAIN AUTHENTICATION - Only authenticated moderators can create meetings
    # Guests can join meetings but cannot create them
    secureDomain = {
      enable = true;
      # authentication = "internal_hashed";  # This is the default
    };

    config = {
      # Disable P2P to always use JVB for better reliability
      p2p.enabled = false;

      # Enable prejoin page
      prejoinPageEnabled = true;

      # Default to muted on join
      startAudioOnly = false;
      startAudioMuted = 10;
      startVideoMuted = 10;

      # Enable features
      enableWelcomePage = true;
      enableClosePage = false;

      # Require display name
      requireDisplayName = true;
    };

    # Interface configuration (overrides)
    interfaceConfig = {
      # Disable the unsupported browser page
      SHOW_JITSI_WATERMARK = false;
      SHOW_WATERMARK_FOR_GUESTS = false;
    };

    # Additional custom configuration
    extraConfig = ''
      // Allow all browsers - disable unsupported browser check
      config.disableDeepLinking = false;
    '';

    # NGINX integration - managed by NixOS module
    nginx.enable = true;

    # Jicofo (conference focus) configuration
    jicofo.enable = true;

    # JVB (videobridge) configuration
    videobridge.enable = true;

    # Prosody XMPP server
    prosody.enable = true;
  };

  # ==========================================================================
  # NGINX CUSTOMIZATION
  # ==========================================================================

  # The jitsi-meet module auto-configures NGINX, but we need to:
  # 1. Enable ACME/Let's Encrypt
  # 2. Add security headers

  services.nginx.virtualHosts.${commonConfig.services.jitsi} = {
    enableACME = true;
    forceSSL = true;

    # Additional config will be merged with jitsi-meet defaults
    extraConfig = ''
      # Security headers
      add_header X-Content-Type-Options "nosniff" always;
      add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    '';
  };

  # ==========================================================================
  # SYSTEMD SERVICE DEPENDENCIES
  # ==========================================================================

  # Ensure Prosody starts after ACME certificates are available
  systemd.services.prosody = {
    after = [ "acme-${commonConfig.services.jitsi}.service" ];
    wants = [ "acme-${commonConfig.services.jitsi}.service" ];
  };
}
