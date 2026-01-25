#!/usr/bin/env bash
set -euo pipefail

# Add Miniflux Secret to SOPS
# This script adds the miniflux_admin secret on the server

SERVER="root@rusty-vault.de"

echo "=========================================="
echo "Adding Miniflux Secret to SOPS"
echo "=========================================="
echo ""

ssh "$SERVER" bash << 'ENDSSH'
set -euo pipefail

SECRETS_FILE="/etc/nixos/secrets/secrets.yaml"
MINIFLUX_ADMIN_USER="admin"
MINIFLUX_ADMIN_PASS='AA$KYRWub2V#nunDbYhs4kQDvEq4sZ'

echo "Adding miniflux_admin secret to SOPS file..."

# Check if sops is available
if ! command -v sops &> /dev/null; then
    echo "❌ Error: sops not found on server"
    exit 1
fi

# Decrypt, update, and re-encrypt
TEMP_DECRYPTED=$(mktemp)
TEMP_UPDATED=$(mktemp)

# Decrypt existing secrets
sops -d "$SECRETS_FILE" > "$TEMP_DECRYPTED"

echo "Current secrets (decrypted):"
cat "$TEMP_DECRYPTED"
echo ""

# Check if miniflux_admin already exists
if grep -q "^miniflux_admin:" "$TEMP_DECRYPTED"; then
    echo "⚠️  miniflux_admin secret already exists, updating..."
    # Remove existing miniflux_admin entry (handling multi-line)
    awk '/^miniflux_admin:/ {skip=1; next} /^[a-z_]+:/ {skip=0} !skip' "$TEMP_DECRYPTED" > "$TEMP_UPDATED"
else
    cp "$TEMP_DECRYPTED" "$TEMP_UPDATED"
fi

# Add miniflux_admin secret
cat >> "$TEMP_UPDATED" << 'EOF'
miniflux_admin: |
  ADMIN_USERNAME=admin
  ADMIN_PASSWORD=AA$KYRWub2V#nunDbYhs4kQDvEq4sZ
EOF

echo "Updated secrets (before encryption):"
cat "$TEMP_UPDATED"
echo ""

# Re-encrypt with sops
sops -e "$TEMP_UPDATED" > "$SECRETS_FILE"

# Cleanup
rm -f "$TEMP_DECRYPTED" "$TEMP_UPDATED"

echo "✅ Secret added successfully"
ENDSSH

echo ""
echo "=========================================="
echo "✅ Secret added to SOPS!"
echo "=========================================="
echo ""
echo "Now run on the server:"
echo "  ssh $SERVER"
echo "  nixos-rebuild switch"
echo ""
