# PrivateBin Installation & Configuration Design

**Date:** 2026-02-05
**Target:** privatebin.rusty-vault.de
**Status:** Approved

## Overview

Install and configure PrivateBin on the NixOS VPS using the native `services.privatebin` module. PrivateBin is a minimalist, open-source pastebin with zero-knowledge encryption where all data is encrypted/decrypted in the browser.

## Requirements

- **Subdomain:** privatebin.rusty-vault.de (DNS configured with A/AAAA records)
- **Deployment:** NixOS native service
- **Default Expiration:** 1 month
- **File Uploads:** Enabled, 10MB limit
- **Discussions:** Enabled
- **Security:** Client-side encryption, integration with existing security hardening

## Architecture & Components

### Components
- **PrivateBin Service**: NixOS native `services.privatebin` module (version 1.7.8)
- **PHP-FPM**: Automatically configured by the PrivateBin module
- **Nginx**: Reverse proxy with automatic integration via `enableNginx = true`
- **ACME/Let's Encrypt**: Automatic SSL certificate for `privatebin.rusty-vault.de`
- **Data Storage**: `/var/lib/privatebin` for encrypted pastes

### Security Model
- **Client-side encryption**: Server has zero knowledge of paste data
- All paste data is encrypted at rest in the filesystem
- Integration with existing security headers and rate limiting
- Fail2ban protection through nginx logs
- CSP headers for additional client-side protection

### Integration
- Follows the pattern of existing services (Miniflux, Vaultwarden)
- Uses existing ACME configuration (ec384 keys)
- Integrates with existing firewall (ports 80/443 already open)
- Respects global nginx security settings

## Configuration Details

### PrivateBin Settings
```nix
services.privatebin = {
  enable = true;
  enableNginx = true;
  virtualHost = "privatebin.rusty-vault.de";

  settings = {
    main = {
      name = "rusty-vault PrivateBin";
      discussion = true;
      opendiscussion = true;
      fileupload = true;
      burnafterreadingselected = false;
      defaultformatter = "plaintext";
      languageselection = true;
      sizelimit = 10485760;  # 10MB
      template = "bootstrap";
      languagedefault = "de";
    };

    expire = {
      default = "1month";
    };

    expire_options = {
      "5min" = 300;
      "10min" = 600;
      "1hour" = 3600;
      "1day" = 86400;
      "1week" = 604800;
      "1month" = 2592000;
      "1year" = 31536000;
      "never" = 0;
    };

    formatter_options = {
      plaintext = "Plain Text";
      syntaxhighlighting = "Source Code";
      markdown = "Markdown";
    };

    model = {
      class = "Filesystem";
    };

    model_options = {
      dir = "/var/lib/privatebin/data";
    };

    purge = {
      limit = 300;
    };
  };
};
```

### Features Enabled
- **Expire Options**: 5min, 10min, 1h, 1d, 1w, **1m (default)**, 1y, never
- **File Upload**: Enabled, max 10MB
- **Discussions**: Enabled (open discussions allowed)
- **Burn-after-reading**: Available as option
- **Password Protection**: Available as option
- **Formatters**: Plain text, Source code (syntax highlighting), Markdown
- **Language**: German default, selection available

### Storage Backend
- **Type**: Filesystem (simple, reliable, suitable for VPS)
- **Path**: `/var/lib/privatebin/data`
- **Purge Limit**: 300 seconds (expired pastes are cleaned up)

## Nginx & Security

### Virtual Host Configuration
```nix
virtualHosts."privatebin.rusty-vault.de" = {
  enableACME = true;
  forceSSL = true;

  extraConfig = ''
    # Rate Limiting (stricter than general services)
    limit_req zone=general burst=10 nodelay;
    limit_conn addr 10;

    # Security Headers (consistent with other services)
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Permissions-Policy "accelerometer=(), camera=(), geolocation=(), gyroscope=(), magnetometer=(), microphone=(), payment=(), usb=()" always;
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;

    # PrivateBin-specific CSP for client-side encryption
    add_header Content-Security-Policy "default-src 'none'; base-uri 'self'; form-action 'self'; img-src 'self' data: blob:; script-src 'self'; style-src 'self'; font-src 'self'; frame-ancestors 'none';" always;

    # Upload size limit
    client_max_body_size 10M;
  '';
};
```

