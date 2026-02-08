# SimpleLogin Installation Design

**Date:** 2026-02-08
**Target:** simplelogin.rusty-vault.de / @sl.rusty-vault.de
**Status:** Approved

## Overview

Install and configure SimpleLogin as a self-hosted email alias service on the NixOS VPS using Podman containers. SimpleLogin allows creating unlimited email aliases that forward to real mailboxes, protecting privacy and reducing spam.

## Requirements

- **Web-App Domain:** simplelogin.rusty-vault.de
- **Email Alias Domain:** @sl.rusty-vault.de
- **Deployment:** Podman containers via NixOS `virtualisation.oci-containers`
- **Email Server:** Full mail server with Postfix (Port 25 for receiving emails)
- **Database:** PostgreSQL 15 in Podman container
- **Cache:** Redis 7 in Podman container
- **Features:** All Premium features enabled (unlimited aliases, custom domains, etc.)
- **Components:** Minimal stack (SimpleLogin + PostgreSQL + Redis + Postfix)

## Architecture

### Container Stack

The SimpleLogin stack consists of 3 Podman containers:

1. **simplelogin-app** - Main application (Web + Email handler)
   - Image: `simplelogin/app:latest`
   - Port: 127.0.0.1:7777 (HTTP for NGINX reverse proxy)
   - Volumes: `/var/lib/simplelogin/{data,upload,dkim}`

2. **simplelogin-postgres** - PostgreSQL database
   - Image: `postgres:15-alpine`
   - Port: 127.0.0.1:5432 (internal only)
   - Volume: `/var/lib/simplelogin/postgres`

3. **simplelogin-redis** - Redis for jobs/cache
   - Image: `redis:7-alpine`
   - Port: 127.0.0.1:6379 (internal only)
   - Volume: `/var/lib/simplelogin/redis`

All containers run in the same Podman network (`simplelogin-net`) for internal communication.

### Email Flow

**Incoming Emails** (`someone@example.com` → `alias@sl.rusty-vault.de` → `your-real@email.com`):
1. Email arrives at Postfix (Port 25)
2. Postfix forwards to SimpleLogin (via Unix socket or TCP)
3. SimpleLogin decrypts alias, anonymizes headers
4. SimpleLogin forwards to real mailbox

**Outgoing Emails** (`your-real@email.com` → SimpleLogin → `recipient@example.com` with `alias@sl.rusty-vault.de` as sender):
1. Send to `reply+<token>@sl.rusty-vault.de`
2. SimpleLogin receives, replaces sender with alias
3. SimpleLogin sends via Postfix to final recipient

### Network Diagram

```
Internet
  ↓
Port 25 (SMTP) ────→ Postfix ────→ SimpleLogin Container
  ↓                                    ↓
Port 443 (HTTPS) ─→ NGINX ─→ SimpleLogin Container
                                       ↓
                              PostgreSQL Container
                                       ↓
                                Redis Container
```

## DNS Configuration

### Required DNS Records (at domain registrar)

**For Web-App:**
- `A` Record: `simplelogin.rusty-vault.de` → `77.42.71.141`
- `AAAA` Record: `simplelogin.rusty-vault.de` → `<VPS-IPv6>` (optional)

**For Email (@sl.rusty-vault.de):**
- `A` Record: `mail.rusty-vault.de` → `77.42.71.141`
- `MX` Record: `sl.rusty-vault.de` → `mail.rusty-vault.de` (Priority 10)
- `TXT` Record (SPF): Name: `sl`, Value: `v=spf1 mx ~all`
- `TXT` Record (DMARC): Name: `_dmarc.sl`, Value: `v=DMARC1; p=quarantine; rua=mailto:postmaster@sl.rusty-vault.de`
- `TXT` Record (DKIM): Name: `dkim._domainkey.sl`, Value: `<generated after installation>`

### DNS Entry Examples for Hetzner

```
Type: A
Name: simplelogin
Value: 77.42.71.141

Type: A
Name: mail
Value: 77.42.71.141

Type: MX
Name: sl
Value: mail.rusty-vault.de
Priority: 10

Type: TXT
Name: sl
Value: v=spf1 mx ~all

Type: TXT
Name: _dmarc.sl
Value: v=DMARC1; p=quarantine; rua=mailto:postmaster@sl.rusty-vault.de

Type: TXT (added AFTER installation)
Name: dkim._domainkey.sl
Value: v=DKIM1; k=rsa; p=<public-key-from-simplelogin>
```

