# rmfakecloud - Self-Hosted reMarkable Cloud

## Architektur

```
                    Internet
                       |
                   NGINX (443)
                   /         \
    remarkable.rusty-vault.de    *.remarkable.com / *.appspot.com
    (Let's Encrypt Cert)         (Self-Signed CA Cert)
                   \         /
                  rmfakecloud (Podman, Port 3000)
                       |
                  /var/lib/rmfakecloud/data
```

- **Web-Interface:** https://remarkable.rusty-vault.de (Let's Encrypt)
- **Tablet/App-Verbindung:** Selbst-signierte CA fuer reMarkable-Domains
- **Container:** `docker.io/ddvk/rmfakecloud:latest` via Podman
- **Daten:** `/var/lib/rmfakecloud/data` auf dem Server

---

## Tablet einrichten (reMarkable 2)

### Schritt 1: SSH-Zugang

1. Auf dem Tablet: **Einstellungen > Allgemein > Hilfe > Urheberrecht und Lizenzen**
2. Ganz unten steht das **root-Passwort** - notieren
3. Tablet per **USB-Kabel** mit dem Computer verbinden
4. Verbinden:

```bash
ssh root@10.11.99.1
```

### Schritt 2: DNS-Umleitung

Auf dem Tablet ausfuehren:

```bash
cat >> /etc/hosts << 'EOF'
77.42.71.141 hwr-production-dot-remarkable-production.appspot.com
77.42.71.141 service-manager-production-dot-remarkable-production.appspot.com
77.42.71.141 local.appspot.com
77.42.71.141 my.remarkable.com
77.42.71.141 ping.remarkable.com
77.42.71.141 internal.cloud.remarkable.com
77.42.71.141 webapp-prod.cloud.remarkable.engineering
77.42.71.141 eu.tectonic.remarkable.com
127.0.0.1 get-updates.cloud.remarkable.engineering
EOF
```

Die letzte Zeile blockiert automatische Firmware-Updates, die die Konfiguration zuruecksetzen wuerden.

### Schritt 3: CA-Zertifikat installieren

Vom eigenen Computer aus (im Projektverzeichnis):

```bash
scp secrets/rmfakecloud-ca/ca.crt root@10.11.99.1:/usr/local/share/ca-certificates/rmfakecloud-ca.crt
ssh root@10.11.99.1 update-ca-certificates
```

### Schritt 4: Tablet-UI neu starten

```bash
ssh root@10.11.99.1 systemctl restart xochitl
```

### Schritt 5: Mit rmfakecloud pairen

1. https://remarkable.rusty-vault.de im Browser oeffnen
2. Account erstellen (beim ersten Mal)
3. Einloggen und **Registrierungscode** generieren
4. Auf dem Tablet: **Einstellungen > Account** > Code eingeben
5. Sync pruefen: Notiz erstellen und im Web-Interface kontrollieren

---

## Desktop/Mobile Apps einrichten

### CA-Zertifikat installieren

| Plattform | Anleitung |
|-----------|-----------|
| **Linux** | `sudo cp ca.crt /usr/local/share/ca-certificates/rmfakecloud-ca.crt && sudo update-ca-certificates` |
| **macOS** | Doppelklick auf `ca.crt` > Keychain oeffnen > "Immer vertrauen" |
| **Windows** | Doppelklick auf `ca.crt` > "Zertifikat installieren" > "Vertrauenswuerdige Stammzertifizierungsstellen" |
| **iOS** | `ca.crt` per AirDrop/Mail senden > Profil installieren > Einstellungen > Allgemein > Info > Zertifikatsvertrauenseinstellungen > aktivieren |

### DNS-Umleitung (Hosts-Datei)

Auf jedem Geraet die gleichen Eintraege zur Hosts-Datei hinzufuegen:

- **Linux/macOS:** `/etc/hosts`
- **Windows:** `C:\Windows\System32\drivers\etc\hosts`

```
77.42.71.141 hwr-production-dot-remarkable-production.appspot.com
77.42.71.141 service-manager-production-dot-remarkable-production.appspot.com
77.42.71.141 local.appspot.com
77.42.71.141 my.remarkable.com
77.42.71.141 ping.remarkable.com
77.42.71.141 internal.cloud.remarkable.com
77.42.71.141 webapp-prod.cloud.remarkable.engineering
77.42.71.141 eu.tectonic.remarkable.com
```

Danach die reMarkable Desktop/Mobile App oeffnen - sie verbindet sich automatisch mit dem Self-Hosted-Server.

---

## Wartung

### Nach einem Firmware-Update des Tablets

Firmware-Updates setzen `/etc/hosts` und CA-Zertifikate zurueck. Schritte 2-4 wiederholen:

```bash
# Hosts neu setzen
ssh root@10.11.99.1 "cat >> /etc/hosts << 'EOF'
77.42.71.141 hwr-production-dot-remarkable-production.appspot.com
77.42.71.141 service-manager-production-dot-remarkable-production.appspot.com
77.42.71.141 local.appspot.com
77.42.71.141 my.remarkable.com
77.42.71.141 ping.remarkable.com
77.42.71.141 internal.cloud.remarkable.com
77.42.71.141 webapp-prod.cloud.remarkable.engineering
77.42.71.141 eu.tectonic.remarkable.com
127.0.0.1 get-updates.cloud.remarkable.engineering
EOF"

# CA-Zertifikat neu installieren
scp secrets/rmfakecloud-ca/ca.crt root@10.11.99.1:/usr/local/share/ca-certificates/rmfakecloud-ca.crt
ssh root@10.11.99.1 "update-ca-certificates && systemctl restart xochitl"
```

### Server-Dateien

| Datei | Beschreibung |
|-------|-------------|
| `modules/services/containers/rmfakecloud.nix` | NixOS-Modul (Podman + NGINX) |
| `secrets/rmfakecloud-ca/ca.crt` | CA-Zertifikat (auf Geraeten installieren) |
| `secrets/rmfakecloud-ca/ca.key` | CA-Privatschluessel (geheim halten) |
| `secrets/rmfakecloud-ca/server.crt` | Server-Zertifikat (NGINX) |
| `secrets/rmfakecloud-ca/server.key` | Server-Privatschluessel (NGINX) |
| `secrets/rmfakecloud.yaml` | SOPS-verschluesseltes JWT-Secret |

### Container-Logs pruefen

```bash
ssh root@rusty-vault.de podman logs rmfakecloud
```

### Zertifikat-Gueltigkeit

- CA-Zertifikat: 30 Jahre (bis ~2056)
- Server-Zertifikat: 10 Jahre (bis ~2036)
