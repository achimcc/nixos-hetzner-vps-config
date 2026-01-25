# Server Scripts

Scripts that should be run on the server (not locally).

## server-add-miniflux-secret.sh

Adds the Miniflux admin credentials to the SOPS secrets file.

**Usage on server:**

```bash
# 1. Copy script to server
scp server-add-miniflux-secret.sh root@rusty-vault.de:/tmp/

# 2. SSH to server and run with password as argument
ssh root@rusty-vault.de "bash /tmp/server-add-miniflux-secret.sh 'your-password-here'"

# OR run with environment variable
ssh root@rusty-vault.de "MINIFLUX_ADMIN_PASS='your-password-here' bash /tmp/server-add-miniflux-secret.sh"

# 3. Apply configuration
ssh root@rusty-vault.de "nixos-rebuild switch"
```

**One-liner (copy script, add secret, rebuild):**

```bash
scp server-add-miniflux-secret.sh root@rusty-vault.de:/tmp/ && \
ssh root@rusty-vault.de "bash /tmp/server-add-miniflux-secret.sh 'your-password-here' && nixos-rebuild switch"
```

**What it does:**
1. Decrypts `/etc/nixos/secrets/secrets.yaml`
2. Adds `miniflux_admin` secret with admin credentials
3. Re-encrypts the file with SOPS
4. Shows you what was added (before encryption)

**Security:**
- ✅ No password hardcoded in script
- ✅ Password passed as argument or environment variable
- ✅ Safe to commit to git
- ✅ Password only visible during execution (not logged)

**Password Requirements:**
- Minimum 6 characters
- Use single quotes to avoid shell escaping issues
- Avoid backticks and dollar signs if possible
