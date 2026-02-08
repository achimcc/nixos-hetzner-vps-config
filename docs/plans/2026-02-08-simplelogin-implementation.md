# SimpleLogin Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Install and configure SimpleLogin as a self-hosted email alias service with Podman containers, Postfix mail server, and full DNS/TLS setup.

**Architecture:** Three-container stack (SimpleLogin app, PostgreSQL, Redis) managed by NixOS oci-containers, integrated with Postfix for mail handling on port 25, NGINX reverse proxy for HTTPS access at simplelogin.rusty-vault.de, and complete email infrastructure for @sl.rusty-vault.de aliases.

**Tech Stack:** NixOS 24.11, Podman, SimpleLogin (Docker image), PostgreSQL 15, Redis 7, Postfix, NGINX, SOPS-nix, ACME/Let's Encrypt

---

## Prerequisites

**Before starting implementation:**
- [ ] DNS records added at Hetzner (see design doc)
- [ ] Secrets generated and encrypted with SOPS
- [ ] Working in isolated git worktree

---

## Task 1: Generate and Encrypt Secrets

**Files:**
- Create: `secrets/simplelogin.yaml`
- Modify: None

**Step 1: Generate secrets locally**

```bash
# Generate Flask secret (64 hex chars)
FLASK_SECRET=$(openssl rand -hex 32)

# Generate DB password (32 hex chars)
DB_PASSWORD=$(openssl rand -hex 16)

# Generate email secret (32 hex chars)
EMAIL_SECRET=$(openssl rand -hex 16)

# Display for verification (save these temporarily)
echo "FLASK_SECRET: $FLASK_SECRET"
echo "DB_PASSWORD: $DB_PASSWORD"
echo "EMAIL_SECRET: $EMAIL_SECRET"
```

Run: Execute the bash commands
Expected: Three random hex strings displayed

**Step 2: Create plaintext secrets file**

```bash
cat > secrets/simplelogin.yaml << EOF
simplelogin_db_password: "POSTGRES_PASSWORD=$DB_PASSWORD"
simplelogin_flask_secret: "$FLASK_SECRET"
simplelogin_email_secret: "$EMAIL_SECRET"
EOF
```

Run: Execute command with actual generated values
Expected: File created at `secrets/simplelogin.yaml`

**Step 3: Verify file content**

```bash
cat secrets/simplelogin.yaml
```

Run: Display file content
Expected: Three lines with correct secret values

**Step 4: Encrypt with SOPS**

```bash
sops -e -i secrets/simplelogin.yaml
```

Run: Execute encryption command
Expected: File now encrypted (shows `sops:` metadata when viewed)

**Step 5: Verify encryption**

```bash
head -n 5 secrets/simplelogin.yaml
```

Run: Display first 5 lines
Expected: Should see `sops:` metadata, not plaintext secrets

**Step 6: Commit encrypted secrets**

```bash
git add secrets/simplelogin.yaml
git commit -m "Add encrypted SimpleLogin secrets

- PostgreSQL password
- Flask secret key
- Email encryption secret

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

Run: Commit command
Expected: Commit successful, 1 file changed

---

## Task 2: Add SOPS Secret Declarations

**Files:**
- Modify: `configuration.nix` (lines 16-32, in SOPS section)

**Step 1: Read current SOPS configuration**

```bash
sed -n '16,32p' configuration.nix
```

Run: Display SOPS section
Expected: Shows existing secrets configuration

**Step 2: Add SimpleLogin secrets after line 31**

Add these lines after `ghostfolio_env` secret (before closing brace):

```nix
    secrets.simplelogin_db_password = {
      sopsFile = ./secrets/simplelogin.yaml;
      mode = "0400";
    };
    secrets.simplelogin_flask_secret = {
      sopsFile = ./secrets/simplelogin.yaml;
      mode = "0400";
    };
    secrets.simplelogin_email_secret = {
      sopsFile = ./secrets/simplelogin.yaml;
      mode = "0400";
    };
```

**Step 3: Verify syntax**

```bash
nix-instantiate --parse configuration.nix > /dev/null && echo "Syntax OK"
```

Run: Check Nix syntax
Expected: "Syntax OK"

**Step 4: Commit SOPS configuration**

```bash
git add configuration.nix
git commit -m "Add SOPS secrets for SimpleLogin

