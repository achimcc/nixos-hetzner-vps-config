# AGENTS.md - NixOS Hetzner VPS Configuration

## Overview

NixOS configuration for a hardened Hetzner VPS running:
- **Vaultwarden** - Self-hosted password manager (Bitwarden-compatible)
- **Miniflux** - Minimalist RSS feed reader
- **Syncthing Relay** - Public relay server for Syncthing file synchronization
- **Veilid Node** - Privacy-focused peer-to-peer network node
- **NGINX** - Reverse proxy with Let's Encrypt TLS termination

Domain: `rusty-vault.de`

## Project Structure

```
.
├── configuration.nix          # Main NixOS configuration (all services)
├── hardware-configuration.nix # Hardware-specific settings (auto-generated, DO NOT EDIT)
├── secrets/
│   └── secrets.yaml           # SOPS-encrypted secrets (SMTP, Miniflux admin)
├── .sops.yaml                 # SOPS encryption config (Age public key)
├── README.md                  # User documentation
└── AGENTS.md                  # This file
```

## Commands

### Deployment (run on server as root)

```bash
# Apply configuration changes
nixos-rebuild switch

# Apply with channel upgrade (updates packages)
nixos-rebuild switch --upgrade

# Test configuration without activating (temporary until reboot)
nixos-rebuild test

# Build without switching (dry-run to check for errors)
nixos-rebuild build

# Check for syntax errors
nix-instantiate --parse /etc/nixos/configuration.nix
```

### Copy Config to Server

```bash
# From local machine to server
scp -r configuration.nix secrets/ .sops.yaml root@<server-ip>:/etc/nixos/

# Or using admin user
scp -r configuration.nix secrets/ .sops.yaml admin@<server-ip>:~/
ssh admin@<server-ip> "sudo cp -r ~/configuration.nix ~/secrets ~/.sops.yaml /etc/nixos/"
```

### Service Management

```bash
# Check service status
systemctl status vaultwarden
systemctl status miniflux
systemctl status nginx
systemctl status syncthing-relay
systemctl status veilid

# View logs (real-time)
journalctl -u vaultwarden -f
journalctl -u miniflux -f
journalctl -u nginx -f
journalctl -u syncthing-relay -f
journalctl -u veilid -f
journalctl -u acme-rusty-vault.de -f

# View recent logs (last 50 lines)
journalctl -u vaultwarden -n 50
journalctl -u miniflux -n 50
journalctl -u nginx -n 50

# Restart services
systemctl restart vaultwarden
systemctl restart miniflux
systemctl restart nginx
systemctl restart syncthing-relay
systemctl restart veilid
```

### ACME/TLS Certificates

```bash
# Check certificate status
systemctl status acme-rusty-vault.de

# Manual certificate renewal
systemctl start acme-rusty-vault.de

# View certificate details
openssl x509 -in /var/lib/acme/rusty-vault.de/cert.pem -text -noout

# If renewal fails with nonce errors (temporary Let's Encrypt issue):
rm -rf /var/lib/acme/rusty-vault.de
systemctl start acme-rusty-vault.de
```

### Secrets Management (SOPS)

```bash
# Edit secrets locally (requires Age key)
sops secrets/secrets.yaml

# Re-encrypt after key rotation
sops updatekeys secrets/secrets.yaml

# View decrypted secrets on server (runtime)
cat /run/secrets/smtp_password
cat /run/secrets/miniflux_admin
```

### Fail2ban

```bash
# Check SSH jail status
fail2ban-client status sshd

# Check nginx jail status
fail2ban-client status nginx-botsearch

# Unban an IP
fail2ban-client set sshd unbanip <IP>

# View banned IPs
fail2ban-client banned
```

### Security Auditing

```bash
# Search audit logs for logins
ausearch -k logins

# Search for sudo events
ausearch -k sudoers

# Search for SSH config changes
ausearch -k sshd

# View systemd unit changes
ausearch -k systemd
```

## Configuration Patterns

### Service Configuration Style

All services are configured in `configuration.nix` using NixOS module options:

```nix
services.<service-name> = {
  enable = true;
  # service-specific options
};
```

### Ports & Networking

