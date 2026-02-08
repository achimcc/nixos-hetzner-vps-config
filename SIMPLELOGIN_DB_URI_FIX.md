# SimpleLogin DB_URI Password Authentication Fix

## Critical Issue

The SimpleLogin app container was configured with:
```nix
DB_URI = "postgresql://simplelogin@simplelogin-postgres:5432/simplelogin";
```

**Problem:** This connection string lacks a password, causing PostgreSQL authentication to fail.

## Root Cause

PostgreSQL in Docker requires password authentication for TCP connections. The SimpleLogin application expects `DB_URI` in the format:
```
postgresql://username:password@host:port/database
```

## Solution

Since NixOS `oci-containers` doesn't support variable substitution in environment blocks, we must:

1. **Add DB_URI to SOPS secrets** with the password embedded
2. **Load DB_URI from environmentFiles** instead of hardcoding it
3. **Keep POSTGRES_PASSWORD** in environmentFiles for the PostgreSQL container

## Implementation

### Step 1: Add DB_URI to secrets/simplelogin.yaml

```bash
sops secrets/simplelogin.yaml
```

Add this line (replace `<PASSWORD>` with the actual password):
```yaml
simplelogin_db_uri: postgresql://simplelogin:<PASSWORD>@simplelogin-postgres:5432/simplelogin
```

The password should match the value in `simplelogin_db_password`.

### Step 2: Update configuration.nix

**Add SOPS secret declaration:**
```nix
sops.secrets.simplelogin_db_uri = {
  sopsFile = ./secrets/simplelogin.yaml;
  mode = "0400";
};
```

**Update simplelogin-app container:**
```nix
simplelogin-app = {
  # ... other config ...
  
  environment = {
    # Remove DB_URI from here - it will come from environmentFiles
    # Keep all other non-sensitive variables
  };
  
  environmentFiles = [
    config.sops.secrets.simplelogin_db_password.path  # For PostgreSQL container
    config.sops.secrets.simplelogin_db_uri.path       # For SimpleLogin app
  ];
};
```

### Step 3: Format of Secret Files

**simplelogin_db_password (for PostgreSQL container):**
```
POSTGRES_PASSWORD=<actual-password>
```

**simplelogin_db_uri (for SimpleLogin app):**
```
DB_URI=postgresql://simplelogin:<actual-password>@simplelogin-postgres:5432/simplelogin
```

Both files use the **same password** but in different formats.

## Why This Approach?

1. **Security:** Password stays encrypted in SOPS
2. **NixOS Compatibility:** Works within oci-containers limitations
3. **Standard Practice:** Matches how other containers (Ghostfolio) handle sensitive DB URIs
4. **Maintainability:** Password only needs to be changed in one place (SOPS file)

## Testing

After deployment:
```bash
# Check app logs
journalctl -u podman-simplelogin-app -f

# Should see successful DB connection
# No "authentication failed" errors
```

## References

- [SimpleLogin Docker Documentation](https://github.com/simple-login/app)
- [PostgreSQL Connection URIs](https://www.postgresql.org/docs/current/libpq-connect.html#LIBPQ-CONNSTRING)
