# NixOS Hetzner VPS - Multi-Service Server

Hardened, modular NixOS flake configuration for self-hosted services on a Hetzner VPS.

## Features

- **Vaultwarden** - Self-hosted Bitwarden-compatible password manager
- **Miniflux** - Lightweight RSS/Atom feed reader
- **PrivateBin** - Encrypted pastebin service
- **Ghostfolio** - Privacy-focused wealth management (Podman container)
- **SimpleLogin** - Email aliasing and privacy protection (Podman container)
- **Syncthing Relay** - Public relay server for Syncthing file synchronization
- **Veilid** - Privacy-focused distributed network node
- **Postfix** - Mail server for service notifications
- **NGINX** - Reverse proxy with Let's Encrypt TLS and modular vhost configuration
- **SOPS-nix** - Encrypted secrets using Age encryption
- **LUKS** - Full disk encryption with remote SSH unlock
- **Security Hardening** - Comprehensive system hardening
- **Modular Architecture** - Clean separation of concerns with reusable components

## Components

| Service | Domain/Port | Description |
|---------|-------------|-------------|
| Vaultwarden | rusty-vault.de | Password Manager |
| Miniflux | miniflux.rusty-vault.de | RSS Feed Reader |
| PrivateBin | privatebin.rusty-vault.de | Encrypted Pastebin |
| Ghostfolio | ghostfolio.rusty-vault.de | Wealth Management (Podman) |
| SimpleLogin | simplelogin.rusty-vault.de | Email Aliasing (Podman) |
| Syncthing Relay | 22067 | Relay server for Syncthing clients |
| Syncthing Status | rusty-vault.de/relay-status | Relay status API |
| Veilid | 5150/TCP, 5150/UDP | Privacy Network Node |
| Postfix | mail.rusty-vault.de | SMTP Mail Server |
| NGINX | 80, 443 | Reverse Proxy + TLS |
| SSH | 22 | Administration |

## Prerequisites

- Hetzner VPS running NixOS
- Domain with DNS pointing to server IP (rusty-vault.de)
- Subdomains for services (miniflux, ghostfolio, privatebin, simplelogin, mail)
- Local tools: `nix` (with flakes enabled), `sops`, `age`

## Structure

```
.
├── flake.nix                  # Flake definition with deployment command
├── configuration.nix          # Main configuration (39 lines!)
├── hardware-configuration.nix
├── lib/
│   └── default.nix           # Custom helper functions (mkProxiedService, etc.)
├── modules/
│   ├── secrets.nix           # SOPS secrets configuration
│   ├── common/               # Core system modules
│   │   ├── security-hardening.nix
│   │   ├── users.nix
│   │   ├── networking.nix
│   │   ├── boot.nix
│   │   ├── base-packages.nix
│   │   ├── ssh.nix
│   │   └── firewall.nix
│   └── services/
│       ├── nginx/
│       │   ├── default.nix   # NGINX base configuration
│       │   └── vhosts.nix    # Virtual host definitions
│       ├── vaultwarden.nix
│       ├── miniflux.nix
│       ├── privatebin.nix
│       ├── syncthing-relay.nix
│       ├── veilid.nix
│       ├── mail/
│       │   └── postfix.nix
│       ├── monitoring/
│       │   └── fail2ban.nix
│       └── containers/
│           ├── podman.nix
│           ├── ghostfolio.nix
│           └── simplelogin.nix
├── secrets/
│   └── secrets.yaml          # Encrypted credentials (SOPS)
└── .sops.yaml                # SOPS configuration
```

## Architecture

### Modular Design

The configuration is highly modular with only **39 lines** in the main `configuration.nix`. Each service is isolated in its own module with clear dependencies.

### Custom Library Functions

The `lib/default.nix` provides reusable helpers:

- `mkProxiedService` - Create NGINX virtual hosts with TLS and proxy settings
- `mkContainerVhost` - Virtual hosts for Podman containers
- `mkStaticVhost` - Serve static files
- `commonVhostSettings` - Shared NGINX security headers and settings

Example:
```nix
services.nginx.virtualHosts = customLib.mkProxiedService {
  domain = commonConfig.services.vaultwarden;
  proxyPass = "http://localhost:8222";
};
```

### Centralized Configuration

All domains and settings are defined in `flake.nix` under `commonConfig`:
```nix
commonConfig = {
  domain = "rusty-vault.de";
  adminEmail = "achim.schneider@posteo.de";
  services = {
    vaultwarden = "rusty-vault.de";
    ghostfolio = "ghostfolio.rusty-vault.de";
    # ... etc
  };
};
```