| Service | Internal Port | External Port | Protocol | Notes |
|---------|---------------|---------------|----------|-------|
| Vaultwarden | 8222 | - | HTTP | Behind NGINX reverse proxy |
| Miniflux | 8080 | - | HTTP | Behind NGINX reverse proxy at /miniflux/ |
| Syncthing Relay | 22067 | 22067 | TCP | Direct connection, public |
| Syncthing Status | 22070 | - | HTTP | Localhost only, proxied via NGINX |
| Veilid | 5150 | 5150 | TCP/UDP | P2P network node |
| PostgreSQL | 5432 | - | TCP | Localhost only, used by Miniflux |
| NGINX | 80, 443 | 80, 443 | HTTP/HTTPS | TLS termination |
| SSH | 22 | 22 | SSH | Key-only authentication |

### Reverse Proxy Pattern

Services are exposed via NGINX with this pattern:

```nix
services.nginx.virtualHosts."rusty-vault.de" = {
  enableACME = true;
  forceSSL = true;
  locations."/" = {
    proxyPass = "http://127.0.0.1:<internal-port>";
    proxyWebsockets = true;  # if WebSocket support needed
  };
};
```

### Security Headers Pattern

All NGINX locations include security headers:

```nix
extraConfig = ''
  add_header X-Frame-Options "SAMEORIGIN" always;
  add_header X-Content-Type-Options "nosniff" always;
  add_header X-XSS-Protection "1; mode=block" always;
  add_header Referrer-Policy "strict-origin-when-cross-origin" always;
  add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
'';
```

### Secrets Pattern

Secrets are managed via SOPS-nix and Age encryption:

```nix
# Declare secret in configuration.nix
sops.secrets.<secret-name> = {};

# Use in service config
services.<service>.environmentFile = config.sops.secrets.<secret-name>.path;
```

Secret format in `secrets/secrets.yaml` (before encryption):
```yaml
smtp_password: 'SMTP_PASSWORD=actual-password-here'
miniflux_admin: |
  ADMIN_USERNAME=admin
  ADMIN_PASSWORD=your-secure-password
```

