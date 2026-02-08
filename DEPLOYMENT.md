# Deployment Guide

## Quick Deploy with `nrs`

The `nrs` (NixOS Rebuild Switch) command provides one-click deployment to your server.

### Basic Usage

```bash
# Deploy to default server (root@rusty-vault.de)
nix run .#nrs

# Or install it to your profile
nix profile install .#nrs
nrs
```

### Environment Variables

- `NRS_SERVER`: Override default server (default: `root@rusty-vault.de`)
- `NRS_HOSTNAME`: Override hostname config (default: `nixos-server`)

```bash
# Deploy to a different server
NRS_SERVER=root@example.com nix run .#nrs

# Deploy to a different configuration
NRS_HOSTNAME=my-server nix run .#nrs
```

### What it does

1. **Checks for uncommitted changes** - warns if working tree is dirty
2. **Copies flake to server** - uses rsync with smart exclusions
3. **Rebuilds remotely** - runs `nixos-rebuild switch --flake .#nixos-server`
4. **Reports status** - shows success/failure with verification commands

### Manual Deployment

If you prefer manual control:

```bash
# Copy flake to server
rsync -av --delete --exclude='.git' --exclude='result' \
  . root@rusty-vault.de:/etc/nixos/

# SSH and rebuild
ssh root@rusty-vault.de
cd /etc/nixos
nixos-rebuild switch --flake .#nixos-server
```

### Verification

After deployment, verify services are running:

```bash
# Check for failed units
ssh root@rusty-vault.de "systemctl is-failed '*' | grep -v not-found"

# Check containers
ssh root@rusty-vault.de "podman ps"

# Check web services
curl -sI https://rusty-vault.de | head -1
curl -sI https://ghostfolio.rusty-vault.de | head -1
curl -sI https://privatebin.rusty-vault.de | head -1
curl -sI https://simplelogin.rusty-vault.de | head -1
```

### Rollback

If something goes wrong:

```bash
# Option 1: NixOS generation rollback
ssh root@rusty-vault.de "nixos-rebuild switch --rollback"

# Option 2: Git revert + redeploy
git revert HEAD
nix run .#nrs

# Option 3: Boot previous generation (if SSH is broken)
# Reboot server, select previous generation in GRUB
```

## Configuration Structure

The modular structure makes it easy to enable/disable services:

```nix
# configuration.nix
{
  imports = [
    # Comment out to disable a service
    ./modules/services/vaultwarden.nix
    # ./modules/services/miniflux.nix  # Disabled
  ];
}
```

## Secrets Management

Secrets are managed with SOPS. Before first deployment:

1. Generate age key on server:
   ```bash
   ssh root@rusty-vault.de "mkdir -p /var/lib/sops-nix && age-keygen > /var/lib/sops-nix/key.txt"
   ```

2. Get public key:
   ```bash
   ssh root@rusty-vault.de "age-keygen -y /var/lib/sops-nix/key.txt"
   ```

3. Add to `.sops.yaml` and re-encrypt secrets:
   ```bash
   sops updatekeys secrets/*.yaml
   ```

See [UPDATE_SECRETS.md](UPDATE_SECRETS.md) for detailed secret management.

## Tips

- **Always commit before deploying** - makes rollback easier
- **Test locally first** - use `nix flake check` to catch errors early
- **Watch the output** - nrs shows what's happening at each step
- **Keep secrets outside git** - they're encrypted but still shouldn't be public