This makes it easy to change domains and email addresses in one place.

## Quick Start

Already have a NixOS server with SOPS configured? Deploy in one command:

```bash
# Clone and deploy
git clone <repo-url>
cd nixos-hetzner-vps-config

# Customize configuration
vim flake.nix  # Update commonConfig with your domains/email

# Deploy
nix run
```

For detailed setup from scratch, see [Installation](#installation) below.

## Installation

### 1. Enable Flakes

On your local machine and server, enable Nix flakes:

```bash
# Add to /etc/nixos/configuration.nix
nix.settings.experimental-features = [ "nix-command" "flakes" ];

# Or temporarily
export NIX_CONFIG="experimental-features = nix-command flakes"
```

### 2. Clone Repository

```bash
git clone <repo-url>
cd nixos-hetzner-vps-config
```

### 3. Create Age Key on Server

```bash
ssh root@<server> "mkdir -p /var/lib/sops-nix && \
  nix-shell -p age --run 'age-keygen -o /var/lib/sops-nix/key.txt' && \
  chmod 600 /var/lib/sops-nix/key.txt && \
  cat /var/lib/sops-nix/key.txt"
```

Note the public key (`age1...`).

### 4. Configure SOPS

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

### 5. Create Secrets

```bash
# Create plaintext
cat > secrets/secrets.yaml << 'EOF'
smtp_password: 'SMTP_PASSWORD=your-password-here'
EOF

# Encrypt
sops -e -i secrets/secrets.yaml
```

**Note:** Backslashes in passwords must be doubled (`\` → `\\`).

### 6. Customize Configuration

Edit `flake.nix` to customize the `commonConfig` section:
- Main domain (`rusty-vault.de`)
- Admin email address
- Service subdomains (vaultwarden, miniflux, etc.)
- Email domain for SimpleLogin

Also update:
- SSH public keys in `modules/common/users.nix`
- SMTP settings in service modules (if needed)

### 7. Deploy

The project includes a custom deployment command `nrs` (NixOS Rebuild Switch) that handles everything:

```bash
# One-command deployment
nix run

# Or with explicit flake path
nix run .#nrs

# Customize server (defaults to root@rusty-vault.de)
NRS_SERVER=root@your-server.com nix run
```

The `nrs` command will:
- Warn about uncommitted changes
- Copy the flake to the server (excluding .git, .worktrees, etc.)
- Run `nixos-rebuild switch --flake .#nixos-server`
- Show success/failure status with helpful verification commands

**Manual deployment** (if needed):
```bash
# Copy files to server
rsync -av --exclude='.git' --exclude='.worktrees' . root@<server>:/etc/nixos/

# Activate configuration
ssh root@<server> "cd /etc/nixos && nixos-rebuild switch --flake .#nixos-server"
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

## Services

### Vaultwarden (Password Manager)

Self-hosted Bitwarden-compatible password manager.

- **Domain**: rusty-vault.de
- **Features**: Full Bitwarden compatibility, web vault, browser extensions
- **Admin**: Access at rusty-vault.de/admin

### Miniflux (RSS Reader)

Lightweight, fast RSS/Atom feed reader.

- **Domain**: miniflux.rusty-vault.de
- **Database**: PostgreSQL
- **Features**: Keyboard shortcuts, fever API, integration support

### PrivateBin (Encrypted Pastebin)

Zero-knowledge encrypted pastebin service.

- **Domain**: privatebin.rusty-vault.de
- **Storage**: Filesystem-based
- **Features**: Client-side encryption, burn after reading, password protection

### Ghostfolio (Wealth Management)

Privacy-focused portfolio tracker (runs in Podman container).

- **Domain**: ghostfolio.rusty-vault.de
- **Container**: ghcr.io/ghostfolio/ghostfolio:latest
- **Features**: Asset tracking, performance metrics, privacy-first

### SimpleLogin (Email Aliasing)

Email aliasing service for privacy protection (runs in Podman container).

- **Domain**: simplelogin.rusty-vault.de
- **Email Domain**: sl.rusty-vault.de
- **Container**: simplelogin/app:latest
- **Features**: Unlimited aliases, PGP encryption, custom domains

### Veilid (Privacy Network)

Privacy-focused distributed network node.

- **Ports**: 5150/TCP, 5150/UDP
- **Purpose**: Contribute to the Veilid privacy network
- **Features**: Distributed routing, end-to-end encryption

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
# Using nrs (updates flake inputs)
nix flake update && nix run

# Or manually on server
ssh root@<server> "cd /etc/nixos && nix flake update && nixos-rebuild switch --flake .#nixos-server"
```

### Check Logs

```bash
# Services
journalctl -u vaultwarden -f
journalctl -u miniflux -f
journalctl -u privatebin -f
journalctl -u syncthing-relay -f
journalctl -u veilid -f

# Containers
ssh root@<server> "podman logs -f ghostfolio"
ssh root@<server> "podman logs -f simplelogin"

# Security
fail2ban-client status sshd
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

### Deployment Fails

```bash
# Check flake syntax
nix flake check

# Test build locally (fast)
nix build .#nixosConfigurations.nixos-server.config.system.build.toplevel

# Check uncommitted changes
git status
```

### Container Not Starting

```bash
# Check container status
ssh root@<server> "podman ps -a"

# View container logs
ssh root@<server> "podman logs ghostfolio"
ssh root@<server> "podman logs simplelogin"

# Restart container
ssh root@<server> "systemctl restart podman-ghostfolio"
```

### Service Fails to Start

```bash
# Check service status
ssh root@<server> "systemctl status vaultwarden"
ssh root@<server> "systemctl status miniflux"

# View detailed logs
ssh root@<server> "journalctl -u miniflux -xe"
```

### SMTP Not Working

```bash
# Check password
ssh root@<server> "cat /run/secrets/smtp_password"

# Vaultwarden logs
journalctl -u vaultwarden | grep -i smtp

# Test Postfix
ssh root@<server> "systemctl status postfix"
```

### Database Issues (Miniflux, Ghostfolio)

```bash
# Check PostgreSQL
ssh root@<server> "systemctl status postgresql"

# Miniflux database migration
ssh root@<server> "sudo -u miniflux miniflux -migrate"

# SimpleLogin database
ssh root@<server> "podman exec simplelogin flask db upgrade"
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

# Check all certificates
systemctl list-units 'acme-*'
```

## Backup

Important data:
- `/var/lib/vaultwarden/` - Vaultwarden database
- `/var/lib/miniflux/` - Miniflux database
- `/var/lib/privatebin/` - PrivateBin data
- `/var/lib/ghostfolio/` - Ghostfolio database (Podman volume)
- `/var/lib/simplelogin/` - SimpleLogin data (Podman volumes)
- `/var/lib/sops-nix/key.txt` - Age private key
- `/etc/secrets/initrd/` - LUKS unlock SSH keys

```bash
# Create backup
ssh root@<server> "tar -czf /tmp/backup.tar.gz \
  /var/lib/vaultwarden \
  /var/lib/miniflux \
  /var/lib/privatebin \
  /var/lib/ghostfolio \
  /var/lib/simplelogin \
  /var/lib/sops-nix/key.txt"
scp root@<server>:/tmp/backup.tar.gz ./
```

## Development

### Adding a New Service

1. Create a module in `modules/services/`:
   ```nix
   { config, lib, commonConfig, customLib, ... }:
   {
     services.myservice = {
       enable = true;
       # ... configuration
     };

     services.nginx.virtualHosts = customLib.mkProxiedService {
       domain = commonConfig.services.myservice;
       proxyPass = "http://localhost:8080";
     };
   }
   ```

2. Add the module to `configuration.nix`:
   ```nix
   imports = [
     ./modules/services/myservice.nix
   ];
   ```

3. Add domain to `flake.nix` under `commonConfig.services`

4. Deploy: `nix run`

### Git Worktrees

The project uses git worktrees for isolated feature development:

```bash
# Create worktree for new feature
git worktree add .worktrees/add-newservice -b add-newservice

# Work in isolation
cd .worktrees/add-newservice
# ... make changes, test deploy ...

# Merge when ready
cd ../..
git merge add-newservice
git worktree remove .worktrees/add-newservice
```

Worktrees are automatically excluded from `nrs` deployments.

### Testing Changes

```bash
# Check flake
nix flake check

# Build locally (without deploying)
nix build .#nixosConfigurations.nixos-server.config.system.build.toplevel

# Format code
nix fmt

# Deploy to test server
NRS_SERVER=root@test-server.com nix run
```

## Contributing

Contributions welcome. This is a personal server configuration but the modular structure makes it easy to adapt for your own use.

Key principles:
- Keep modules focused and single-purpose
- Use `customLib` for reusable patterns
- Centralize configuration in `flake.nix`
- Document new services in README

## License

MIT