- Database password
- Flask secret key
- Email encryption secret

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

Run: Commit command
Expected: Commit successful

---

## Task 3: Create Podman Network Service

**Files:**
- Modify: `configuration.nix` (after line 348, after ghostfolio network)

**Step 1: Add SimpleLogin network service**

Add after the `create-ghostfolio-network` service:

```nix
  # Podman-Netzwerk fuer SimpleLogin erstellen
  systemd.services.create-simplelogin-network = {
    description = "Create Podman network for SimpleLogin";
    after = [ "podman.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.podman}/bin/podman network exists simplelogin-net || \
      ${pkgs.podman}/bin/podman network create simplelogin-net
    '';
  };
```

**Step 2: Verify syntax**

```bash
nix-instantiate --parse configuration.nix > /dev/null && echo "Syntax OK"
```

Run: Check syntax
Expected: "Syntax OK"

**Step 3: Commit network service**

```bash
git add configuration.nix
git commit -m "Add Podman network for SimpleLogin

Creates simplelogin-net for container communication

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

Run: Commit
Expected: Successful

---

## Task 4: Create Directory Structure tmpfiles

**Files:**
- Modify: `configuration.nix` (search for `systemd.tmpfiles.rules`, add after existing rules)

**Step 1: Find existing tmpfiles rules**

```bash
grep -n "systemd.tmpfiles.rules" configuration.nix
```

Run: Find tmpfiles section
Expected: Line number where tmpfiles.rules is defined

**Step 2: Add SimpleLogin directories**

Add to the `systemd.tmpfiles.rules` array:

```nix
    # SimpleLogin directories
    "d /var/lib/simplelogin 0755 root root -"
    "d /var/lib/simplelogin/postgres 0750 70 70 -"
    "d /var/lib/simplelogin/redis 0750 999 999 -"
    "d /var/lib/simplelogin/data 0750 root root -"
    "d /var/lib/simplelogin/upload 0750 root root -"
    "d /var/lib/simplelogin/dkim 0700 root root -"
```

**Step 3: Verify syntax**

```bash
nix-instantiate --parse configuration.nix > /dev/null && echo "Syntax OK"
```

Run: Syntax check
Expected: "Syntax OK"

**Step 4: Commit tmpfiles rules**

```bash
git add configuration.nix
git commit -m "Add directory structure for SimpleLogin

Creates /var/lib/simplelogin with subdirs for:
- postgres (db data)
- redis (cache)
- data (app data)
- upload (file uploads)
- dkim (private keys)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

Run: Commit
Expected: Successful

---

## Task 5: Add PostgreSQL Container

**Files:**
- Modify: `configuration.nix` (in `virtualisation.oci-containers.containers` section, after line 352)

**Step 1: Find container section**

```bash
grep -n "virtualisation.oci-containers.containers" configuration.nix
```

Run: Find containers section
Expected: Line 352

**Step 2: Add PostgreSQL container**

Add after the ghostfolio containers, before closing brace:

```nix
    # SimpleLogin PostgreSQL Database
    simplelogin-postgres = {
      image = "docker.io/library/postgres:15-alpine";
      autoStart = true;

      environment = {
        POSTGRES_DB = "simplelogin";
        POSTGRES_USER = "simplelogin";
      };

      environmentFiles = [
        config.sops.secrets.simplelogin_db_password.path
      ];

      volumes = [
        "/var/lib/simplelogin/postgres:/var/lib/postgresql/data"
      ];

      extraOptions = [
        "--network=simplelogin-net"
        "--cap-drop=ALL"
        "--cap-add=DAC_OVERRIDE"
        "--cap-add=SETGID"
        "--cap-add=SETUID"
        "--cap-add=FOWNER"
        "--cap-add=CHOWN"
        "--security-opt=no-new-privileges:true"
        "--health-cmd=pg_isready -U simplelogin"
        "--health-interval=10s"
        "--health-timeout=5s"
        "--health-retries=5"
      ];
    };
```

**Step 3: Verify syntax**

```bash
nix-instantiate --parse configuration.nix > /dev/null && echo "Syntax OK"
```

Run: Syntax check
Expected: "Syntax OK"

**Step 4: Commit PostgreSQL container**

