# Jitsi Meet Setup Instructions

## Prerequisites

Before deploying, ensure DNS is configured:

```bash
# Verify DNS resolution
dig jitsi.rusty-vault.de +short
# Should return your server IP address
```

## Step 1: Create and Encrypt Secrets

```bash
# Create the secrets file from template
cp secrets/jitsi.yaml.template secrets/jitsi.yaml

# Edit and set a strong password
nano secrets/jitsi.yaml
# Replace CHANGE_ME_STRONG_PASSWORD with a strong password

# Encrypt with SOPS
sops -e -i secrets/jitsi.yaml

# Verify encryption worked
cat secrets/jitsi.yaml
# Should show encrypted content starting with ENC[...]
```

## Step 2: Test Build Locally

```bash
# Test the configuration builds without errors
nix build .#nixosConfigurations.nixos-server.config.system.build.toplevel
```

## Step 3: Deploy to Server

```bash
# Deploy using the nrs command
nix run

# Or manually:
nixos-rebuild switch --flake .#nixos-server --target-host root@rusty-vault.de
```

## Step 4: Verify Services Started

```bash
ssh root@rusty-vault.de

# Check all Jitsi services
systemctl status jitsi-meet
systemctl status prosody
systemctl status jicofo
systemctl status jitsi-videobridge2

# Check NGINX configuration
nginx -t
systemctl status nginx
```

## Step 5: Wait for ACME Certificate

```bash
# Monitor certificate generation
ssh root@rusty-vault.de
journalctl -u acme-jitsi.rusty-vault.de -f

# Once complete, verify certificate exists
ls -la /var/lib/acme/jitsi.rusty-vault.de/
```

## Step 6: Create Moderator User

After services are running and certificates are in place:

```bash
ssh root@rusty-vault.de

# Get the password from secrets
JITSI_PASSWORD=$(cat /run/secrets/jitsi_moderator_password)

# Create moderator user in Prosody
prosodyctl --config /var/lib/jitsi-meet/prosody-cfg/prosody.cfg.lua \
  register moderator jitsi.rusty-vault.de "$JITSI_PASSWORD"

# Verify user was created
prosodyctl --config /var/lib/jitsi-meet/prosody-cfg/prosody.cfg.lua \
  shell user list jitsi.rusty-vault.de
```

## Step 7: Test Web Interface

1. Open browser: https://jitsi.rusty-vault.de
2. Enter a meeting name and click "Start meeting"
3. You should see a moderator login prompt
4. Login with:
   - Username: `moderator`
   - Password: `<your password from secrets/jitsi.yaml>`
5. Test video/audio functionality

## Step 8: Test Guest Access

1. Open an incognito/private browser window
2. Go to: https://jitsi.rusty-vault.de
3. Join the same meeting name
4. Enter a display name (no login required)
5. You should be able to join the meeting without authentication

## Verification Commands

### Check Service Status
```bash
ssh root@rusty-vault.de

# All services should be active (running)
systemctl status jitsi-meet prosody jicofo jitsi-videobridge2
```

### Check Firewall
```bash
ssh root@rusty-vault.de

# UDP 10000 should be listening
ss -ulnp | grep 10000

# Check firewall rules
iptables -L -n -v | grep 10000
```

### Check Logs
```bash
ssh root@rusty-vault.de

# Jitsi Videobridge
journalctl -u jitsi-videobridge2 -f

# Jicofo
journalctl -u jicofo -f

# Prosody XMPP
journalctl -u prosody -f

# NGINX
journalctl -u nginx -f
```

### Check NGINX Virtual Host
```bash
ssh root@rusty-vault.de

# Verify Jitsi vhost exists
nginx -T | grep -A 20 "server_name jitsi.rusty-vault.de"
```

## Troubleshooting

### Services Won't Start
```bash
# Check for errors
journalctl -xe

# Check Prosody configuration
prosodyctl check config

# Verify certificate permissions
ls -la /var/lib/acme/jitsi.rusty-vault.de/
```

### Video/Audio Not Working
```bash
# Check JVB logs for NAT detection
journalctl -u jitsi-videobridge2 | grep -i "public address"

# Verify UDP port is open
ss -ulnp | grep 10000
```

### Login Not Working
```bash
# Verify moderator user exists
prosodyctl --config /var/lib/jitsi-meet/prosody-cfg/prosody.cfg.lua \
  shell user list jitsi.rusty-vault.de

# Check Prosody authentication logs
journalctl -u prosody | grep -i auth
```

### Certificate Issues
```bash
# Check ACME service status
systemctl status acme-jitsi.rusty-vault.de

# Manually trigger renewal
systemctl start acme-jitsi.rusty-vault.de

# Check certificate validity
openssl s_client -connect jitsi.rusty-vault.de:443 -servername jitsi.rusty-vault.de < /dev/null | openssl x509 -noout -dates
```

## Architecture Overview

**Components:**
- **Jitsi Meet (Web):** Frontend on port 443 via NGINX
- **Prosody (XMPP):** Signaling server for room management
- **Jicofo:** Conference focus, orchestrates meetings
- **JVB (Videobridge):** Media streaming via UDP port 10000

**Ports:**
- 443/TCP: HTTPS (Jitsi Web Interface)
- 10000/UDP: Media streaming (JVB)
- Internal: Prosody, Jicofo, JVB communicate via localhost

**Authentication:**
- Main domain (`jitsi.rusty-vault.de`): Requires authentication to create rooms
- Guest domain (`guest.jitsi.rusty-vault.de`): Anonymous access for participants
- Moderators must login to create meetings
- Guests can join existing meetings without login

## Post-Setup Configuration

### Adding More Moderators
```bash
ssh root@rusty-vault.de

# Add another moderator user
prosodyctl --config /var/lib/jitsi-meet/prosody-cfg/prosody.cfg.lua \
  register <username> jitsi.rusty-vault.de <password>
```

### Changing Moderator Password
```bash
ssh root@rusty-vault.de

# Change password
prosodyctl --config /var/lib/jitsi-meet/prosody-cfg/prosody.cfg.lua \
  passwd moderator@jitsi.rusty-vault.de
```

### Deleting Moderator User
```bash
ssh root@rusty-vault.de

# Delete user
prosodyctl --config /var/lib/jitsi-meet/prosody-cfg/prosody.cfg.lua \
  deluser moderator@jitsi.rusty-vault.de
```

## Security Notes

1. **Firewall:** Only UDP port 10000 and TCP ports 80/443 are exposed
2. **Authentication:** Only authenticated users can create rooms
3. **HTTPS:** All connections encrypted via Let's Encrypt
4. **Automatic Updates:** System updates run daily at 04:00
5. **Secrets:** Moderator credentials encrypted with SOPS

## Optional Future Enhancements

- **TURN Server (coturn):** Better firewall compatibility
- **Recording (Jibri):** Record meetings
- **LDAP/OAuth:** Centralized authentication
- **Lobby Mode:** Waiting room for guests
- **Moderation Tools:** Enhanced moderation features