### Security Features
- **HSTS**: 2 years, includeSubDomains, preload
- **CSP**: Strict Content Security Policy for client-side encryption
- **Rate Limiting**: Burst of 10 requests (vs 20 for other services)
- **Upload Limit**: 10MB maximum
- **PHP-FPM**: Isolated process pool as `privatebin:nginx` user

### PHP-FPM Pool
- **User/Group**: privatebin:nginx
- **Memory Limit**: 128MB
- **Max Execution Time**: 60 seconds
- **Process Management**: Dynamic (automatic)

## Implementation Steps

### 1. Update NixOS Configuration
- Add `services.privatebin` block to `configuration.nix`
- Add nginx virtualHost for `privatebin.rusty-vault.de`
- Configure all settings as specified above

### 2. Deploy
```bash
sudo nixos-rebuild switch
```
- Service starts automatically
- ACME fetches SSL certificate automatically
- PHP-FPM pool starts automatically

### 3. Verification
```bash
# Check service status
systemctl status privatebin-config.service
systemctl status phpfpm-privatebin.service

# Check nginx configuration
nginx -t

# Test DNS resolution
dig privatebin.rusty-vault.de A
dig privatebin.rusty-vault.de AAAA

# Test HTTPS
curl -I https://privatebin.rusty-vault.de
```

### 4. Functional Testing
- Create a paste and verify retrieval
- Test file upload (up to 10MB)
- Test burn-after-reading feature
- Test discussion/comment feature
- Test various expiration options
- Test password protection
- Test different formatters (plaintext, code, markdown)

## Monitoring & Maintenance

### Logs
```bash
# PrivateBin PHP-FPM logs
journalctl -u phpfpm-privatebin -f

# Nginx access/error logs
tail -f /var/log/nginx/access.log
tail -f /var/log/nginx/error.log
```

### Automatic Protection
- Fail2ban automatically monitors nginx logs
- Rate limiting prevents abuse
- Automatic security updates via `system.autoUpgrade`

### Backup Strategy
- `/var/lib/privatebin` contains encrypted pastes
- Pastes are useless without client-side decryption keys (by design)
- Optional: Backup directory for disaster recovery
- Consider setting shorter default expiration if storage becomes an issue

## Security Considerations

### Client-Side Encryption
- All encryption/decryption happens in the browser
- Server never has access to unencrypted data
- Encryption key is in the URL fragment (never sent to server)

### Attack Surface
- File uploads enabled: Monitor for abuse
- Discussions enabled: Monitor for spam
- Rate limiting mitigates DoS attempts
- 10MB limit prevents resource exhaustion

### Compliance
- GDPR-friendly: Zero-knowledge architecture
- No user tracking or analytics
- No cookies required for basic functionality

## Success Criteria

- [ ] PrivateBin accessible at https://privatebin.rusty-vault.de
- [ ] SSL certificate valid and auto-renewing
- [ ] Can create and retrieve pastes
- [ ] File uploads work (up to 10MB)
- [ ] Discussions work
- [ ] All expiration options available
- [ ] Security headers present
- [ ] Rate limiting active
- [ ] Service logs clean (no errors)
- [ ] Integration with existing security infrastructure

## References

- [PrivateBin GitHub](https://github.com/PrivateBin/PrivateBin)
- [PrivateBin Configuration Wiki](https://github.com/PrivateBin/PrivateBin/wiki/Configuration)
- [NixOS PrivateBin Module](https://search.nixos.org/options?query=services.privatebin)