```bash
git add configuration.nix
git commit -m "Add PostgreSQL container for SimpleLogin

- postgres:15-alpine image
- simplelogin database and user
- SOPS-encrypted password
- Health checks enabled
- Security hardened with capability drops

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

Run: Commit
Expected: Successful

---

## Task 6: Add Redis Container

**Files:**
- Modify: `configuration.nix` (after simplelogin-postgres container)

**Step 1: Add Redis container**

Add after simplelogin-postgres:

```nix
    # SimpleLogin Redis Cache
    simplelogin-redis = {
      image = "docker.io/library/redis:7-alpine";
      autoStart = true;

      volumes = [
        "/var/lib/simplelogin/redis:/data"
      ];

      extraOptions = [
        "--network=simplelogin-net"
        "--cap-drop=ALL"
        "--cap-add=SETGID"
        "--cap-add=SETUID"
        "--security-opt=no-new-privileges:true"
        "--health-cmd=redis-cli ping"
        "--health-interval=10s"
        "--health-timeout=5s"
        "--health-retries=5"
      ];
    };
```

**Step 2: Verify syntax**

```bash
nix-instantiate --parse configuration.nix > /dev/null && echo "Syntax OK"
```

Run: Syntax check
Expected: "Syntax OK"

**Step 3: Commit Redis container**

```bash
git add configuration.nix
git commit -m "Add Redis container for SimpleLogin

- redis:7-alpine image
- Persistent storage in /var/lib/simplelogin/redis
- Health checks enabled
- Security hardened

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

Run: Commit
Expected: Successful

---

## Task 7: Add SimpleLogin App Container

**Files:**
- Modify: `configuration.nix` (after simplelogin-redis container)

**Step 1: Add SimpleLogin app container**

Add after simplelogin-redis:

```nix
    # SimpleLogin Application
    simplelogin-app = {
      image = "docker.io/simplelogin/app:latest";
      autoStart = true;

      ports = [
        "127.0.0.1:7777:7777"
      ];

      environment = {
        # URLs & Domains
        URL = "https://simplelogin.rusty-vault.de";
        EMAIL_DOMAIN = "sl.rusty-vault.de";
        SUPPORT_EMAIL = "support@sl.rusty-vault.de";
        SUPPORT_NAME = "SimpleLogin Support";

        # Premium Features (all enabled for self-hosting)
        PREMIUM = "true";
        MAX_NB_EMAIL_FREE_PLAN = "999999";

        # Database connection
        DB_URI = "postgresql://simplelogin@simplelogin-postgres:5432/simplelogin";

        # Redis
        REDIS_URL = "redis://simplelogin-redis:6379";

        # Email via Postfix on host
        POSTFIX_SERVER = "host.containers.internal";
        POSTFIX_PORT = "25";
        POSTFIX_SUBMISSION_TLS = "false";

        # Flask configuration
        FLASK_SECRET = "/run/secrets/simplelogin_flask_secret";

        # Disable local email server (we use host Postfix)
        LOCAL_FILE_UPLOAD = "1";
      };

      environmentFiles = [
        config.sops.secrets.simplelogin_db_password.path
      ];

      volumes = [
        "/var/lib/simplelogin/data:/sl/data"
        "/var/lib/simplelogin/upload:/code/static/upload"
        "/var/lib/simplelogin/dkim:/dkim"
        "${config.sops.secrets.simplelogin_flask_secret.path}:/run/secrets/simplelogin_flask_secret:ro"
      ];

      extraOptions = [
        "--network=simplelogin-net"
        "--add-host=host.containers.internal:host-gateway"
        "--cap-drop=ALL"
        "--cap-add=NET_BIND_SERVICE"
        "--security-opt=no-new-privileges:true"
      ];

      dependsOn = [
        "simplelogin-postgres"
        "simplelogin-redis"
      ];
    };
```

**Step 2: Verify syntax**

```bash
nix-instantiate --parse configuration.nix > /dev/null && echo "Syntax OK"
```

Run: Syntax check
Expected: "Syntax OK"

**Step 3: Commit SimpleLogin app container**