## Secrets Management

### SOPS Secrets File

Create `secrets/simplelogin.yaml`:

```yaml
# PostgreSQL
simplelogin_db_password: '<strong-password>'

# Flask Secret Key (for sessions)
simplelogin_flask_secret: '<random-64-chars>'

# Email Encryption (for stored email contents)
simplelogin_email_secret: '<random-32-chars>'

# DKIM Private Key (generated after installation)
simplelogin_dkim_private_key: |
  -----BEGIN RSA PRIVATE KEY-----
  ... added later ...
  -----END RSA PRIVATE KEY-----

# Optional: Postmark/AWS SES for better deliverability (can be added later)
simplelogin_postmark_api_key: ''
```

### Generate Secrets

```bash
# Flask Secret (64 chars)
openssl rand -hex 32

# DB Password (32 chars)
openssl rand -hex 16

# Email Secret (32 chars)
openssl rand -hex 16
```

### NixOS SOPS Configuration

```nix
sops.secrets = {
  simplelogin_db_password = {
    sopsFile = ./secrets/simplelogin.yaml;
    mode = "0400";
  };
  simplelogin_flask_secret = {
    sopsFile = ./secrets/simplelogin.yaml;
    mode = "0400";
  };
  simplelogin_email_secret = {
    sopsFile = ./secrets/simplelogin.yaml;
    mode = "0400";
  };
};
```

## NixOS Configuration

### Enable Podman

```nix
virtualisation.podman = {
  enable = true;
  dockerCompat = false;  # We use native Podman, not Docker compatibility
};
```

### Create Podman Network

```nix
systemd.services.create-simplelogin-network = {
  serviceConfig.Type = "oneshot";
  wantedBy = [ "multi-user.target" ];
  script = ''
    ${pkgs.podman}/bin/podman network exists simplelogin-net || \
    ${pkgs.podman}/bin/podman network create simplelogin-net
  '';
};
```

### Directory Structure

```nix
systemd.tmpfiles.rules = [
  "d /var/lib/simplelogin 0755 root root -"
  "d /var/lib/simplelogin/postgres 0750 70 70 -"    # postgres UID:GID
  "d /var/lib/simplelogin/redis 0750 999 999 -"     # redis UID:GID
  "d /var/lib/simplelogin/data 0750 root root -"
  "d /var/lib/simplelogin/upload 0750 root root -"
  "d /var/lib/simplelogin/dkim 0700 root root -"    # Sensitive DKIM keys
];
```

### Container Definitions

```nix
virtualisation.oci-containers = {
  backend = "podman";

  containers = {
    # PostgreSQL Database
    simplelogin-postgres = {
      image = "postgres:15-alpine";
      autoStart = true;

      environment = {
        POSTGRES_DB = "simplelogin";
        POSTGRES_USER = "simplelogin";
      };

      environmentFiles = [
        "/run/secrets/simplelogin_db_password"
      ];

      volumes = [
        "/var/lib/simplelogin/postgres:/var/lib/postgresql/data"
      ];

      extraOptions = [ "--network=simplelogin-net" ];
    };

    # Redis Cache
    simplelogin-redis = {
      image = "redis:7-alpine";
      autoStart = true;

      volumes = [
        "/var/lib/simplelogin/redis:/data"
      ];

      extraOptions = [ "--network=simplelogin-net" ];
    };

    # SimpleLogin App
    simplelogin-app = {
      image = "simplelogin/app:latest";
      autoStart = true;

      ports = [
        "127.0.0.1:7777:7777"  # Web interface (local only for NGINX)
      ];

      environment = {
        # URLs & Domains
        URL = "https://simplelogin.rusty-vault.de";
        EMAIL_DOMAIN = "sl.rusty-vault.de";
        SUPPORT_EMAIL = "support@sl.rusty-vault.de";

        # Premium Features enabled
        PREMIUM_FEATURE = "true";
        MAX_NB_EMAIL_FREE_PLAN = "999999";
        MAX_ALIASES_FREE_PLAN = "999999";

        # Database (password from secret)
        DB_URI = "postgresql://simplelogin:PASSWORD_FROM_SECRET@simplelogin-postgres:5432/simplelogin";

        # Redis
        REDIS_URL = "redis://simplelogin-redis:6379";

        # Postfix Integration (host.containers.internal = host system)
        POSTFIX_SERVER = "host.containers.internal";
        POSTFIX_PORT = "25";

        # Disable local Postfix (we use host Postfix)
        POSTFIX_SUBMISSION_TLS = "false";

        # Flask Secret (mounted from secret)
        FLASK_SECRET = "/run/secrets/simplelogin_flask_secret";
      };

      volumes = [
        "/var/lib/simplelogin/data:/sl/data"
        "/var/lib/simplelogin/upload:/code/static/upload"
        "/var/lib/simplelogin/dkim:/dkim"
        "/run/secrets/simplelogin_db_password:/run/secrets/simplelogin_db_password:ro"
        "/run/secrets/simplelogin_flask_secret:/run/secrets/simplelogin_flask_secret:ro"
      ];

      extraOptions = [
        "--network=simplelogin-net"
        "--add-host=host.containers.internal:host-gateway"  # Access to host Postfix
      ];

      dependsOn = [ "simplelogin-postgres" "simplelogin-redis" ];
    };
  };
};
```