**Important**: 
- Backslashes in passwords must be doubled (`\` → `\\`)
- Miniflux passwords must be ≥6 characters
- Use multi-line format (`|`) for credentials with multiple variables

### Firewall Configuration

Port opening is explicit:

```nix
networking.firewall = {
  enable = true;
  allowedTCPPorts = [ 22 80 443 22067 ];  # Veilid port 5150 opened by service
  allowedUDPPorts = [ ];  # Veilid UDP opened by service
};
```

Services can auto-open ports:
```nix
services.veilid = {
  enable = true;
  openFirewall = true;  # Automatically opens port 5150 TCP/UDP
};
```

## Security Configuration

### Key Hardening Features

- **SSH**: Key-only auth, strong ciphers (Curve25519, ChaCha20-Poly1305), no password login
- **Firewall**: Only essential ports open, SYN flood protection, ICMP rate limiting
- **Fail2ban**: Brute-force protection for SSH (3 tries in 10min → 1h ban) and NGINX (5 tries)
- **Kernel**: ASLR, ptrace protection (yama.ptrace_scope=2), BPF JIT hardening, kptr_restrict=2
- **AppArmor**: Mandatory access control enabled system-wide
- **Auditd**: Security event logging for logins, sudo, SSH config, systemd changes
- **DNS-over-TLS**: Opportunistic DoT with Quad9 (9.9.9.9)
- **NGINX**: Security headers, rate limiting (10 req/s general, 5 req/s for /admin), server tokens hidden
- **TLS**: ECDSA P-384 certificates, TLS 1.2+ only, strong cipher suites
- **Auto-updates**: Daily updates at 04:00 (no auto-reboot)
- **Coredumps**: Disabled to prevent memory leaks

### Users

| User | Purpose | Access | Shell |
|------|---------|--------|-------|
| `root` | Emergency/LUKS unlock | SSH key only | bash |
| `admin` | Daily administration | SSH key + passwordless sudo | bash |

SSH login:
```bash
ssh admin@rusty-vault.de
sudo -i  # Root shell if needed
```

### Kernel Modules

Blacklisted modules (unused/insecure):
- Network protocols: `dccp`, `sctp`, `rds`, `tipc`
- Filesystems: `cramfs`, `freevxfs`, `jffs2`, `hfs`, `hfsplus`, `udf`
- Hardware: `firewire-core`, `firewire-ohci`, `firewire-sbp2`, `thunderbolt`

## Common Tasks

### Adding a New Service

1. Add service configuration to `configuration.nix`:
   ```nix
   services.newservice = {
     enable = true;
     # service-specific options
   };
   ```

2. If web-accessible, add NGINX location:
   ```nix
   services.nginx.virtualHosts."rusty-vault.de".locations."/newservice" = {
     proxyPass = "http://127.0.0.1:<port>";
   };
   ```

3. Open firewall port if needed (if not auto-opened by service):
   ```nix
   networking.firewall.allowedTCPPorts = [ ... <port> ];
   ```

4. Build and test locally (if possible):
   ```bash
   nixos-rebuild build
   ```

5. Deploy to server:
   ```bash
   scp configuration.nix root@rusty-vault.de:/etc/nixos/
   ssh root@rusty-vault.de "nixos-rebuild switch"
   ```

6. Verify service is running:
   ```bash
   ssh root@rusty-vault.de "systemctl status newservice"
   ```

### Adding a New Secret

1. Edit secrets file locally:
   ```bash
   sops secrets/secrets.yaml
   # Add new key-value pair
   ```

2. Declare secret in `configuration.nix`:
   ```nix
   sops.secrets.new_secret = {};
   ```

3. Reference in service configuration:
   ```nix
   services.someservice.environmentFile = config.sops.secrets.new_secret.path;
   # OR for individual values:
   services.someservice.passwordFile = config.sops.secrets.new_secret.path;
   ```

4. Deploy to server:
   ```bash
   scp secrets/secrets.yaml root@rusty-vault.de:/etc/nixos/secrets/
   scp configuration.nix root@rusty-vault.de:/etc/nixos/
   ssh root@rusty-vault.de "nixos-rebuild switch"
   ```

5. Verify secret is accessible:
   ```bash
   ssh root@rusty-vault.de "cat /run/secrets/new_secret"
   ```

### Changing Domain/Email

Update these locations in `configuration.nix`:
- `services.vaultwarden.config.DOMAIN` (e.g., `"https://rusty-vault.de"`)
- `services.vaultwarden.config.SMTP_FROM`
- `services.vaultwarden.config.SMTP_USERNAME`
- `security.acme.defaults.email`
- `services.syncthing.relay.providedBy`
- `services.nginx.virtualHosts."<domain>"`

After changing domain:
1. Update DNS records to point to server IP
2. Deploy configuration
3. ACME will automatically request new certificates

### Rotating SMTP Password

1. Edit secrets:
   ```bash
   sops secrets/secrets.yaml
   # Update smtp_password value
   ```

2. Deploy to server:
   ```bash
   scp secrets/secrets.yaml root@rusty-vault.de:/etc/nixos/secrets/
   ssh root@rusty-vault.de "nixos-rebuild switch"
   ```

3. Restart Vaultwarden:
   ```bash
   ssh root@rusty-vault.de "systemctl restart vaultwarden"
   ```

### Managing Miniflux

#### First-time Setup

After deploying, you need to add admin credentials to secrets:

1. **On the server**, edit secrets:
   ```bash
   ssh root@rusty-vault.de
   sops /etc/nixos/secrets/secrets.yaml
   ```

2. Add Miniflux admin credentials:
   ```yaml
   miniflux_admin: |
     ADMIN_USERNAME=admin
     ADMIN_PASSWORD=your-secure-password
   ```

3. Rebuild to apply:
   ```bash
   nixos-rebuild switch
   ```

4. Access Miniflux:
   ```
   https://rusty-vault.de/miniflux/
   ```

#### Accessing Miniflux

- **URL**: `https://rusty-vault.de/miniflux/`
- **Admin login**: Username and password from SOPS secrets
- **First login**: Use admin credentials, then create regular users if needed

#### Managing Feeds

```bash
# Check feed refresh status
ssh root@rusty-vault.de "journalctl -u miniflux -f"

# Manual database operations (if needed)
ssh root@rusty-vault.de "sudo -u postgres psql miniflux"

# Check database size
ssh root@rusty-vault.de "sudo -u postgres psql -c '\l+' | grep miniflux"
```

#### Changing Admin Password

1. Edit secrets on server:
   ```bash
   ssh root@rusty-vault.de "sops /etc/nixos/secrets/secrets.yaml"
   # Update ADMIN_PASSWORD
   ```

2. Restart Miniflux:
   ```bash
   ssh root@rusty-vault.de "systemctl restart miniflux"
   ```

**Note**: Admin user is created on first start. To change password later, use Miniflux web UI (Settings → Users) or update via database.

#### Troubleshooting Miniflux

**Service won't start:**
```bash
# Check logs
journalctl -u miniflux -n 100

# Check PostgreSQL is running
systemctl status postgresql

# Verify secret exists
cat /run/secrets/miniflux_admin
```

**Database issues:**
```bash
# Connect to database
sudo -u postgres psql miniflux

# Check tables
\dt

# Check users
SELECT * FROM users;
```

**Reset admin password directly in database:**
```bash
# Generate password hash (run on server)
echo -n 'newpassword' | miniflux -hash

# Update in database
sudo -u postgres psql miniflux -c "UPDATE users SET password='<hash>' WHERE username='admin';"
```

### Updating NixOS

Automatic updates run daily at 04:00. For manual updates:

```bash
# Update and rebuild
ssh root@rusty-vault.de "nixos-rebuild switch --upgrade"

# Check current version
ssh root@rusty-vault.de "nixos-version"

# Check for available updates (without applying)
ssh root@rusty-vault.de "nix-channel --update && nix-env -u --dry-run"
```

### Testing Configuration Changes Safely

```bash
# 1. Build configuration without activating
nixos-rebuild build

# 2. If build succeeds, test without making it permanent
nixos-rebuild test

# 3. If test works, make it permanent
nixos-rebuild switch

# If test fails, just reboot to go back to previous config
```

## Gotchas & Troubleshooting

### ACME Certificate Errors

**`badNonce` errors** are temporary Let's Encrypt API issues. Solution:
```bash
# Just retry
systemctl start acme-rusty-vault.de

# If persistent, clear state and retry
rm -rf /var/lib/acme/rusty-vault.de
systemctl start acme-rusty-vault.de
```

**Rate limit errors**: Let's Encrypt limits certificates per domain. Wait or use staging environment for testing.

### SOPS Decryption Fails

**Symptom**: Service fails with "cannot read secret" or similar.

**Check Age key exists on server**:
```bash
cat /var/lib/sops-nix/key.txt
```

**Verify public key matches `.sops.yaml`**:
```bash
# Extract public key from private key
nix-shell -p age --run "cat /var/lib/sops-nix/key.txt | grep 'public key:'"
# Compare with key in .sops.yaml
```

**Re-encrypt secrets if key changed**:
```bash
sops updatekeys secrets/secrets.yaml
```

### Service Won't Start After Config Change

1. **Check syntax first**:
   ```bash
   nixos-rebuild build
   ```

2. **View service logs**:
   ```bash
   journalctl -u <service-name> -n 50
   ```

3. **Check if secrets are accessible**:
   ```bash
   cat /run/secrets/<secret-name>
   ls -la /run/secrets/
   ```

4. **Verify service configuration**:
   ```bash
   systemctl cat <service-name>
   ```

### Network Interface Name Changed

**Symptom**: Network not working after hardware change.

**Solution**: Check interface name and update config:
```bash
ip link  # Check actual interface name
# Update configuration.nix:
# networking.interfaces.<interface-name>
# networking.defaultGateway6.interface
```

Current interface: `enp1s0` (Hetzner VPS standard)

### IPv6 Not Working

**Hetzner-specific**: IPv6 must be manually configured.

**Check current address**:
```bash
ip -6 addr show enp1s0
```

**Configuration in `configuration.nix`**:
```nix
networking.interfaces.enp1s0.ipv6.addresses = [{
  address = "2a01:4f9:c013:5ee7::1";  # Your actual IPv6
  prefixLength = 64;
}];
networking.defaultGateway6 = {
  address = "fe80::1";  # Always this on Hetzner
  interface = "enp1s0";
};
```

### Vaultwarden SMTP Not Working

1. **Check password is correct**:
   ```bash
   cat /run/secrets/smtp_password
   ```

2. **Check Vaultwarden logs**:
   ```bash
   journalctl -u vaultwarden | grep -i smtp
   ```

3. **Test SMTP manually**:
   ```bash
   nix-shell -p swaks --run "swaks --to test@example.com --from achim.schneider@posteo.de --server posteo.de:587 --tls --auth-user achim.schneider@posteo.de --auth-password '<password>'"
   ```

4. **Common issues**:
   - Backslashes in password not escaped (must be `\\`)
   - SMTP credentials wrong in secrets.yaml
   - Posteo blocking login (check their web interface)

### Syncthing Relay Not Registering

1. **Check relay is running**:
   ```bash
   systemctl status syncthing-relay
   journalctl -u syncthing-relay -n 50
   ```

2. **Check relay status**:
   ```bash
   curl http://localhost:22070/status
   # Should show JSON with connection stats
   ```

3. **Check if publicly accessible**:
   ```bash
   curl https://rusty-vault.de/relay-status
   ```

4. **Check pool registration**:
   - Relay auto-registers with `https://relays.syncthing.net/endpoint`
   - Can take a few hours to appear in global pool
   - Check logs for registration messages

### SSH Access Lost

**DO NOT PANIC**. Recovery steps:

1. **Use Hetzner rescue system**:
   - Boot into rescue mode via Hetzner admin panel
   - Unlock LUKS partition:
     ```bash
     cryptsetup luksOpen /dev/sda2 enc-pv
     mount /dev/mapper/enc-pv /mnt
     ```

2. **Repair configuration**:
   ```bash
   chroot /mnt
   # Fix /etc/nixos/configuration.nix
   nixos-rebuild switch
   ```

3. **Reboot to normal system**

### Firewall Blocking Legitimate Traffic

**Check current firewall rules**:
```bash
iptables -L -n -v
```

**Temporarily disable firewall** (for testing only):
```bash
systemctl stop firewall
# Test connectivity
systemctl start firewall  # Re-enable
```

**Add port permanently**:
Edit `configuration.nix` and add to `networking.firewall.allowedTCPPorts` or `allowedUDPPorts`.

### Running Out of Disk Space

**Check disk usage**:
```bash
df -h
du -sh /var/lib/* | sort -h
```

**Clean Nix store** (removes old generations and unused packages):
```bash
# Delete old generations (keep last 3)
nix-collect-garbage --delete-older-than 30d

# Optimize store (deduplicate)
nix-store --optimise
```

**Check journal size**:
```bash
journalctl --disk-usage
# If too large:
journalctl --vacuum-time=7d  # Keep only last 7 days
```

## File Locations on Server

| Path | Content | Notes |
|------|---------|-------|
| `/etc/nixos/` | NixOS configuration files | Source of truth for system |
| `/etc/nixos/configuration.nix` | Main config | Edit this for changes |
| `/etc/nixos/hardware-configuration.nix` | Hardware config | Auto-generated, don't edit |
| `/etc/nixos/secrets/secrets.yaml` | Encrypted secrets | SOPS-encrypted |
| `/var/lib/vaultwarden/` | Vaultwarden database | **BACKUP THIS** |
| `/var/lib/miniflux/` | Miniflux data (if any) | Usually empty, data in PostgreSQL |
| `/var/lib/postgresql/` | PostgreSQL database | **BACKUP THIS** - contains Miniflux data |
| `/var/lib/acme/` | TLS certificates | Auto-renewed by ACME |
| `/var/lib/sops-nix/key.txt` | Age decryption key | **BACKUP THIS** - needed to decrypt secrets |
| `/run/secrets/` | Decrypted secrets (runtime) | tmpfs, cleared on reboot |
| `/etc/secrets/initrd/` | LUKS unlock SSH keys | **BACKUP THIS** - needed for remote unlock |
| `/var/lib/veilid/` | Veilid node data | Veilid P2P state |

## Backup Strategy

### Critical Data to Backup

1. **Vaultwarden database**:
   ```bash
   ssh root@rusty-vault.de "tar -czf /tmp/vaultwarden-backup.tar.gz -C /var/lib/vaultwarden ."
   scp root@rusty-vault.de:/tmp/vaultwarden-backup.tar.gz ./backups/vaultwarden-$(date +%F).tar.gz
   ```

2. **SOPS Age key**:
   ```bash
   ssh root@rusty-vault.de "cat /var/lib/sops-nix/key.txt" > backups/age-key-$(date +%F).txt
   chmod 600 backups/age-key-$(date +%F).txt
   ```

3. **LUKS SSH keys**:
   ```bash
   ssh root@rusty-vault.de "tar -czf /tmp/initrd-keys.tar.gz /etc/secrets/initrd/"
   scp root@rusty-vault.de:/tmp/initrd-keys.tar.gz ./backups/initrd-keys-$(date +%F).tar.gz
   ```

4. **Miniflux PostgreSQL database**:
   ```bash
   ssh root@rusty-vault.de "sudo -u postgres pg_dump miniflux | gzip > /tmp/miniflux-db.sql.gz"
   scp root@rusty-vault.de:/tmp/miniflux-db.sql.gz ./backups/miniflux-db-$(date +%F).sql.gz
   ```

5. **Configuration files** (already in git):
   - `configuration.nix`
   - `secrets/secrets.yaml` (encrypted)
   - `.sops.yaml`

### Full Backup Script

```bash
#!/usr/bin/env bash
set -euo pipefail

SERVER="root@rusty-vault.de"
BACKUP_DIR="./backups/$(date +%F)"
mkdir -p "$BACKUP_DIR"

echo "Backing up to $BACKUP_DIR..."

# Vaultwarden
ssh "$SERVER" "tar -czf /tmp/vaultwarden.tar.gz -C /var/lib/vaultwarden ."
scp "$SERVER:/tmp/vaultwarden.tar.gz" "$BACKUP_DIR/"

# Age key
ssh "$SERVER" "cat /var/lib/sops-nix/key.txt" > "$BACKUP_DIR/age-key.txt"
chmod 600 "$BACKUP_DIR/age-key.txt"

# LUKS keys
ssh "$SERVER" "tar -czf /tmp/initrd-keys.tar.gz /etc/secrets/initrd/"
scp "$SERVER:/tmp/initrd-keys.tar.gz" "$BACKUP_DIR/"

# Miniflux database
ssh "$SERVER" "sudo -u postgres pg_dump miniflux | gzip > /tmp/miniflux-db.sql.gz"
scp "$SERVER:/tmp/miniflux-db.sql.gz" "$BACKUP_DIR/"

# Cleanup temp files on server
ssh "$SERVER" "rm /tmp/vaultwarden.tar.gz /tmp/initrd-keys.tar.gz /tmp/miniflux-db.sql.gz"

echo "Backup complete: $BACKUP_DIR"
```

## External Dependencies

### SOPS-nix

Fetched from GitHub at build time (unpinned):
```nix
builtins.fetchTarball {
  url = "https://github.com/Mic92/sops-nix/archive/master.tar.gz";
}
```

**Recommendation**: Pin to specific commit for reproducibility:
```nix
builtins.fetchTarball {
  url = "https://github.com/Mic92/sops-nix/archive/<commit-hash>.tar.gz";
  sha256 = "<sha256-hash>";
}
```

### Let's Encrypt (ACME)

- Certificates via `security.acme` module
- ECDSA P-384 certificates (smaller, faster than RSA)
- Auto-renewal via systemd timers
- Rate limits: 50 certificates per domain per week

### Syncthing Relay Pool

- Relay auto-registers with `https://relays.syncthing.net/endpoint`
- Listed in global relay pool as `rusty-vault.de`
- Clients automatically discover and use it

### Posteo SMTP

- SMTP server: `posteo.de:587`
- TLS: STARTTLS required
- Used for Vaultwarden email notifications
- Credentials in SOPS-encrypted secrets

### Quad9 DNS

- DNS-over-TLS: `9.9.9.9#dns.quad9.net`
- Fallback: `149.112.112.112#dns.quad9.net`
- Privacy-focused, malware filtering

### NTP Servers

- German NTP pool: `{0,1,2}.de.pool.ntp.org`
- Time sync via Chrony (not systemd-timesyncd)

## Development Workflow

### Local Testing (if applicable)

NixOS configurations can be tested in VMs:

```bash
# Build VM from configuration
nixos-rebuild build-vm -I nixos-config=./configuration.nix

# Run VM (requires commenting out hardware-specific parts)
./result/bin/run-nixos-vm
```

**Note**: Hardware-specific options must be disabled for VMs:
- LUKS configuration
- Network interface names
- Grub device

### Git Workflow

Current remote: `git@github.com:achimcc/nixos-hetzner-vps-config.git`

Typical workflow:
```bash
# Make changes to configuration.nix
vim configuration.nix

# Test build locally
nixos-rebuild build -I nixos-config=./configuration.nix

# Commit changes
git add configuration.nix
git commit -m "Describe changes"
git push

# Deploy to server
scp configuration.nix root@rusty-vault.de:/etc/nixos/
ssh root@rusty-vault.de "nixos-rebuild switch"
```

**Important**: Don't commit unencrypted secrets! Only commit `secrets/secrets.yaml` after SOPS encryption.

## Code Conventions

### Nix Style

- **Indentation**: 2 spaces (not tabs)
- **Attribute sets**: Multi-line with trailing semicolon
  ```nix
  services.vaultwarden = {
    enable = true;
    config = {
      DOMAIN = "https://rusty-vault.de";
    };
  };
  ```
- **Lists**: One item per line for readability
  ```nix
  allowedTCPPorts = [
    22      # SSH
    80      # HTTP
    443     # HTTPS
  ];
  ```
- **Comments**: German in current config (historical), but English is fine
- **Section headers**: Use ASCII art dividers for major sections
  ```nix
  # ============================================================================
  # SECTION NAME
  # ============================================================================
  ```

### Configuration Organization

File is organized by topic:
1. Imports & SOPS setup
2. Security hardening (kernel, users)
3. SSH hardening
4. Bootloader & remote unlock
5. System settings
6. Services (Syncthing, Veilid, Miniflux, Vaultwarden)
7. NGINX reverse proxy
8. ACME/TLS
9. Firewall
10. Audit & logging
11. Additional security (AppArmor, DNS-over-TLS, etc.)

When adding new services, insert in the "Services" section, not at the end.

### Naming Conventions

- Service options: Follow upstream NixOS module naming
- Secrets: Use underscores (`smtp_password`, not `smtp-password`)
- File paths: Absolute paths for clarity (`/var/lib/...`, not relative)
- Port numbers: Add comments explaining purpose

## Known Issues

### ACME `badNonce` Errors

**Status**: Ongoing, intermittent  
**Cause**: Let's Encrypt API timing issue  
**Workaround**: Retry `systemctl start acme-rusty-vault.de`  
**Permanent fix**: None (upstream issue)

### Veilid Not Starting on First Boot

**Status**: Rare  
**Symptom**: `systemctl status veilid` shows failed  
**Workaround**: `systemctl restart veilid`  
**Root cause**: Unknown, possibly ordering issue

### Syncthing Relay Taking Hours to Register

**Status**: Expected behavior  
**Symptom**: Relay not showing in pool immediately  
**Expected**: Can take 2-6 hours for initial registration  
**Check**: `journalctl -u syncthing-relay` for registration messages

## External Resources

- **NixOS Manual**: https://nixos.org/manual/nixos/stable/
- **NixOS Options Search**: https://search.nixos.org/options
- **SOPS-nix Documentation**: https://github.com/Mic92/sops-nix
- **Vaultwarden Wiki**: https://github.com/dani-garcia/vaultwarden/wiki
- **Syncthing Relay**: https://docs.syncthing.net/users/strelaysrv.html
- **Veilid**: https://veilid.com/
- **Hetzner Docs**: https://docs.hetzner.com/

## Quick Reference

### Most Common Tasks

```bash
# Deploy config change
scp configuration.nix root@rusty-vault.de:/etc/nixos/ && ssh root@rusty-vault.de "nixos-rebuild switch"

# Check all service status
ssh root@rusty-vault.de "systemctl status vaultwarden miniflux nginx syncthing-relay veilid"

# View Vaultwarden logs
ssh root@rusty-vault.de "journalctl -u vaultwarden -f"

# View Miniflux logs
ssh root@rusty-vault.de "journalctl -u miniflux -f"

# Renew certificate manually
ssh root@rusty-vault.de "systemctl start acme-rusty-vault.de"

# Update secrets
sops secrets/secrets.yaml
scp secrets/secrets.yaml root@rusty-vault.de:/etc/nixos/secrets/
ssh root@rusty-vault.de "nixos-rebuild switch"

# Check banned IPs
ssh root@rusty-vault.de "fail2ban-client banned"
```

### Emergency Commands

```bash
# Stop all services
ssh root@rusty-vault.de "systemctl stop vaultwarden miniflux nginx syncthing-relay veilid"

# Disable firewall (temporary)
ssh root@rusty-vault.de "systemctl stop firewall"

# Rollback to previous generation
ssh root@rusty-vault.de "nixos-rebuild switch --rollback"

# Boot into previous generation
ssh root@rusty-vault.de "reboot"
# At boot, select previous generation from GRUB menu
```
