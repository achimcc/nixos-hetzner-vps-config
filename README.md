# NixOS Hetzner VPS - Vaultwarden Server

Gehärtete NixOS-Konfiguration für einen Vaultwarden Password Manager auf einem Hetzner VPS.

## Features

- **Vaultwarden** - Selbst-gehosteter Bitwarden-kompatibler Password Manager
- **NGINX** - Reverse Proxy mit Let's Encrypt TLS
- **SOPS-nix** - Verschlüsselte Secrets mit Age
- **LUKS** - Festplattenverschlüsselung mit Remote-Unlock via SSH
- **Security Hardening** - Umfassende Systemhärtung

## Komponenten

| Dienst | Port | Beschreibung |
|--------|------|--------------|
| Vaultwarden | 8222 (intern) | Password Manager |
| NGINX | 80, 443 | Reverse Proxy + TLS |
| SSH | 22 | Administration |

## Voraussetzungen

- Hetzner VPS mit NixOS
- Domain mit DNS auf Server-IP
- Lokal: `sops`, `age` installiert

## Struktur

```
.
├── configuration.nix      # Haupt-Konfiguration
├── hardware-configuration.nix
├── secrets/
│   └── secrets.yaml       # Verschlüsselte Credentials (SOPS)
├── .sops.yaml             # SOPS-Konfiguration
└── README.md
```

## Installation

### 1. Repository klonen

```bash
git clone <repo-url>
cd nixos-hetzner-vps-config
```

### 2. Age-Schlüssel auf Server erstellen

```bash
ssh root@<server> "mkdir -p /var/lib/sops-nix && \
  nix-shell -p age --run 'age-keygen -o /var/lib/sops-nix/key.txt' && \
  chmod 600 /var/lib/sops-nix/key.txt && \
  cat /var/lib/sops-nix/key.txt"
```

Den Public Key (`age1...`) notieren.

### 3. SOPS konfigurieren

`.sops.yaml` mit dem Public Key aktualisieren:

```yaml
keys:
  - &server age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
creation_rules:
  - path_regex: secrets/.*\.yaml$
    key_groups:
      - age:
          - *server
```

### 4. Secrets erstellen

```bash
# Plaintext erstellen
cat > secrets/secrets.yaml << 'EOF'
smtp_password: 'SMTP_PASSWORD=dein-passwort-hier'
EOF

# Verschlüsseln
sops -e -i secrets/secrets.yaml
```

**Hinweis:** Backslashes im Passwort müssen verdoppelt werden (`\` → `\\`).

### 5. Konfiguration anpassen

In `configuration.nix` anpassen:
- Domain (`rusty-vault.de`)
- E-Mail-Adressen
- SSH Public Keys
- SMTP-Einstellungen

### 6. Deployment

```bash
# Dateien auf Server kopieren
scp -r configuration.nix secrets/ .sops.yaml root@<server>:/etc/nixos/

# Konfiguration aktivieren
ssh root@<server> "nixos-rebuild switch"
```

## Security Hardening

### Kernel

- ASLR (Address Space Layout Randomization)
- Kernel-Pointer versteckt (`kptr_restrict=2`)
- ptrace-Schutz (`yama.ptrace_scope=2`)
- BPF JIT Hardening
- Ungenutzte Kernel-Module blockiert

### Netzwerk

- ICMP/IP-Redirects deaktiviert
- Source-Routing blockiert
- SYN-Cookies aktiviert
- Reverse-Path-Filtering
- TCP-Timestamps deaktiviert

### SSH

- Nur Key-Authentifizierung
- Starke Kryptografie (Curve25519, ChaCha20-Poly1305)
- X11/Agent/TCP-Forwarding deaktiviert
- MaxAuthTries=3

### Firewall

- Nur Ports 22, 80, 443 offen
- SYN-Flood-Schutz
- ICMP Rate-Limiting
- Logging für abgelehnte Verbindungen

### NGINX

- Security Headers (HSTS, X-Frame-Options, etc.)
- Rate-Limiting (10 req/s)
- Server-Version versteckt
- TLS 1.2+ mit starken Cipher-Suites

### Zusätzlich

- **Fail2ban** - Brute-Force-Schutz
- **AppArmor** - Mandatory Access Control
- **Auditd** - Security-Event-Logging
- **DNS-over-TLS** - Verschlüsselte DNS-Anfragen (Quad9)
- **Chrony** - Sichere Zeitsynchronisation
- **Auto-Updates** - Tägliche Sicherheitsupdates

## Benutzer

| User | Zweck |
|------|-------|
| `root` | Notfall/LUKS-Unlock (SSH-Key) |
| `admin` | Tägliche Administration (sudo) |

Login:
```bash
ssh admin@<server>
sudo -i  # Root-Shell
```

## Wartung

### Updates

Automatische Updates sind aktiviert (04:00 Uhr). Manuell:

```bash
ssh root@<server> "nixos-rebuild switch --upgrade"
```

### Logs prüfen

```bash
# Vaultwarden
journalctl -u vaultwarden -f

# Fail2ban
fail2ban-client status sshd

# Audit-Log
ausearch -k logins
```

### Secrets rotieren

```bash
# Lokal bearbeiten (benötigt Server-Key oder eigenen Key)
sops secrets/secrets.yaml

# Auf Server deployen
scp secrets/secrets.yaml root@<server>:/etc/nixos/secrets/
ssh root@<server> "nixos-rebuild switch"
```

## Troubleshooting

### SMTP funktioniert nicht

```bash
# Passwort prüfen
ssh root@<server> "cat /run/secrets/smtp_password"

# Vaultwarden-Logs
journalctl -u vaultwarden | grep -i smtp
```

### SSH-Zugang verloren

1. Hetzner Rescue-System booten
2. LUKS-Partition entsperren
3. Konfiguration reparieren

### ACME/TLS-Fehler

```bash
# Zertifikat-Status
systemctl status acme-rusty-vault.de

# Manuell erneuern
systemctl start acme-rusty-vault.de
```

## Backup

Wichtige Daten:
- `/var/lib/vaultwarden/` - Vaultwarden-Datenbank
- `/var/lib/sops-nix/key.txt` - Age Private Key
- `/etc/secrets/initrd/` - LUKS-Unlock SSH-Keys

```bash
# Backup erstellen
ssh root@<server> "tar -czf /tmp/backup.tar.gz \
  /var/lib/vaultwarden \
  /var/lib/sops-nix/key.txt"
scp root@<server>:/tmp/backup.tar.gz ./
```

## Lizenz

MIT