### Postfix Configuration

```nix
services.postfix = {
  enable = true;
  hostname = "mail.rusty-vault.de";

  # SimpleLogin as Virtual Alias Domain
  virtual = ''
    @sl.rusty-vault.de simplelogin
  '';

  # Transport: All sl.rusty-vault.de emails to SimpleLogin
  transport = ''
    sl.rusty-vault.de smtp:[127.0.0.1]:7777
  '';

  # Relay Host (optional for better deliverability)
  relayHost = "";  # Empty = direct sending, or e.g. "[smtp.eu.mailgun.org]:587"

  config = {
    # SimpleLogin Virtual Domain
    virtual_alias_domains = "sl.rusty-vault.de";
    virtual_alias_maps = "hash:/etc/postfix/virtual";

    # SMTP Settings
    smtpd_banner = "$myhostname ESMTP";

    # TLS for incoming connections
    smtpd_tls_cert_file = "/var/lib/acme/mail.rusty-vault.de/cert.pem";
    smtpd_tls_key_file = "/var/lib/acme/mail.rusty-vault.de/key.pem";
    smtpd_use_tls = "yes";
    smtpd_tls_security_level = "may";

    # TLS for outgoing connections
    smtp_tls_security_level = "may";
    smtp_tls_loglevel = "1";

    # Message size limit (25MB)
    message_size_limit = "26214400";

    # SimpleLogin Email Handler
    mailbox_transport = "lmtp:unix:/var/lib/simplelogin/postfix-lmtp.sock";

    # Rate Limiting
    smtpd_client_connection_rate_limit = "10";
    smtpd_error_sleep_time = "1s";
    smtpd_soft_error_limit = "10";
    smtpd_hard_error_limit = "20";

    # Reject invalid recipients early
    smtpd_recipient_restrictions = [
      "reject_non_fqdn_recipient"
      "reject_unknown_recipient_domain"
      "permit_mynetworks"
      "reject_unauth_destination"
    ];
  };
};

# ACME Certificate for mail.rusty-vault.de
security.acme.certs."mail.rusty-vault.de" = {
  email = "admin@rusty-vault.de";
  webroot = "/var/lib/acme/acme-challenge";
  postRun = "systemctl reload postfix";
};
```

### NGINX Configuration

```nix
services.nginx.virtualHosts."simplelogin.rusty-vault.de" = {
  enableACME = true;
  forceSSL = true;

  extraConfig = ''
    # Rate Limiting
    limit_req zone=general burst=20 nodelay;
    limit_conn addr 10;

    # Security Headers (consistent with other services)
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Permissions-Policy "accelerometer=(), camera=(), geolocation=(), gyroscope=(), magnetometer=(), microphone=(), payment=(), usb=()" always;
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;

    # Upload size limit for email attachments
    client_max_body_size 25M;
  '';

  locations."/" = {
    proxyPass = "http://127.0.0.1:7777";
    extraConfig = ''
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto https;
    '';
  };
};
```

### Firewall Configuration

```nix
networking.firewall = {
  allowedTCPPorts = [
    22    # SSH (already open)
    80    # HTTP (already open)
    443   # HTTPS (already open)
    25    # SMTP for incoming emails (NEW)
    587   # SMTP Submission (optional, for later)
  ];
};
```

## Implementation Steps

### 1. DNS Configuration (BEFORE installation)

At Hetzner DNS Manager, add these records:

```
# Web-App
A    simplelogin.rusty-vault.de  → 77.42.71.141

# Email Domain
A    mail.rusty-vault.de         → 77.42.71.141
MX   sl.rusty-vault.de           → mail.rusty-vault.de (Priority 10)
TXT  sl                          → v=spf1 mx ~all
TXT  _dmarc.sl                   → v=DMARC1; p=quarantine; rua=mailto:postmaster@sl.rusty-vault.de
```

**DKIM will be added later!**

### 2. Generate and Encrypt Secrets

```bash
# Generate secrets
FLASK_SECRET=$(openssl rand -hex 32)
DB_PASSWORD=$(openssl rand -hex 16)
EMAIL_SECRET=$(openssl rand -hex 16)

# Create secrets/simplelogin.yaml
cat > secrets/simplelogin.yaml << EOF
simplelogin_db_password: "POSTGRES_PASSWORD=$DB_PASSWORD"
simplelogin_flask_secret: "$FLASK_SECRET"
simplelogin_email_secret: "$EMAIL_SECRET"
EOF

# Encrypt with SOPS
sops -e -i secrets/simplelogin.yaml
```

### 3. Update NixOS Configuration

Changes in `configuration.nix`:
- Add SOPS secrets
- Enable Podman (`virtualisation.podman.enable = true`)
- Add container definitions
- Add Postfix configuration
- Open firewall port 25
- Add NGINX virtualHost for simplelogin.rusty-vault.de

### 4. Deploy

```bash
# Copy secrets to server
scp secrets/simplelogin.yaml root@rusty-vault.de:/etc/nixos/secrets/

# NixOS rebuild
ssh root@rusty-vault.de "nixos-rebuild switch"
```

### 5. Initialize Database

```bash
# SSH into server
ssh root@rusty-vault.de

# Initialize database
podman exec -it simplelogin-app flask db upgrade

# Create admin account
podman exec -it simplelogin-app flask create-admin admin@rusty-vault.de
# Enter password when prompted
```

### 6. Generate DKIM Key

```bash
# Generate DKIM key
podman exec -it simplelogin-app python scripts/generate_dkim_key.py

# Display public key (for DNS)
podman exec -it simplelogin-app cat /dkim/dkim.pub.key
```

Then add **DKIM TXT Record** to DNS:
```
Type: TXT
Name: dkim._domainkey.sl
Value: v=DKIM1; k=rsa; p=<public-key-from-above>
```

### 7. Restart Postfix

```bash
systemctl restart postfix
```

## Testing & Verification

### Service Status

```bash
# Container status
podman ps
systemctl status podman-simplelogin-postgres
systemctl status podman-simplelogin-redis
systemctl status podman-simplelogin-app

# Postfix
systemctl status postfix

# NGINX
systemctl status nginx

# Logs
journalctl -u podman-simplelogin-app -f
journalctl -u postfix -f
```

### Functional Tests

1. **Web-App Access**
   ```bash
   curl -I https://simplelogin.rusty-vault.de
   # Should return 200 OK
   ```

2. **Login Test**
   - Browser: https://simplelogin.rusty-vault.de
   - Login with admin@rusty-vault.de

3. **Create Alias**
   - Create new alias (e.g., test@sl.rusty-vault.de)
   - Connect to real mailbox

4. **Email Receiving Test**
   - Send email to test@sl.rusty-vault.de
   - Should be forwarded to real mailbox

5. **Email Sending Test**
   - Reply via SimpleLogin from real mailbox
   - Recipient should see email from test@sl.rusty-vault.de

6. **DNS Validation**
   ```bash
   # MX Record
   dig MX sl.rusty-vault.de

   # SPF
   dig TXT sl.rusty-vault.de

   # DKIM
   dig TXT dkim._domainkey.sl.rusty-vault.de

   # DMARC
   dig TXT _dmarc.sl.rusty-vault.de
   ```

7. **Email Header Check**
   - DKIM signature present?
   - SPF PASS?
   - DMARC PASS?

### Troubleshooting Commands

```bash
# Container logs
podman logs simplelogin-app
podman logs simplelogin-postgres
podman logs simplelogin-redis

# Postfix mail queue
mailq

# Postfix logs
tail -f /var/log/mail.log

# Enter SimpleLogin container
podman exec -it simplelogin-app bash
# Then: flask shell, python manage.py, etc.
```

## Backup Strategy

### Important Data

