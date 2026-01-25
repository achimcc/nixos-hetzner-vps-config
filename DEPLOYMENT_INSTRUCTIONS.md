# Miniflux Deployment

## Security: Password Management

**IMPORTANT**: The deployment script does NOT contain any passwords. The admin password must be provided as an environment variable.

## Deployment

### Quick Deployment

```bash
# Set password as environment variable (one-time use)
MINIFLUX_ADMIN_PASS='your-secure-password-here' ./deploy-miniflux.sh
```

### Deployment with Password in Shell (more secure)

```bash
# Set password in current shell session
export MINIFLUX_ADMIN_PASS='your-secure-password-here'

# Run deployment
./deploy-miniflux.sh

# Unset password after deployment
unset MINIFLUX_ADMIN_PASS
```

### Deployment with Password from File (most secure)

```bash
# Store password in a secure file (NOT in git)
echo 'your-secure-password' > ~/.miniflux-password
chmod 600 ~/.miniflux-password

# Deploy using password from file
MINIFLUX_ADMIN_PASS=$(cat ~/.miniflux-password) ./deploy-miniflux.sh

# Optionally delete the file after deployment
rm ~/.miniflux-password
```

## What the Script Does

1. ✅ Copies `configuration.nix` to server
2. ✅ Adds admin credentials to SOPS secrets (encrypted on server)
3. ✅ Applies NixOS configuration (`nixos-rebuild switch`)
4. ✅ Verifies services (Miniflux, PostgreSQL, NGINX)
5. ✅ Shows logs

## After Deployment

Access Miniflux:
- **URL**: https://rusty-vault.de/miniflux/
- **Username**: admin
- **Password**: (the one you provided)

**Recommended**: Change the password in Miniflux UI (Settings → Users) after first login.

## Security Notes

- ✅ Password is passed via environment variable (not stored in script)
- ✅ Password is encrypted with SOPS on the server
- ✅ Password is NOT logged or stored in plain text anywhere
- ✅ Add `.miniflux-password` to `.gitignore` if using file method
- ✅ Never commit password files to git

## Troubleshooting

### Script fails with "MINIFLUX_ADMIN_PASS environment variable not set"

Make sure you're passing the password:
```bash
MINIFLUX_ADMIN_PASS='your-password' ./deploy-miniflux.sh
```

### Service won't start after deployment

```bash
# Check logs
ssh root@rusty-vault.de "journalctl -u miniflux -n 50"

# Verify secret
ssh root@rusty-vault.de "cat /run/secrets/miniflux_admin"
```

### Password not working

Make sure your password:
- Is at least 6 characters long
- Does not contain characters that need shell escaping (use single quotes)
- Was correctly passed to the script
