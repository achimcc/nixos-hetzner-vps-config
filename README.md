# NixOS Hetzner VPS - Vaultwarden Server

Hardened NixOS configuration for a self-hosted Vaultwarden password manager on a Hetzner VPS.

## Features

- **Vaultwarden** - Self-hosted Bitwarden-compatible password manager
- **Syncthing Relay** - Public relay server for Syncthing file synchronization
- **NGINX** - Reverse proxy with Let's Encrypt TLS
- **SOPS-nix** - Encrypted secrets using Age encryption
- **LUKS** - Full disk encryption with remote SSH unlock
- **Security Hardening** - Comprehensive system hardening

## Components

| Service | Port | Description |
|---------|------|-------------|
| Vaultwarden | 8222 (internal) | Password Manager |
| Syncthing Relay | 22067 | Relay server for Syncthing clients |
| Syncthing Status | 22070 (internal) | Relay status API |
| NGINX | 80, 443 | Reverse Proxy + TLS |
| SSH | 22 | Administration |

## Prerequisites

- Hetzner VPS running NixOS
- Domain with DNS pointing to server IP
- Local tools: `sops`, `age`

## Structure

```
.
├── configuration.nix          # Main configuration
├── hardware-configuration.nix
├── secrets/
│   └── secrets.yaml           # Encrypted credentials (SOPS)
├── .sops.yaml                 # SOPS configuration
└── README.md
```

## Installation

### 1. Clone Repository

```bash
git clone <repo-url>
cd nixos-hetzner-vps-config
```

### 2. Create Age Key on Server

```bash
ssh root@<server> "mkdir -p /var/lib/sops-nix && \
  nix-shell -p age --run 'age-keygen -o /var/lib/sops-nix/key.txt' && \
  chmod 600 /var/lib/sops-nix/key.txt && \
  cat /var/lib/sops-nix/key.txt"
```

Note the public key (`age1...`).

### 3. Configure SOPS

Update `.sops.yaml` with the public key:

```yaml
keys:
  - &server age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
creation_rules:
  - path_regex: secrets/.*\.yaml$
    key_groups:
      - age:
          - *server
```

### 4. Create Secrets

```bash
# Create plaintext
cat > secrets/secrets.yaml << 'EOF'
smtp_password: 'SMTP_PASSWORD=your-password-here'
EOF

# Encrypt
sops -e -i secrets/secrets.yaml
```

**Note:** Backslashes in passwords must be doubled (`\` → `\\`).

### 5. Customize Configuration

Edit `configuration.nix`:
- Domain (`rusty-vault.de`)
- Email addresses
- SSH public keys
- SMTP settings

### 6. Deploy

```bash
# Copy files to server
scp -r configuration.nix secrets/ .sops.yaml root@<server>:/etc/nixos/

# Activate configuration
ssh root@<server> "nixos-rebuild switch"
```

## Security Hardening

### Kernel

- ASLR (Address Space Layout Randomization)
- Kernel pointers hidden (`kptr_restrict=2`)
- ptrace protection (`yama.ptrace_scope=2`)
- BPF JIT hardening
- Unused kernel modules blacklisted

### Network

- ICMP/IP redirects disabled
- Source routing blocked
- SYN cookies enabled
- Reverse path filtering
- TCP timestamps disabled

### SSH

- Key-only authentication
- Strong cryptography (Curve25519, ChaCha20-Poly1305)
- X11/Agent/TCP forwarding disabled
- MaxAuthTries=3

### Firewall

- Only ports 22, 80, 443 open
- SYN flood protection
- ICMP rate limiting
- Logging for refused connections

### NGINX

- Security headers (HSTS, X-Frame-Options, etc.)
- Rate limiting (10 req/s)
- Server version hidden
- TLS 1.2+ with strong cipher suites

### Additional

- **Fail2ban** - Brute-force protection
- **AppArmor** - Mandatory Access Control
- **Auditd** - Security event logging
- **DNS-over-TLS** - Encrypted DNS queries (Quad9)
- **Chrony** - Secure time synchronization
- **Auto-updates** - Daily security updates

## Users

| User | Purpose |
|------|---------|
| `root` | Emergency/LUKS unlock (SSH key) |
| `admin` | Daily administration (sudo) |

Login:
```bash
ssh admin@<server>
sudo -i  # Root shell
```

## Syncthing Relay

The server runs a public Syncthing relay that helps Syncthing clients connect when direct connections aren't possible.

### Status

Check relay status:
```bash
# Via NGINX (HTTPS)
curl https://rusty-vault.de/relay-status

# Direct on server
curl http://localhost:22070/status
```

### Configuration

The relay is registered in the global Syncthing relay pool. Clients will automatically discover and use it.

Current settings:
- **Port**: 22067
- **Provider**: rusty-vault.de
- **Rate Limit**: Unlimited

### Logs

```bash
journalctl -u syncthing-relay -f
```

## Maintenance

### Updates

Automatic updates are enabled (04:00 daily). Manual update:

```bash
ssh root@<server> "nixos-rebuild switch --upgrade"
```

### Check Logs

```bash
# Vaultwarden
journalctl -u vaultwarden -f

# Fail2ban
fail2ban-client status sshd

# Audit log
ausearch -k logins
```

### Rotate Secrets

```bash
# Edit locally (requires server key or your own key)
sops secrets/secrets.yaml

# Deploy to server
scp secrets/secrets.yaml root@<server>:/etc/nixos/secrets/
ssh root@<server> "nixos-rebuild switch"
```

## Troubleshooting

### SMTP Not Working

```bash
# Check password
ssh root@<server> "cat /run/secrets/smtp_password"

# Vaultwarden logs
journalctl -u vaultwarden | grep -i smtp
```

### SSH Access Lost

1. Boot Hetzner rescue system
2. Unlock LUKS partition
3. Repair configuration

### ACME/TLS Errors

```bash
# Certificate status
systemctl status acme-rusty-vault.de

# Manual renewal
systemctl start acme-rusty-vault.de
```

## Backup

Important data:
- `/var/lib/vaultwarden/` - Vaultwarden database
- `/var/lib/sops-nix/key.txt` - Age private key
- `/etc/secrets/initrd/` - LUKS unlock SSH keys

```bash
# Create backup
ssh root@<server> "tar -czf /tmp/backup.tar.gz \
  /var/lib/vaultwarden \
  /var/lib/sops-nix/key.txt"
scp root@<server>:/tmp/backup.tar.gz ./
```

## License

MIT
