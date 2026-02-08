{ config, pkgs, lib, ... }:

{
  # ============================================================================
  # SECURITY HARDENING
  # ============================================================================

  # --- Kernel Hardening ---
  boot.kernel.sysctl = {
    # Network Hardening
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

    # Memory Hardening
    "kernel.randomize_va_space" = 2;
    "kernel.kptr_restrict" = 2;
    "kernel.dmesg_restrict" = 1;
    "kernel.perf_event_paranoid" = 3;
    "kernel.yama.ptrace_scope" = 2;
    "kernel.unprivileged_bpf_disabled" = 1;
    "net.core.bpf_jit_harden" = 2;

    # Filesystem Hardening
    "fs.protected_hardlinks" = 1;
    "fs.protected_symlinks" = 1;
    "fs.protected_fifos" = 2;
    "fs.protected_regular" = 2;
    "fs.suid_dumpable" = 0;
  };

  # Kernel Module Blacklist (unused/insecure modules)
  boot.blacklistedKernelModules = [
    "dccp" "sctp" "rds" "tipc"                             # Unused network protocols
    "cramfs" "freevxfs" "jffs2" "hfs" "hfsplus" "udf"    # Unused filesystems
    "firewire-core" "firewire-ohci" "firewire-sbp2"      # FireWire
    "thunderbolt"                                         # Thunderbolt (not needed on VPS)
  ];

  # --- Automatic Security Updates ---
  system.autoUpgrade = {
    enable = true;
    allowReboot = false;  # Manual reboot after updates
    dates = "04:00";
    randomizedDelaySec = "30min";
  };

  # --- Audit & Logging ---
  security.auditd.enable = true;
  security.audit = {
    enable = true;
    rules = [
      # Monitor login attempts
      "-w /var/log/faillog -p wa -k logins"
      "-w /var/log/lastlog -p wa -k logins"

      # Monitor sudo usage
      "-w /etc/sudoers -p wa -k sudoers"
      "-w /etc/sudoers.d -p wa -k sudoers"

      # Monitor SSH configuration
      "-w /etc/ssh/sshd_config -p wa -k sshd"

      # Monitor systemd units
      "-w /etc/systemd -p wa -k systemd"
    ];
  };

  # Journald Configuration
  services.journald = {
    extraConfig = ''
      Storage=persistent
      Compress=yes
      SystemMaxUse=500M
      MaxRetentionSec=1month
    '';
  };

  # --- Additional Security Features ---

  # AppArmor
  security.apparmor.enable = true;

  # Polkit (privilege management)
  security.polkit.enable = true;

  # Disable coredumps (data leak risk)
  systemd.coredump.enable = false;

  # --- DNS-over-TLS with systemd-resolved ---
  services.resolved = {
    enable = true;
    settings = {
      Resolve = {
        DNSSEC = "allow-downgrade";
        DNSOverTLS = "opportunistic";
        FallbackDNS = [
          "9.9.9.9#dns.quad9.net"
          "149.112.112.112#dns.quad9.net"
        ];
      };
    };
  };

  # --- Time Synchronization ---
  # Use Chrony instead of ntpd (more secure)
  services.chrony = {
    enable = true;
    servers = [
      "0.de.pool.ntp.org"
      "1.de.pool.ntp.org"
      "2.de.pool.ntp.org"
    ];
  };

  # Disable timesyncd (Chrony takes over)
  services.timesyncd.enable = false;

  # Disable cron (use systemd timers)
  services.cron.enable = false;
}
