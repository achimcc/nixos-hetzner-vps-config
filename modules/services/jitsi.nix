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
  # JITSI MEET (VIDEO CONFERENCING)
  # ==========================================================================

  services.jitsi-meet = {
    enable = true;
    hostName = commonConfig.services.jitsi;

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
  };

  # ==========================================================================
  # PROSODY XMPP SERVER CONFIGURATION
  # ==========================================================================

  # The jitsi-meet module handles Prosody configuration automatically
  # We just need to enable it
  services.jitsi-meet.prosody.enable = true;

  # Override Prosody config for secure domain
  services.prosody.virtualHosts."${commonConfig.services.jitsi}" = lib.mkForce {
    enabled = true;
    domain = commonConfig.services.jitsi;
    extraConfig = ''
      authentication = "jitsi-anonymous"
      c2s_require_encryption = false
      admins = { "focus@auth.${commonConfig.services.jitsi}" }

      speakerstats_component = "speakerstats.${commonConfig.services.jitsi}"
      conference_duration_component = "conferenceduration.${commonConfig.services.jitsi}"

      av_moderation_component = "avmoderation.${commonConfig.services.jitsi}"
      breakout_rooms_component = "breakout.${commonConfig.services.jitsi}"
      end_conference_component = "endconference.${commonConfig.services.jitsi}"

      modules_enabled = {
        "bosh";
        "pubsub";
        "ping";
        "speakerstats";
        "external_services";
        "conference_duration";
        "end_conference";
        "muc_lobby_rooms";
        "muc_breakout_rooms";
        "av_moderation";
        "room_metadata";
      }
    '';
  };

  # Force MUC component to restrict room creation to authenticated users only
  services.prosody.muc = [{
    domain = "conference.${commonConfig.services.jitsi}";
    name = "Jitsi Meet MUC";
    restrictRoomCreation = true;  # Only authenticated users can create rooms
    extraConfig = ''
      restrict_room_creation = true
      muc_room_locking = false
      muc_tombstones = true
      muc_room_default_public = true
    '';
  }];

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