```bash
git add configuration.nix
git commit -m "Add SimpleLogin app container

- simplelogin/app:latest image
- Port 7777 for NGINX reverse proxy
- Premium features enabled
- PostgreSQL + Redis integration
- Postfix email via host
- SOPS secrets mounted
- Depends on postgres and redis containers

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

Run: Commit
Expected: Successful

---

## Task 8: Configure Postfix Service

**Files:**
- Modify: `configuration.nix` (add services.postfix section, search for a good location after services.nginx)

**Step 1: Find location for Postfix config**

```bash
grep -n "services.nginx" configuration.nix | head -1
```

Run: Find NGINX section
Expected: Line number ~474

**Step 2: Add Postfix configuration**

Add after the NGINX section (around line 580-600, find a good spot):

```nix
  # ============================================================================
  # POSTFIX MAIL SERVER (for SimpleLogin)
  # ============================================================================

  services.postfix = {
    enable = true;
    hostname = "mail.rusty-vault.de";
    domain = "rusty-vault.de";
    origin = "rusty-vault.de";

    # Network configuration
    networks = [ "127.0.0.0/8" "[::1]/128" ];

    # Virtual domains for SimpleLogin
    virtual = ''
      @sl.rusty-vault.de simplelogin
    '';

    # Main configuration
    config = {
      # Basic SMTP settings
      smtpd_banner = "$myhostname ESMTP";
      biff = "no";
      append_dot_mydomain = "no";
      readme_directory = "no";
      compatibility_level = "3.6";

      # Virtual alias configuration
      virtual_alias_domains = "sl.rusty-vault.de";
      virtual_alias_maps = "hash:/etc/postfix/virtual";

      # Transport to SimpleLogin
      transport_maps = "hash:/etc/postfix/transport";

      # TLS for incoming connections
      smtpd_use_tls = "yes";
      smtpd_tls_security_level = "may";
      smtpd_tls_cert_file = "/var/lib/acme/mail.rusty-vault.de/cert.pem";
      smtpd_tls_key_file = "/var/lib/acme/mail.rusty-vault.de/key.pem";
      smtpd_tls_session_cache_database = "btree:${config.services.postfix.dataDir}/smtpd_scache";
      smtpd_tls_loglevel = "1";

      # TLS for outgoing connections
      smtp_tls_security_level = "may";
      smtp_tls_session_cache_database = "btree:${config.services.postfix.dataDir}/smtp_scache";
      smtp_tls_loglevel = "1";

      # Message size limit (25MB)
      message_size_limit = "26214400";
      mailbox_size_limit = "0";

      # Recipient restrictions
      smtpd_recipient_restrictions = [
        "reject_non_fqdn_recipient"
        "reject_unknown_recipient_domain"
        "permit_mynetworks"
        "reject_unauth_destination"
      ];

      # Rate limiting
      smtpd_client_connection_rate_limit = "10";
      smtpd_error_sleep_time = "1s";
      smtpd_soft_error_limit = "10";
      smtpd_hard_error_limit = "20";

      # Relay restrictions
      smtpd_relay_restrictions = [
        "permit_mynetworks"
        "reject_unauth_destination"
      ];
    };

    # Transport map for SimpleLogin
    transport = ''
      sl.rusty-vault.de smtp:[127.0.0.1]:7777
    '';
  };

  # ACME certificate for mail.rusty-vault.de
  security.acme.certs."mail.rusty-vault.de" = {
    email = "admin@rusty-vault.de";
    group = "postfix";
    postRun = "systemctl reload postfix";
  };
```

**Step 3: Verify syntax**

```bash
nix-instantiate --parse configuration.nix > /dev/null && echo "Syntax OK"
```

Run: Syntax check
Expected: "Syntax OK"

**Step 4: Commit Postfix configuration**

```bash
git add configuration.nix
git commit -m "Add Postfix mail server for SimpleLogin

- Full mail server on mail.rusty-vault.de
- Virtual domain sl.rusty-vault.de
- Transport to SimpleLogin container
- TLS with ACME certificates
- Rate limiting and security hardening
- 25MB message size limit

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

Run: Commit
Expected: Successful

---

## Task 9: Add NGINX Virtual Host

**Files:**
- Modify: `configuration.nix` (in services.nginx.virtualHosts section, after ghostfolio vhost)

**Step 1: Find NGINX virtualHosts section**

```bash
grep -n 'virtualHosts."ghostfolio' configuration.nix
```

Run: Find ghostfolio vhost
Expected: Line number ~558

**Step 2: Add SimpleLogin virtualHost**

