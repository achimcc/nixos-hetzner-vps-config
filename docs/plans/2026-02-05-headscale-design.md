# Headscale Installation Design

**Date**: 2026-02-05
**Purpose**: Add Headscale as a self-hosted Tailscale coordination server for personal VPN mesh network

## Overview

Headscale is an open-source implementation of the Tailscale control server. This design adds Headscale to the existing NixOS VPS configuration to create a personal VPN mesh network connecting personal devices (laptops, phones, home servers) securely.

## Requirements

- Self-hosted Tailscale control server
- Web UI for easier management (headscale-ui)
- Public HTTPS access at `headscale.rusty-vault.de`
- Integration with existing security hardening
- Use Tailscale's default network range (100.64.0.0/10)

## Architecture

### Components

| Component | Location | Purpose |
|-----------|----------|---------|
| Headscale | 127.0.0.1:8085 | Control server (coordination) |
| headscale-ui | Static files via NGINX | Web management interface |
| NGINX | 443 (HTTPS) | Reverse proxy with TLS |
| SQLite | /var/lib/headscale/db.sqlite | Data storage |
| STUN | 0.0.0.0:3478 (UDP) | NAT traversal |

### Network Flow

```
Client Device (Tailscale)
    ↓
HTTPS (headscale.rusty-vault.de)
    ↓
NGINX (TLS termination + security)
    ↓
Headscale (127.0.0.1:8085)
    ↓
SQLite Database

STUN traffic: Direct UDP:3478
DERP relay: Tailscale public DERP servers
```

## Configuration

### Headscale Settings

```yaml
server_url: https://headscale.rusty-vault.de
listen_addr: 0.0.0.0:8085
ip_prefixes:
  - 100.64.0.0/10      # IPv4 (Tailscale default)
  - fd7a:115c:a1e0::/48 # IPv6
database: SQLite (/var/lib/headscale/db.sqlite)
derp: Use Tailscale's public DERP map
stun: Built-in on UDP:3478
```

### DNS Requirements

Add these DNS A records to your domain registrar:
- `headscale.rusty-vault.de` → VPS IP address
- `headscale-ui.rusty-vault.de` → VPS IP address

**Note**: These are added at your domain registrar (not Hetzner console unless they manage your DNS for rusty-vault.de).

### Security

- Headscale API accessible only via NGINX reverse proxy
- TLS with Let's Encrypt (ACME)
- Same security headers as other services (HSTS, X-Frame-Options, CSP, etc.)
- Rate limiting on NGINX endpoints (10 req/s, burst 20)
- API key for headscale-ui stored in SOPS secrets
- User registration controlled (no open registration)
- Integrated with existing fail2ban, AppArmor, audit logging

### Firewall Changes

Add to `allowedUDPPorts`:
- 3478 (STUN for NAT traversal)

## Implementation Steps

### 1. DNS Configuration

Add DNS A records at your domain registrar:
```
headscale.rusty-vault.de    → <VPS_IP>
headscale-ui.rusty-vault.de → <VPS_IP>
```

### 2. Generate API Key

```bash
openssl rand -base64 32
```

### 3. Create SOPS Secret

Create `secrets/headscale.yaml`:
```yaml
headscale_api_key: '<generated-api-key>'
```

Encrypt it:
```bash
sops -e -i secrets/headscale.yaml
```

### 4. Update configuration.nix

Add the following sections:

#### SOPS Secret Declaration
```nix
sops.secrets.headscale_api_key = {
  sopsFile = ./secrets/headscale.yaml;
  mode = "0400";
};
```

#### Headscale Service
```nix
services.headscale = {
  enable = true;
  address = "127.0.0.1";
  port = 8085;

  settings = {
    server_url = "https://headscale.rusty-vault.de";
    listen_addr = "0.0.0.0:8085";
    metrics_listen_addr = "127.0.0.1:9090";

    ip_prefixes = [
      "100.64.0.0/10"
      "fd7a:115c:a1e0::/48"
    ];

    derp = {
      urls = [
        "https://controlplane.tailscale.com/derpmap/default"
      ];
      auto_update_enabled = true;
      update_frequency = "24h";
    };

    database = {
      type = "sqlite3";
      sqlite.path = "/var/lib/headscale/db.sqlite";
    };

    unix_socket = "/var/run/headscale/headscale.sock";
    unix_socket_permission = "0770";
  };
};
```

