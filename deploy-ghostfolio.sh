#!/usr/bin/env bash
set -euo pipefail

# Ghostfolio Deployment Script
# Automatisches Deployment von Ghostfolio mit SOPS-Secrets
# Container: ghostfolio, ghostfolio-postgres, ghostfolio-redis

SERVER="root@rusty-vault.de"

echo "=========================================="
echo "Ghostfolio Deployment Script"
echo "=========================================="
echo ""

# Check if configuration.nix exists
if [ ! -f "configuration.nix" ]; then
    echo "Error: configuration.nix not found in current directory"
    exit 1
fi

echo "Step 1: Generating secrets and creating encrypted secrets file on server..."

ssh "$SERVER" bash -s << 'ENDSSH'
set -euo pipefail

SECRETS_DIR="/etc/nixos/secrets"
SECRETS_FILE="$SECRETS_DIR/ghostfolio.yaml"
SOPS_CONFIG="/etc/nixos/.sops.yaml"

# Check if sops is available
if ! command -v sops &> /dev/null; then
    echo "Error: sops not found on server"
    exit 1
fi

# Check if secrets file already exists
if [ -f "$SECRETS_FILE" ]; then
    echo "ghostfolio.yaml already exists, skipping secret generation"
    echo "(Delete $SECRETS_FILE on server to regenerate)"
else
    echo "Generating random credentials..."

    POSTGRES_PASSWORD=$(openssl rand -hex 32)
    ACCESS_TOKEN_SALT=$(openssl rand -hex 32)
    JWT_SECRET_KEY=$(openssl rand -hex 32)

    echo "Creating plaintext secrets file..."
    TEMP_FILE=$(mktemp)
    cat > "$TEMP_FILE" << EOF
ghostfolio_env: |
    POSTGRES_USER=ghostfolio
    POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
    POSTGRES_DB=ghostfolio-db
    REDIS_HOST=ghostfolio-redis
    REDIS_PORT=6379
    ACCESS_TOKEN_SALT=${ACCESS_TOKEN_SALT}
    JWT_SECRET_KEY=${JWT_SECRET_KEY}
    DATABASE_URL=postgresql://ghostfolio:${POSTGRES_PASSWORD}@ghostfolio-postgres:5432/ghostfolio-db?connect_timeout=300&sslmode=prefer
    NODE_ENV=production
EOF

    echo "Encrypting with sops..."
    sops --config "$SOPS_CONFIG" -e "$TEMP_FILE" > "$SECRETS_FILE"
    rm -f "$TEMP_FILE"
    echo "Secrets created and encrypted successfully"
fi
ENDSSH

echo "Secrets ready"
echo ""

echo "Step 2: Copying configuration files to server..."
scp configuration.nix "$SERVER:/etc/nixos/"
scp .sops.yaml "$SERVER:/etc/nixos/"
echo "Configuration copied"
echo ""

echo "Step 3: Copying secrets file (if exists locally)..."
if [ -f "secrets/ghostfolio.yaml" ]; then
    scp secrets/ghostfolio.yaml "$SERVER:/etc/nixos/secrets/"
    echo "Local secrets file copied"
else
    echo "No local secrets/ghostfolio.yaml - using server-generated secrets"
fi
echo ""

echo "Step 4: Applying NixOS configuration..."
ssh "$SERVER" "nixos-rebuild switch"
echo "Configuration applied"
echo ""

echo "Step 5: Verifying deployment..."
echo ""

echo "Checking container status..."
ssh "$SERVER" "podman ps --format 'table {{.Names}}\t{{.Status}}' | grep -E 'ghostfolio|NAMES'" || echo "Warning: Could not list containers"
echo ""

echo "Checking Ghostfolio service..."
ssh "$SERVER" "systemctl is-active podman-ghostfolio" && echo "Ghostfolio container service is running" || echo "Warning: Ghostfolio container service is not running"
echo ""

echo "Checking Ghostfolio HTTP response..."
ssh "$SERVER" "curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:3333/ || true"
echo ""

echo "Checking NGINX service..."
ssh "$SERVER" "systemctl is-active nginx" && echo "NGINX is running" || echo "Warning: NGINX is not running"
echo ""

echo "Step 6: Recent Ghostfolio logs..."
ssh "$SERVER" "podman logs --tail 20 ghostfolio 2>&1" || echo "Warning: Could not fetch logs"
echo ""

echo "=========================================="
echo "Deployment complete!"
echo "=========================================="
echo ""
echo "Access Ghostfolio at: https://rusty-vault.de/ghostfolio/"
echo ""
echo "Useful commands:"
echo "  - View logs: ssh $SERVER 'podman logs -f ghostfolio'"
echo "  - Container status: ssh $SERVER 'podman ps'"
echo "  - Restart: ssh $SERVER 'systemctl restart podman-ghostfolio'"
echo "  - Restart all: ssh $SERVER 'systemctl restart podman-ghostfolio-postgres podman-ghostfolio-redis podman-ghostfolio'"
echo ""
echo "Note: Ghostfolio runs under /ghostfolio/ via nginx sub_filter."
echo "If the UI has issues with asset paths, consider using a subdomain instead."
echo ""