Add after the ghostfolio virtualHost block:

```nix
    virtualHosts."simplelogin.rusty-vault.de" = {
      enableACME = true;
      forceSSL = true;

      extraConfig = ''
        # Rate Limiting
        limit_req zone=general burst=20 nodelay;
        limit_conn addr 10;

        # Security Headers
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
        proxyWebsockets = true;
        extraConfig = ''
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto https;

          proxy_hide_header X-Powered-By;
          proxy_hide_header Server;
        '';
      };
    };
```

**Step 3: Verify syntax**

```bash
nix-instantiate --parse configuration.nix > /dev/null && echo "Syntax OK"
```

Run: Syntax check
Expected: "Syntax OK"

**Step 4: Commit NGINX virtualHost**

```bash
git add configuration.nix
git commit -m "Add NGINX virtualHost for SimpleLogin

- simplelogin.rusty-vault.de domain
- ACME/Let's Encrypt TLS
- Reverse proxy to port 7777
- Security headers (HSTS, CSP, etc.)
- Rate limiting
- 25MB upload limit for attachments

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

Run: Commit
Expected: Successful

---

## Task 10: Update Firewall Configuration

**Files:**
- Modify: `configuration.nix` (line ~626, in networking.firewall.allowedTCPPorts)

**Step 1: Find firewall ports configuration**

```bash
grep -n "allowedTCPPorts" configuration.nix
```

Run: Find firewall section
Expected: Line number ~626

**Step 2: Read current ports**

```bash
sed -n '626,631p' configuration.nix
```

Run: Show current ports
Expected: Ports 22, 80, 443, 22067

**Step 3: Add port 25 for SMTP**

Modify the allowedTCPPorts array to include port 25:

```nix
    allowedTCPPorts = [
      22      # SSH
      25      # SMTP (SimpleLogin email)
      80      # HTTP
      443     # HTTPS
      22067   # Syncthing Relay
    ];
```

**Step 4: Verify syntax**

```bash
nix-instantiate --parse configuration.nix > /dev/null && echo "Syntax OK"
```

Run: Syntax check
Expected: "Syntax OK"

**Step 5: Commit firewall change**

```bash
git add configuration.nix
git commit -m "Open port 25 for SMTP email receiving

SimpleLogin requires port 25 for incoming emails

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

Run: Commit
Expected: Successful

---

## Task 11: Update README Documentation

**Files:**
- Modify: `README.md` (add SimpleLogin to Components table and Features list)

**Step 1: Read current Components table**

```bash
sed -n '14,23p' README.md
```

Run: Show Components table
Expected: Vaultwarden, Syncthing Relay, NGINX, SOPS, LUKS

**Step 2: Add SimpleLogin to Components**

Add after "Syncthing Relay" in the Components table:

```markdown
| Service | Port | Description |
|---------|------|-------------|
| Vaultwarden | 8222 (internal) | Password Manager |
| Syncthing Relay | 22067 | Relay server for Syncthing clients |
| SimpleLogin | 7777 (internal) | Email Alias Service |
| Syncthing Status | 22070 (internal) | Relay status API |
| NGINX | 80, 443 | Reverse Proxy + TLS |
| Postfix | 25 | Mail Server (SimpleLogin) |
| SSH | 22 | Administration |
```

**Step 3: Add SimpleLogin to Features list**

Update the Features section at the top:

```markdown
## Features

- **Vaultwarden** - Self-hosted Bitwarden-compatible password manager
- **SimpleLogin** - Email alias service for privacy protection
- **Syncthing Relay** - Public relay server for Syncthing file synchronization
- **NGINX** - Reverse proxy with Let's Encrypt TLS
- **Postfix** - Mail server for SimpleLogin email aliases
- **SOPS-nix** - Encrypted secrets using Age encryption
- **LUKS** - Full disk encryption with remote SSH unlock
- **Security Hardening** - Comprehensive system hardening
```

**Step 4: Commit README updates**