#### NGINX Virtual Hosts
```nix
virtualHosts."headscale.rusty-vault.de" = {
  enableACME = true;
  forceSSL = true;

  extraConfig = ''
    limit_req zone=general burst=20 nodelay;
    limit_conn addr 10;

    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
  '';

  locations."/" = {
    proxyPass = "http://127.0.0.1:8085";
    proxyWebsockets = true;
    extraConfig = ''
      proxy_hide_header X-Powered-By;
      proxy_hide_header Server;
    '';
  };
};

virtualHosts."headscale-ui.rusty-vault.de" = {
  enableACME = true;
  forceSSL = true;

  root = "${pkgs.headscale-ui}";

  extraConfig = ''
    limit_req zone=general burst=20 nodelay;
    limit_conn addr 10;

    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
  '';

  locations."/" = {
    tryFiles = "$uri $uri/ /index.html";
  };

  locations."/web/" = {
    proxyPass = "http://127.0.0.1:8085";
    proxyWebsockets = true;
  };
};
```

#### Firewall
```nix
networking.firewall = {
  allowedUDPPorts = [
    3478  # Headscale STUN
  ];
};
```

#### Environment Packages (optional)
```nix
environment.systemPackages = with pkgs; [
  headscale  # Makes CLI available
];
```

### 5. Deploy Configuration

```bash
# Copy files to server
scp secrets/headscale.yaml root@<server>:/etc/nixos/secrets/

# Deploy
ssh root@<server> "nixos-rebuild switch"
```

### 6. Create Initial User

```bash
ssh root@<server>
headscale users create <username>
```

### 7. Generate Pre-Auth Key

```bash
headscale preauthkeys create --user <username> --reusable --expiration 24h
```

## Client Setup

### Install Tailscale Client

On each device you want to connect:

**Linux:**
```bash
# Install via package manager
# Debian/Ubuntu: apt install tailscale
# Arch: pacman -S tailscale
```

**macOS:**
```bash
brew install tailscale
```

**Windows/iOS/Android:**
Download from https://tailscale.com/download

### Connect to Headscale

```bash
tailscale up --login-server=https://headscale.rusty-vault.de
```

Follow the authentication flow (use pre-auth key if prompted).

### Verify Connection

```bash
tailscale status
tailscale ping <another-device>
```

## Management

### CLI Commands

```bash
# List users
headscale users list

# List connected nodes
headscale nodes list

# Create pre-auth key
headscale preauthkeys create --user <username> --reusable --expiration 24h

# Remove node
headscale nodes delete --identifier <node-id>

# List routes
headscale routes list
```

### Web UI

Access at `https://headscale-ui.rusty-vault.de`

Features:
- View all connected nodes
- View users
- View routes
- Monitor connection status

Configure API endpoint in web UI:
- API URL: `https://headscale.rusty-vault.de`
- API Key: (from SOPS secret)

### Logs

```bash
# Service logs
journalctl -u headscale -f

# Check status
systemctl status headscale
```

## Testing Checklist

- [ ] DNS records propagated (`dig headscale.rusty-vault.de`)
- [ ] Headscale service running (`systemctl status headscale`)
- [ ] HTTPS endpoints accessible (browser test)
- [ ] User created successfully
- [ ] Pre-auth key generated
- [ ] First device registered via Tailscale client
- [ ] Device shows in `headscale nodes list`
- [ ] Second device can ping first device via VPN IPs
- [ ] Web UI accessible and shows nodes
- [ ] STUN port open (`ss -ulnp | grep 3478`)

## Troubleshooting

### Device Won't Register

```bash
# Check Headscale logs
journalctl -u headscale -f

# Verify DNS resolves
dig headscale.rusty-vault.de

# Test HTTPS endpoint
curl https://headscale.rusty-vault.de
```

### Devices Can't Connect

```bash
# Check STUN port
ss -ulnp | grep 3478

# Check firewall
iptables -L -n | grep 3478

# Verify DERP map
headscale derp list
```

### Web UI Won't Connect

```bash
# Check API key in secrets
cat /run/secrets/headscale_api_key

# Verify NGINX proxy
curl -H "Authorization: Bearer <api-key>" http://127.0.0.1:8085/api/v1/node
```

## Backup Considerations

Important files to backup:
- `/var/lib/headscale/db.sqlite` - User and node database
- `/var/lib/headscale/private.key` - Server private key
- `/etc/nixos/secrets/headscale.yaml` - API key (SOPS encrypted)

```bash
# Create backup
ssh root@<server> "tar -czf /tmp/headscale-backup.tar.gz \
  /var/lib/headscale"
scp root@<server>:/tmp/headscale-backup.tar.gz ./
```

## Future Enhancements

- Custom DERP relay server (reduce latency, no third-party)
- Exit node configuration (route internet through VPS)
- Subnet routing (access home network from VPN)
- ACL policies (control which devices can communicate)
- OIDC integration (use external identity provider)

## References

- [Headscale Documentation](https://headscale.net/)
- [Tailscale Documentation](https://tailscale.com/kb/)
- [NixOS Headscale Module](https://search.nixos.org/options?query=services.headscale)
- [headscale-ui GitHub](https://github.com/gurucomputing/headscale-ui)
