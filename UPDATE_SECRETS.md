# CRITICAL: Update SOPS Secrets for DB_URI

## Action Required

You must add the `simplelogin_db_uri` secret to the SOPS file before deployment.

## Steps

1. **Edit the encrypted secrets file:**
   ```bash
   cd /home/achim/Projects/vpn/nixos-hetzner-vps-config/.worktrees/add-simplelogin
   sops secrets/simplelogin.yaml
   ```

2. **Add the new DB_URI secret:**
   
   The file currently contains:
   ```yaml
   simplelogin_db_password: POSTGRES_PASSWORD=<password>
   simplelogin_flask_secret: <flask-secret>
   simplelogin_email_secret: <email-secret>
   ```
   
   Add this line (replace `<PASSWORD>` with the **same password** from `simplelogin_db_password`):
   ```yaml
   simplelogin_db_uri: DB_URI=postgresql://simplelogin:<PASSWORD>@simplelogin-postgres:5432/simplelogin
   ```

3. **Example with dummy password:**
   
   If `simplelogin_db_password` contains:
   ```
   POSTGRES_PASSWORD=mySecurePassword123
   ```
   
   Then `simplelogin_db_uri` should be:
   ```
   DB_URI=postgresql://simplelogin:mySecurePassword123@simplelogin-postgres:5432/simplelogin
   ```

4. **Save and exit** (SOPS will automatically encrypt the new value)

## Verification

After editing, the decrypted file should look like:
```yaml
simplelogin_db_password: POSTGRES_PASSWORD=<password>
simplelogin_db_uri: DB_URI=postgresql://simplelogin:<password>@simplelogin-postgres:5432/simplelogin
simplelogin_flask_secret: <flask-secret>
simplelogin_email_secret: <email-secret>
```

## Important Notes

- **Both secrets must use the SAME password**
- The format is different:
  - `simplelogin_db_password`: `POSTGRES_PASSWORD=<password>` (for PostgreSQL container)
  - `simplelogin_db_uri`: `DB_URI=postgresql://simplelogin:<password>@...` (for SimpleLogin app)
- Do NOT include spaces around the `=` sign
- The password should be the one generated in Task #1

## Why This Is Required

PostgreSQL requires password authentication for TCP connections. The SimpleLogin app needs the full connection URI with embedded password. NixOS oci-containers doesn't support variable substitution, so we must provide the complete URI via SOPS.

## Deployment Blocker

**The system will fail to deploy without this change.** The SimpleLogin app will not be able to connect to the database.