1. **PostgreSQL Database** - Aliases, users, mailboxes
   ```bash
   podman exec simplelogin-postgres pg_dump -U simplelogin simplelogin > simplelogin-backup.sql
   ```

2. **DKIM Private Keys** - `/var/lib/simplelogin/dkim/`
   ```bash
   tar -czf dkim-backup.tar.gz /var/lib/simplelogin/dkim/
   ```

3. **SOPS Secrets** - `secrets/simplelogin.yaml` (already in Git)

### Automatic Backup (Optional)

```nix
systemd.services.simplelogin-backup = {
  description = "SimpleLogin Database Backup";
  serviceConfig = {
    Type = "oneshot";
    ExecStart = pkgs.writeShellScript "backup-simplelogin" ''
      ${pkgs.podman}/bin/podman exec simplelogin-postgres \
        pg_dump -U simplelogin simplelogin | \
        ${pkgs.gzip}/bin/gzip > /var/backups/simplelogin-$(date +%Y%m%d).sql.gz

      # Delete old backups (older than 30 days)
      find /var/backups/ -name "simplelogin-*.sql.gz" -mtime +30 -delete
    '';
  };
};

systemd.timers.simplelogin-backup = {
  wantedBy = [ "timers.target" ];
  timerConfig = {
    OnCalendar = "daily";
    Persistent = true;
  };
};
```

## Security Considerations

### Container Security

- **Rootless Podman**: Containers don't run as root (if desired)
- **Network Isolation**: Own simplelogin-net network
- **Secret Management**: All secrets encrypted via SOPS
- **Read-only Secrets**: Secrets mounted as read-only

### Email Security

- **DKIM Signing**: All outgoing emails signed
- **SPF**: Prevents email spoofing
- **DMARC**: Email authentication policy
- **TLS**: Encrypted SMTP connections
- **Rate Limiting**: NGINX rate limits protect against abuse

### NGINX Security Headers

Already in existing setup, applies to SimpleLogin too:
- Strict-Transport-Security (HSTS)
- X-Frame-Options
- X-Content-Type-Options
- X-XSS-Protection
- Referrer-Policy

### Postfix Hardening

- Rate limiting on client connections
- Early rejection of invalid recipients
- TLS for incoming and outgoing connections
- Message size limits

## Maintenance & Updates

### Container Updates

```bash
# Update container images
podman pull simplelogin/app:latest
podman pull postgres:15-alpine
podman pull redis:7-alpine

# NixOS rebuild (restarts containers with new images)
nixos-rebuild switch
```

### SimpleLogin Database Migrations

After updates, check if migrations are needed:

```bash
podman exec -it simplelogin-app flask db upgrade
```

### Log Rotation

NixOS/systemd rotates logs automatically. For container logs:

```nix
virtualisation.containers.logDriver = "journald";
```

## Monitoring

### Container Health Checks

```nix
systemd.services.simplelogin-healthcheck = {
  description = "SimpleLogin Health Check";
  serviceConfig = {
    Type = "oneshot";
    ExecStart = pkgs.writeShellScript "healthcheck" ''
      ${pkgs.curl}/bin/curl -f https://simplelogin.rusty-vault.de/api/health || exit 1
    '';
  };
};
```

### Logs with fail2ban

Fail2ban already monitors NGINX logs, SimpleLogin logins are automatically protected.

### Email Metrics

SimpleLogin has an integrated dashboard at `/dashboard` for:
- Number of aliases
- Email statistics
- Bounces/blocks
- Storage usage

## Success Criteria

- [ ] All containers running (`podman ps`)
- [ ] Web-App accessible at https://simplelogin.rusty-vault.de
- [ ] Admin account created and login works
- [ ] DNS records correct (MX, SPF, DKIM, DMARC)
- [ ] Test alias created
- [ ] Email receiving works (forwarding to real mailbox)
- [ ] Email sending works (reply via alias)
- [ ] DKIM signature in outgoing emails
- [ ] TLS certificates valid
- [ ] Postfix receives emails on port 25
- [ ] No errors in logs

## References

- [SimpleLogin Documentation](https://simplelogin.io/docs/)
- [SimpleLogin GitHub](https://github.com/simple-login/app)
- [SimpleLogin Self-Hosting Guide](https://github.com/simple-login/app/blob/master/docs/self-hosting.md)
- [NixOS Podman Module](https://search.nixos.org/options?query=virtualisation.podman)
- [Postfix Documentation](http://www.postfix.org/documentation.html)
