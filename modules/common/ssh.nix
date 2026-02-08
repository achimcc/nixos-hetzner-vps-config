{ config, pkgs, lib, ... }:

{
  # ============================================================================
  # SSH HARDENING
  # ============================================================================

  services.openssh = {
    enable = true;
    openFirewall = true;

    settings = {
      # Key-only authentication
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "prohibit-password";

      # Strong cryptography
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

      # Additional hardening
      X11Forwarding = false;
      AllowAgentForwarding = false;
      AllowTcpForwarding = false;
      PermitTunnel = "no";
      MaxAuthTries = 3;
      LoginGraceTime = 30;
      ClientAliveInterval = 300;
      ClientAliveCountMax = 2;
    };

    # Only secure host key types
    hostKeys = [
      { path = "/etc/ssh/ssh_host_ed25519_key"; type = "ed25519"; }
      { path = "/etc/ssh/ssh_host_rsa_key"; type = "rsa"; bits = 4096; }
    ];
  };
}
