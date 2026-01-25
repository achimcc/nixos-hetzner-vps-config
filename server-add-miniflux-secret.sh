#!/usr/bin/env bash
set -euo pipefail

# Add Miniflux Admin Secret to SOPS
# Run this script on the server as root
#
# Usage:
#   MINIFLUX_ADMIN_PASS='your-password' ./server-add-miniflux-secret.sh
#   OR
#   ./server-add-miniflux-secret.sh 'your-password'

SECRETS_FILE="/etc/nixos/secrets/secrets.yaml"
MINIFLUX_ADMIN_USER="admin"
SOPS_AGE_KEY_FILE="/var/lib/sops-nix/key.txt"

# Export Age key location for SOPS
export SOPS_AGE_KEY_FILE

echo "=========================================="
echo "Adding Miniflux Admin Secret to SOPS"
echo "=========================================="
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "❌ Error: Please run as root"
    exit 1
fi

# Get password from environment variable or argument
if [ -n "${MINIFLUX_ADMIN_PASS:-}" ]; then
    PASSWORD="$MINIFLUX_ADMIN_PASS"
elif [ $# -eq 1 ]; then
    PASSWORD="$1"
else
    echo "❌ Error: Password not provided"
    echo ""
    echo "Usage:"
    echo "  MINIFLUX_ADMIN_PASS='your-password' $0"
    echo "  OR"
    echo "  $0 'your-password'"
    echo ""
    exit 1
fi

# Check if secrets file exists
if [ ! -f "$SECRETS_FILE" ]; then
    echo "❌ Error: $SECRETS_FILE not found"
    exit 1
fi

echo "📋 Step 1: Finding SOPS binary..."
# Find sops in the system
if command -v sops &> /dev/null; then
    SOPS="sops"
elif [ -x "/run/current-system/sw/bin/sops" ]; then
    SOPS="/run/current-system/sw/bin/sops"
else
    # Use nix-shell to get sops
    echo "SOPS not in PATH, using nix-shell..."
    SOPS="nix-shell -p sops --run sops"
fi

echo "Using SOPS: $SOPS"
echo ""

echo "📋 Step 2: Decrypting secrets file..."
TEMP_DECRYPTED=$(mktemp)
TEMP_UPDATED=$(mktemp)

# Decrypt existing secrets
if [[ "$SOPS" == *"nix-shell"* ]]; then
    # Using nix-shell, need to handle differently
    if ! nix-shell -p sops --run "sops -d '$SECRETS_FILE'" > "$TEMP_DECRYPTED"; then
        echo "❌ Error: Failed to decrypt secrets file"
        rm -f "$TEMP_DECRYPTED" "$TEMP_UPDATED"
        exit 1
    fi
else
    if ! "$SOPS" -d "$SECRETS_FILE" > "$TEMP_DECRYPTED"; then
        echo "❌ Error: Failed to decrypt secrets file"
        rm -f "$TEMP_DECRYPTED" "$TEMP_UPDATED"
        exit 1
    fi
fi

echo "✅ Secrets decrypted"
echo ""

echo "Current secrets (decrypted):"
cat "$TEMP_DECRYPTED"
echo ""

echo "📋 Step 3: Adding miniflux_admin secret..."

# Check if miniflux_admin already exists
if grep -q "^miniflux_admin:" "$TEMP_DECRYPTED"; then
    echo "⚠️  miniflux_admin already exists, updating..."
    # Remove existing miniflux_admin entry (handling multi-line)
    awk '/^miniflux_admin:/ {skip=1; next} /^[a-z_]+:/ {skip=0} !skip' "$TEMP_DECRYPTED" > "$TEMP_UPDATED"
else
    echo "Adding new miniflux_admin secret..."
    cp "$TEMP_DECRYPTED" "$TEMP_UPDATED"
fi

# Add miniflux_admin secret
cat >> "$TEMP_UPDATED" << EOFINNER
miniflux_admin: |
  ADMIN_USERNAME=${MINIFLUX_ADMIN_USER}
  ADMIN_PASSWORD=${PASSWORD}
EOFINNER

echo ""
echo "Updated secrets (before encryption):"
cat "$TEMP_UPDATED"
echo ""

echo "📋 Step 4: Re-encrypting secrets file..."

# Get the Age public key from the private key
AGE_PUBLIC_KEY=$(grep "# public key:" "$SOPS_AGE_KEY_FILE" | awk '{print $4}')

if [ -z "$AGE_PUBLIC_KEY" ]; then
    echo "❌ Error: Could not extract Age public key from $SOPS_AGE_KEY_FILE"
    rm -f "$TEMP_DECRYPTED" "$TEMP_UPDATED"
    exit 1
fi

echo "Using Age public key: $AGE_PUBLIC_KEY"

# Re-encrypt with sops using the Age public key
if [[ "$SOPS" == *"nix-shell"* ]]; then
    # Using nix-shell, need to handle differently
    if ! nix-shell -p sops --run "sops -e --age '$AGE_PUBLIC_KEY' '$TEMP_UPDATED'" > "$SECRETS_FILE"; then
        echo "❌ Error: Failed to encrypt secrets file"
        rm -f "$TEMP_DECRYPTED" "$TEMP_UPDATED"
        exit 1
    fi
else
    if ! "$SOPS" -e --age "$AGE_PUBLIC_KEY" "$TEMP_UPDATED" > "$SECRETS_FILE"; then
        echo "❌ Error: Failed to encrypt secrets file"
        rm -f "$TEMP_DECRYPTED" "$TEMP_UPDATED"
        exit 1
    fi
fi

# Cleanup
rm -f "$TEMP_DECRYPTED" "$TEMP_UPDATED"

echo "✅ Secret added and encrypted successfully"
echo ""
echo "=========================================="
echo "✅ Done!"
echo "=========================================="
echo ""
echo "Next step: Apply configuration"
echo "  nixos-rebuild switch"
echo ""