```bash
git add README.md
git commit -m "Add SimpleLogin to README documentation

- Add to Features list
- Add to Components table with port info
- Document Postfix mail server

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

Run: Commit
Expected: Successful

---

## Task 12: Final Configuration Review

**Files:**
- Review: `configuration.nix`

**Step 1: Verify all changes are committed**

```bash
git status
```

Run: Check git status
Expected: "working tree clean"

**Step 2: Review commit history**

```bash
git log --oneline -15
```

Run: Show recent commits
Expected: All 12 tasks committed

**Step 3: Syntax check entire configuration**

```bash
nix-instantiate --parse configuration.nix > /dev/null && echo "Configuration syntax valid"
```

Run: Final syntax check
Expected: "Configuration syntax valid"

**Step 4: Count configuration lines**

```bash
wc -l configuration.nix
```

Run: Line count
Expected: ~850-900 lines (increased from 732)

**Step 5: Create summary commit tag**

```bash
git tag -a simplelogin-config-ready -m "SimpleLogin configuration complete

All NixOS configuration changes for SimpleLogin:
- 3 Podman containers (app, postgres, redis)
- Postfix mail server
- NGINX reverse proxy
- Firewall port 25
- SOPS secrets
- Documentation updates

Ready for deployment testing."
```

Run: Tag command
Expected: Tag created

---

## Post-Implementation: Manual Deployment Steps

**These steps are executed AFTER merging to main and deploying to server:**

### Step 1: Copy secrets to server

```bash
scp secrets/simplelogin.yaml root@rusty-vault.de:/etc/nixos/secrets/
```

### Step 2: Deploy configuration

```bash
ssh root@rusty-vault.de "nixos-rebuild switch"
```

### Step 3: Wait for containers to start

```bash
ssh root@rusty-vault.de "podman ps"
```

Expected: 3 SimpleLogin containers running

### Step 4: Initialize database

```bash
ssh root@rusty-vault.de "podman exec -it simplelogin-app flask db upgrade"
```

### Step 5: Create admin account

```bash
ssh root@rusty-vault.de "podman exec -it simplelogin-app flask create-admin admin@rusty-vault.de"
```

Enter password when prompted.

### Step 6: Generate DKIM key

```bash
ssh root@rusty-vault.de "podman exec -it simplelogin-app python scripts/generate_dkim_key.py"
ssh root@rusty-vault.de "podman exec -it simplelogin-app cat /dkim/dkim.pub.key"
```

Copy the public key output.

### Step 7: Add DKIM DNS record

At Hetzner DNS:
```
Type: TXT
Name: dkim._domainkey.sl
Value: v=DKIM1; k=rsa; p=<public-key-from-step-6>
```

### Step 8: Restart Postfix

```bash
ssh root@rusty-vault.de "systemctl restart postfix"
```

### Step 9: Test web access

```bash
curl -I https://simplelogin.rusty-vault.de
```

Expected: 200 OK

### Step 10: Test login

Browser: https://simplelogin.rusty-vault.de
Login with admin@rusty-vault.de

---

## Testing Checklist

After deployment:

- [ ] All containers running (`podman ps` shows 3 SimpleLogin containers)
- [ ] Web-App accessible at https://simplelogin.rusty-vault.de
- [ ] Admin login works
- [ ] Can create test alias
- [ ] DNS records propagated (dig checks for MX, SPF, DKIM, DMARC)
- [ ] Postfix receiving on port 25 (`ss -tlnp | grep :25`)
- [ ] Test email receiving (send to alias, check forwarding)
- [ ] Test email sending (reply via alias)
- [ ] DKIM signature present in sent emails
- [ ] No errors in logs (`journalctl -u podman-simplelogin-app -n 50`)

---

## Rollback Plan

If issues occur during deployment:

```bash
# On server
ssh root@rusty-vault.de

# Stop SimpleLogin containers
systemctl stop podman-simplelogin-app
systemctl stop podman-simplelogin-postgres
systemctl stop podman-simplelogin-redis

# Disable Postfix
systemctl stop postfix
systemctl disable postfix

# Revert to previous NixOS configuration
nixos-rebuild switch --rollback
```

---

## Success Criteria

Configuration phase complete when:
- [ ] All 12 tasks committed to git
- [ ] Syntax validation passes
- [ ] Tag `simplelogin-config-ready` created
- [ ] No uncommitted changes in worktree
- [ ] Ready to merge to main branch

Deployment phase complete when:
- [ ] All containers healthy
- [ ] Web interface accessible
- [ ] Email receiving works
- [ ] Email sending works
- [ ] DKIM verification passes
- [ ] No errors in service logs
