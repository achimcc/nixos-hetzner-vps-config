#!/usr/bin/env bash
set -euo pipefail

# Miniflux Deployment Script
# Automatisches Deployment von Miniflux mit SOPS-Secrets

SERVER="root@rusty-vault.de"
MINIFLUX_ADMIN_USER="admin"

echo "=========================================="
echo "Miniflux Deployment Script"
echo "=========================================="
echo ""

# Check if password is provided as environment variable
if [ -z "${MINIFLUX_ADMIN_PASS:-}" ]; then
    echo "❌ Error: MINIFLUX_ADMIN_PASS environment variable not set"
    echo ""
    echo "Usage:"
    echo "  MINIFLUX_ADMIN_PASS='your-password' ./deploy-miniflux.sh"
    echo ""
    echo "Or set it in your shell first:"
    echo "  export MINIFLUX_ADMIN_PASS='your-password'"
    echo "  ./deploy-miniflux.sh"
    echo ""
    exit 1
fi

# Check if configuration.nix exists
if [ ! -f "configuration.nix" ]; then
    echo "❌ Error: configuration.nix not found in current directory"
    exit 1
fi

echo "📋 Step 1: Copying configuration to server..."
scp configuration.nix "$SERVER:/etc/nixos/"
echo "✅ Configuration copied"
echo ""

echo "📋 Step 2: Adding Miniflux admin credentials to SOPS secrets..."
ssh "$SERVER" bash -s << ENDSSH
set -euo pipefail

SECRETS_FILE="/etc/nixos/secrets/secrets.yaml"
MINIFLUX_ADMIN_USER="$MINIFLUX_ADMIN_USER"
MINIFLUX_ADMIN_PASS='$MINIFLUX_ADMIN_PASS'

# Check if sops is available
if ! command -v sops &> /dev/null; then
    echo "❌ Error: sops not found on server"
    exit 1
fi

# Decrypt, update, and re-encrypt
TEMP_DECRYPTED=\$(mktemp)
TEMP_UPDATED=\$(mktemp)

# Decrypt existing secrets
sops -d "\$SECRETS_FILE" > "\$TEMP_DECRYPTED"

# Check if miniflux_admin already exists
if grep -q "^miniflux_admin:" "\$TEMP_DECRYPTED"; then
    echo "⚠️  miniflux_admin secret already exists, updating..."
    # Remove existing miniflux_admin entry (handling multi-line)
    awk '/^miniflux_admin:/ {skip=1; next} /^[a-z_]+:/ {skip=0} !skip' "\$TEMP_DECRYPTED" > "\$TEMP_UPDATED"
else
    cp "\$TEMP_DECRYPTED" "\$TEMP_UPDATED"
fi

# Add miniflux_admin secret
cat >> "\$TEMP_UPDATED" << 'EOF'
miniflux_admin: |
  ADMIN_USERNAME=\${MINIFLUX_ADMIN_USER}
  ADMIN_PASSWORD=\${MINIFLUX_ADMIN_PASS}
EOF

# Replace variables
sed -i "s/\\\${MINIFLUX_ADMIN_USER}/\${MINIFLUX_ADMIN_USER}/g" "\$TEMP_UPDATED"
sed -i "s|\\\${MINIFLUX_ADMIN_PASS}|\${MINIFLUX_ADMIN_PASS}|g" "\$TEMP_UPDATED"

# Re-encrypt with sops
sops -e "\$TEMP_UPDATED" > "\$SECRETS_FILE"

# Cleanup
rm -f "\$TEMP_DECRYPTED" "\$TEMP_UPDATED"

echo "✅ Secret added successfully"
ENDSSH

echo "✅ Secrets updated"
echo ""

echo "📋 Step 3: Applying NixOS configuration..."
ssh "$SERVER" "nixos-rebuild switch"
echo "✅ Configuration applied"
echo ""

echo "📋 Step 4: Verifying deployment..."
echo ""

# Check service status
echo "Checking Miniflux service status..."
ssh "$SERVER" "systemctl is-active miniflux" && echo "✅ Miniflux service is running" || echo "❌ Miniflux service is not running"

echo ""
echo "Checking PostgreSQL service status..."
ssh "$SERVER" "systemctl is-active postgresql" && echo "✅ PostgreSQL service is running" || echo "❌ PostgreSQL service is not running"

echo ""
echo "Checking NGINX service status..."
ssh "$SERVER" "systemctl is-active nginx" && echo "✅ NGINX service is running" || echo "❌ NGINX service is not running"

echo ""
echo "📋 Step 5: Checking logs (last 20 lines)..."
echo ""
ssh "$SERVER" "journalctl -u miniflux -n 20 --no-pager"

echo ""
echo "=========================================="
echo "✅ Deployment complete!"
echo "=========================================="
echo ""
echo "🌐 Access Miniflux at: https://rusty-vault.de/miniflux/"
echo "👤 Username: $MINIFLUX_ADMIN_USER"
echo "🔑 Password: (from environment variable)"
echo ""
echo "📝 Next steps:"
echo "   1. Login to Miniflux web interface"
echo "   2. Change admin password in Settings → Users"
echo "   3. Add your RSS/Atom feeds"
echo ""
echo "🔍 Useful commands:"
echo "   - View logs: ssh $SERVER 'journalctl -u miniflux -f'"
echo "   - Check status: ssh $SERVER 'systemctl status miniflux'"
echo "   - Restart: ssh $SERVER 'systemctl restart miniflux'"
echo ""
