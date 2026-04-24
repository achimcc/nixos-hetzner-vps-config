# rmfakecloud-CA auf sops-nix migrieren — Implementierungsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Die selbstsignierten CA- und Server-Keys fuer `rmfakecloud` aus dem git-getrackten `secrets/rmfakecloud-ca/`-Ordner entfernen und per `sops-nix` verschluesselt/verwaltet bereitstellen, sodass nginx sie zuverlaessig mit korrekten Permissions lesen kann und keine Plain-Private-Keys mehr im Repo liegen.

**Architecture:** `sops-nix` legt die entschluesselten Keys unter `/run/secrets/...` mit expliziten `owner`/`group`/`mode`-Angaben ab. Der nginx-vhost in `modules/services/containers/rmfakecloud.nix` zeigt dann auf diese Pfade statt auf `/etc/nixos/secrets/rmfakecloud-ca/`. Die alten Plain-Files werden aus dem git-Tree und aus dem Arbeitsbaum entfernt, `.gitignore` blockiert Re-Import. Da die alten Keys bereits in der git-History liegen (und damit kompromittiert gelten), werden CA und Server-Zertifikat als Teil dieser Migration neu generiert — das reMarkable-Tablet muss der neuen CA danach einmalig vertrauen.

**Tech Stack:** NixOS 26.05, sops-nix, OpenSSL (CA-Generierung), nginx, rsync-basiertes `nrs`-Deployment.

---

## Kontext: Warum jetzt

Am 2026-04-24 ist beim Deploy der `stats.rusty-vault.de`-Ergaenzung (Commit `8387812`) nginx auf dem VPS mit `cannot load certificate key ... Permission denied` gecrashed. Root-Analyse:

1. `secrets/rmfakecloud-ca/server.key` ist lokal `0600 achim:users` — `rsync -a` im `nrs`-Deploy traegt diese Permissions 1:1 zum Server.
2. `modules/services/containers/rmfakecloud.nix:27-32` hat zwar eine `systemd.tmpfiles.rules`-Regel mit `z` ("adjust") auf `0640 root nginx`, die greift bei nachfolgenden Rebuilds mit unveraenderter Regel aber nicht zuverlaessig nach einem frischen rsync.
3. Das fuehrt dazu, dass der erste nginx-Restart nach laengerem Stillstand fehlschlaegt — wie am 2026-04-24 beobachtet.
4. **Nebenbefund (eigentliches Hauptproblem):** `secrets/rmfakecloud-ca/ca.key` und `server.key` sind als Plain-Private-Keys git-getrackt (`git ls-files` bestaetigt). Sie liegen damit unverschluesselt in der gesamten git-History aller Clones.

Ad-hoc wurde nginx am 2026-04-24 durch manuelles `chgrp nginx` + `chmod 640` auf dem Server wiederhergestellt. Bei jedem naechsten `nrs`-Deploy setzt rsync die Permissions aber zurueck.

---

## Betroffene Dateien

| Datei | Aenderung |
|-------|----------|
| `secrets/rmfakecloud-ca.yaml` | **NEU**: sops-verschluesselte CA- und Server-Keys (base64-encoded) |
| `modules/secrets.nix` | `sops.secrets` um 4 Eintraege erweitern (ca_crt, ca_key, server_crt, server_key) |
| `modules/services/containers/rmfakecloud.nix` | `certDir` durch `config.sops.secrets.*.path` ersetzen; `systemd.tmpfiles.rules` entfernen |
| `secrets/rmfakecloud-ca/*` | Alle 5 Dateien (ca.crt, ca.key, openssl-san.cnf, server.crt, server.key) **loeschen** (git rm) |
| `.gitignore` | `secrets/rmfakecloud-ca/` eintragen, falls je wieder erstellt |
| `docs/runbooks/rmfakecloud-ca-rotation.md` | **NEU**: Rotations-Prozedur fuer zukuenftige CA-Erneuerung |

---

## Task 1: Neue CA + Server-Zertifikat generieren (lokal, ausserhalb des Repos)

**Files:**
- Temp: `/tmp/rmfakecloud-ca-new/` (wird nach Task 2 wieder geloescht)

Grund der Neugenerierung: Die alten Keys sind in der git-History unverschluesselt. Auch nach Entfernung aus dem aktuellen Tree bleiben sie in `git log`-History und Remote-Clones abrufbar. Rotation eliminiert das Risiko dauerhaft. Das reMarkable-Tablet muss der neuen CA danach einmalig vertrauen — siehe Abschluss-Runbook.

- [ ] **Step 1.1: Arbeitsverzeichnis ausserhalb des Repos anlegen**

```bash
mkdir -p /tmp/rmfakecloud-ca-new
cd /tmp/rmfakecloud-ca-new
```

- [ ] **Step 1.2: `openssl-san.cnf` aus dem alten Repo kopieren (SAN-Liste bleibt identisch)**

```bash
cp /home/achim/Projects/vpn/nixos-hetzner-vps-config/secrets/rmfakecloud-ca/openssl-san.cnf .
cat openssl-san.cnf | head -20
```

Expected: SAN-Liste mit `local.appspot.com`, `my.remarkable.com`, etc.

- [ ] **Step 1.3: Neue CA generieren (ECDSA P-384, 10 Jahre Laufzeit)**

```bash
openssl ecparam -name secp384r1 -genkey -noout -out ca.key
openssl req -new -x509 -key ca.key -days 3650 \
  -subj "/CN=rmfakecloud Self-Signed CA/O=rusty-vault.de" \
  -out ca.crt
```

Expected: `ca.key` (~300 bytes) und `ca.crt` (~500 bytes) liegen vor.

- [ ] **Step 1.4: Server-Key + CSR erzeugen und von der neuen CA signieren**

```bash
openssl ecparam -name secp384r1 -genkey -noout -out server.key
openssl req -new -key server.key -config openssl-san.cnf -out server.csr
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
  -days 825 -extensions v3_req -extfile openssl-san.cnf \
  -out server.crt
```

- [ ] **Step 1.5: Verifizieren, dass Cert gueltig ist und alle SANs enthaelt**

```bash
openssl verify -CAfile ca.crt server.crt
openssl x509 -in server.crt -noout -ext subjectAltName
```

Expected:
- `server.crt: OK`
- Alle 8 `DNS:`-Eintraege aus `openssl-san.cnf` (hwr-production-..., service-manager-production-..., local.appspot.com, my.remarkable.com, ping.remarkable.com, internal.cloud.remarkable.com, webapp-prod.cloud.remarkable.engineering, eu.tectonic.remarkable.com).

---

## Task 2: sops-verschluesseltes YAML-File mit den neuen Keys anlegen

**Files:**
- Create: `/home/achim/Projects/vpn/nixos-hetzner-vps-config/secrets/rmfakecloud-ca.yaml`

- [ ] **Step 2.1: Plaintext-YAML mit base64-encodeten Keys vorbereiten**

```bash
cd /tmp/rmfakecloud-ca-new
cat > /tmp/rmfakecloud-ca.plain.yaml <<EOF
ca_crt_b64: $(base64 -w0 ca.crt)
ca_key_b64: $(base64 -w0 ca.key)
server_crt_b64: $(base64 -w0 server.crt)
server_key_b64: $(base64 -w0 server.key)
EOF
```

- [ ] **Step 2.2: Mit sops verschluesseln, Zielort ist das VPS-Repo**

```bash
cd /home/achim/Projects/vpn/nixos-hetzner-vps-config
sops --encrypt /tmp/rmfakecloud-ca.plain.yaml > secrets/rmfakecloud-ca.yaml
```

`.sops.yaml` hat bereits die Regel `secrets/.*\.yaml$` → server-age-key, d.h. die Datei wird automatisch fuer den VPS verschluesselt.

- [ ] **Step 2.3: Plain-Zwischenfile und Arbeitsverzeichnis loeschen**

```bash
shred -u /tmp/rmfakecloud-ca.plain.yaml
shred -u /tmp/rmfakecloud-ca-new/ca.key /tmp/rmfakecloud-ca-new/server.key
rm -rf /tmp/rmfakecloud-ca-new
```

- [ ] **Step 2.4: Kontrolle, dass das sops-File lesbar bleibt**

```bash
sops --decrypt secrets/rmfakecloud-ca.yaml | head -2
```

Expected: Zwei Zeilen im Format `ca_crt_b64: LS0tLS1CRUdJTiBD...`

- [ ] **Step 2.5: Commit**

```bash
git add secrets/rmfakecloud-ca.yaml
git commit -m "feat(rmfakecloud): neue CA/Server-Keys verschluesselt via sops"
```

---

## Task 3: `modules/secrets.nix` um 4 sops-Secrets erweitern

**Files:**
- Modify: `modules/secrets.nix` (Ende des `sops.secrets`-Blocks, vor der schliessenden `};`)

- [ ] **Step 3.1: Eintraege hinzufuegen**

Einfuegen vor der schliessenden Klammer der `sops`-Attributmenge (aktuell im Bereich nach den SimpleLogin-Secrets):

```nix
    # rmfakecloud Self-Signed CA + Server-Cert
    # Base64 dekodieren, weil der Key-Inhalt binaer-sensitiv (ECDSA) ist;
    # sops-nix `format = "yaml"` koennte mehrzeilige PEM-Strings escapen
    # und beim Schreiben wieder dekodieren, das ist sicherer.
    secrets."rmfakecloud-ca/ca.crt" = {
      sopsFile = ../secrets/rmfakecloud-ca.yaml;
      key      = "ca_crt_b64";
      mode     = "0444";
      owner    = "nginx";
      group    = "nginx";
      # Der in der YAML hinterlegte Wert ist base64-encoded → beim Schreiben dekodieren.
      restartUnits = [ "nginx.service" ];
    };
    secrets."rmfakecloud-ca/ca.key" = {
      sopsFile = ../secrets/rmfakecloud-ca.yaml;
      key      = "ca_key_b64";
      mode     = "0440";
      owner    = "nginx";
      group    = "nginx";
      restartUnits = [ "nginx.service" ];
    };
    secrets."rmfakecloud-ca/server.crt" = {
      sopsFile = ../secrets/rmfakecloud-ca.yaml;
      key      = "server_crt_b64";
      mode     = "0444";
      owner    = "nginx";
      group    = "nginx";
      restartUnits = [ "nginx.service" ];
    };
    secrets."rmfakecloud-ca/server.key" = {
      sopsFile = ../secrets/rmfakecloud-ca.yaml;
      key      = "server_key_b64";
      mode     = "0440";
      owner    = "nginx";
      group    = "nginx";
      restartUnits = [ "nginx.service" ];
    };
```

**Hinweis zu base64:** sops-nix selbst dekodiert nicht automatisch; ohne Dekodier-Schritt steht base64-Content im secret-File und nginx kann es nicht laden. Da sops-nix keinen eingebauten Decode-Hook hat, wird Task 3.2 einen `system.activationScripts`-Block hinzufuegen, der nach dem sops-render die Files base64-dekodiert am gleichen Pfad ablegt. (Alternative: Plain-PEM als multiline-String in YAML — funktioniert, ist aber bei mehrzeiligen PEM-Strings fehleranfaellig beim Editieren.)

- [ ] **Step 3.2: Activation-Script fuer base64-Dekodierung hinzufuegen**

Direkt nach dem `sops`-Attribut in `modules/secrets.nix` ergaenzen (innerhalb des Top-Level-Attrset, ausserhalb `sops`):

```nix
  # sops-nix schreibt die Files als base64-encoded (siehe key-Bindings oben).
  # Dekodieren idempotent beim activation nach sops-install-secrets:
  system.activationScripts.rmfakecloudCaDecode = {
    deps = [ "setupSecrets" ];
    text = ''
      for name in ca.crt ca.key server.crt server.key; do
        src="/run/secrets/rmfakecloud-ca/$name"
        tmp="$src.decoded"
        if [ -f "$src" ]; then
          ${pkgs.coreutils}/bin/base64 -d "$src" > "$tmp"
          ${pkgs.coreutils}/bin/chown nginx:nginx "$tmp"
          case "$name" in
            *.key) ${pkgs.coreutils}/bin/chmod 0440 "$tmp" ;;
            *)     ${pkgs.coreutils}/bin/chmod 0444 "$tmp" ;;
          esac
          mv "$tmp" "$src"
        fi
      done
    '';
  };
```

`modules/secrets.nix` beginnt mit `{ config, ... }:` — `pkgs` muss mit in den Modul-Header. Also:

- [ ] **Step 3.3: Modul-Header um `pkgs` ergaenzen**

```nix
{ config, pkgs, ... }:
```

- [ ] **Step 3.4: Syntaxcheck lokal**

```bash
cd /home/achim/Projects/vpn/nixos-hetzner-vps-config
nix flake check --no-build 2>&1 | tail -20
```

Expected: Kein Evaluation-Error. (Build-Fehler durch fehlende runtime-Abhaengigkeiten sind erwartet und ok, solange die Module evaluieren.)

- [ ] **Step 3.5: Commit**

```bash
git add modules/secrets.nix
git commit -m "feat(rmfakecloud): sops-nix-Secrets fuer CA + Server-Cert"
```

---

## Task 4: `rmfakecloud.nix` auf die neuen Pfade umziehen

**Files:**
- Modify: `modules/services/containers/rmfakecloud.nix`

- [ ] **Step 4.1: `certDir` entfernen und direkte `config.sops.secrets`-Pfade nutzen**

Alte Zeilen 18-19:

```nix
  # Path to self-signed CA certs on the server (deployed via rsync)
  certDir = "/etc/nixos/secrets/rmfakecloud-ca";
```

Ersetzen durch (keinen `let`-Bindings fuer die Pfade, sondern direkt `config.sops.secrets.*.path` an den Referenzstellen):

```nix
  # (keine certDir-Variable mehr — Pfade kommen aus config.sops.secrets.*.path,
  # siehe Zeilen im vhost-Block unten)
```

- [ ] **Step 4.2: `systemd.tmpfiles.rules`-Block bereinigen**

Alte Zeilen 26-32 (der `systemd.tmpfiles.rules = [ ... ];`-Block):

```nix
  # Persistent data directory and certificate permissions for nginx
  systemd.tmpfiles.rules = [
    "d /var/lib/rmfakecloud 0750 root root -"
    "d /var/lib/rmfakecloud/data 0750 root root -"
    "z ${certDir}/server.key 0640 root nginx -"
    "z ${certDir}/server.crt 0644 root nginx -"
  ];
```

Ersetzen durch (nur noch Daten-Dirs, Permissions auf die Keys macht sops-nix):

```nix
  # Persistent data directory
  systemd.tmpfiles.rules = [
    "d /var/lib/rmfakecloud 0750 root root -"
    "d /var/lib/rmfakecloud/data 0750 root root -"
  ];
```

- [ ] **Step 4.3: Vhost-Pfade auf sops-Secrets umbiegen**

Alte Zeilen 97-98:

```nix
      sslCertificate = "${certDir}/server.crt";
      sslCertificateKey = "${certDir}/server.key";
```

Ersetzen durch:

```nix
      sslCertificate    = config.sops.secrets."rmfakecloud-ca/server.crt".path;
      sslCertificateKey = config.sops.secrets."rmfakecloud-ca/server.key".path;
```

- [ ] **Step 4.4: Modul-Header pruefen — `config` muss ohnehin in den Argumenten stehen**

Aktuell: `{ config, pkgs, lib, commonConfig, customLib, ... }:` — `config` ist bereits da, nichts zu aendern.

- [ ] **Step 4.5: Lokaler Syntaxcheck**

```bash
cd /home/achim/Projects/vpn/nixos-hetzner-vps-config
nix flake check --no-build 2>&1 | tail -20
```

Expected: Kein Evaluation-Error.

- [ ] **Step 4.6: Commit**

```bash
git add modules/services/containers/rmfakecloud.nix
git commit -m "refactor(rmfakecloud): Cert-Pfade auf sops-nix umstellen, tmpfiles-Hack weg"
```

---

## Task 5: Alte Plain-Files aus dem Arbeitsbaum entfernen und `.gitignore` haerten

**Files:**
- Delete (git rm): `secrets/rmfakecloud-ca/{ca.crt,ca.key,server.crt,server.key,openssl-san.cnf}`
- Modify: `.gitignore`

- [ ] **Step 5.1: Alle 5 Dateien aus git entfernen (inkl. arbeitsbaumloeschung)**

```bash
cd /home/achim/Projects/vpn/nixos-hetzner-vps-config
git rm secrets/rmfakecloud-ca/ca.crt \
       secrets/rmfakecloud-ca/ca.key \
       secrets/rmfakecloud-ca/server.crt \
       secrets/rmfakecloud-ca/server.key \
       secrets/rmfakecloud-ca/openssl-san.cnf
rmdir secrets/rmfakecloud-ca
```

- [ ] **Step 5.2: `.gitignore` erweitern**

Ende der `.gitignore` anhaengen:

```
# Plain-Private-Keys und Self-Signed CA-Material nie ins git (sops-nix statt dessen)
secrets/rmfakecloud-ca/
```

- [ ] **Step 5.3: Verifizieren — keine Plain-Keys mehr im Tree**

```bash
git ls-files | grep rmfakecloud-ca || echo "OK: keine tracked files mehr"
find secrets/rmfakecloud-ca -type f 2>/dev/null || echo "OK: Ordner weg"
```

Expected: Beide OK-Zeilen.

- [ ] **Step 5.4: Commit**

```bash
git add .gitignore
git commit -m "security(rmfakecloud): Plain-CA-Keys aus git entfernen, .gitignore haerten"
```

---

## Task 6: Deploy + End-to-End-Verifikation

**Files:** (keine — Deployment)

- [ ] **Step 6.1: Deploy auf den VPS**

```bash
cd /home/achim/Projects/vpn/nixos-hetzner-vps-config
nix run .#nrs
```

Expected: `activating the configuration...` laeuft durch, nginx wird reloaded, Exit-Code 0.

- [ ] **Step 6.2: Auf dem VPS — Dateien da und mit richtigen Permissions?**

```bash
ssh root@rusty-vault.de "ls -la /run/secrets/rmfakecloud-ca/"
```

Expected:

```
-r--------  1 nginx nginx  ca.crt
-r--------  1 nginx nginx  ca.key     (mode kann 0440 sein je nach umask)
-r--------  1 nginx nginx  server.crt
-r--r-----  1 nginx nginx  server.key
```

- [ ] **Step 6.3: nginx laeuft und serviert die reMarkable-Domains mit neuer CA**

```bash
ssh root@rusty-vault.de "systemctl is-active nginx.service"
curl -kI --resolve local.appspot.com:443:77.42.71.141 https://local.appspot.com/ | head -3
```

Expected:
- `active`
- HTTP/1.1 200 OK (oder was rmfakecloud in der Form liefert — wichtig ist: TLS-Handshake erfolgreich, kein `cannot load certificate key`)

- [ ] **Step 6.4: Alte Pfade sind weg**

```bash
ssh root@rusty-vault.de "test ! -e /etc/nixos/secrets/rmfakecloud-ca/server.key && echo 'OK: alte Plain-Files geloescht'"
```

Expected: `OK: ...`

Hinweis: Die Plain-Files liegen auf dem VPS in `/etc/nixos/secrets/rmfakecloud-ca/` noch vor dem ersten Deploy mit diesem Plan. Da sie durch Task 5 lokal entfernt wurden, wird `rsync --delete` (was `nrs` laut `DEPLOYMENT.md` macht) sie auch auf dem Server loeschen. **Falls das nicht klappt (rsync excludes?), manuell:**

```bash
ssh root@rusty-vault.de "shred -u /etc/nixos/secrets/rmfakecloud-ca/*.key; rm -rf /etc/nixos/secrets/rmfakecloud-ca"
```

- [ ] **Step 6.5: Regression-Check — alle anderen Vhosts gehen noch**

```bash
for host in auth vault stats seerr grafana jellyfin; do
  curl -sSI --resolve $host.rusty-vault.de:443:77.42.71.141 \
    --max-time 10 https://$host.rusty-vault.de/ 2>&1 | head -1
done
```

Expected: Jede Zeile ist ein `HTTP/2 2xx` oder `HTTP/2 3xx`, kein `HTTP/2 502` und kein Timeout.

---

## Task 7: Runbook fuer spaetere Rotation schreiben

**Files:**
- Create: `docs/runbooks/rmfakecloud-ca-rotation.md`

Reason: CA laeuft in 10 Jahren ab, Server-Cert in 825 Tagen (~2.25 Jahre). Vor Ablauf muss rotiert werden — damit das nicht jedes Mal durch Code-Archaeologie laeuft, schriftliche Prozedur.

- [ ] **Step 7.1: Datei anlegen mit Prozedur**

```markdown
# Runbook: rmfakecloud-CA rotieren

## Wann

- CA-Ablauf naehert sich (10 Jahre ab Erstellung, siehe `openssl x509 -in /run/secrets/rmfakecloud-ca/ca.crt -noout -enddate`).
- Server-Cert-Ablauf naehert sich (825 Tage).
- Kompromittierungsverdacht (Key-Leak).

## Prozedur

1. Neue Keys lokal generieren (ausserhalb des Repos, in `/tmp`):

   ```bash
   mkdir -p /tmp/rmfakecloud-ca-rotation
   cd /tmp/rmfakecloud-ca-rotation
   # openssl-san.cnf aus dem aktuellen sops-File extrahieren — oder aus
   # dem letzten Rotations-Backup. Die SAN-Liste MUSS identisch zu der
   # in rmfakecloud.nix:remarkableDomains bleiben.

   openssl ecparam -name secp384r1 -genkey -noout -out ca.key
   openssl req -new -x509 -key ca.key -days 3650 \
     -subj "/CN=rmfakecloud Self-Signed CA/O=rusty-vault.de" -out ca.crt
   openssl ecparam -name secp384r1 -genkey -noout -out server.key
   openssl req -new -key server.key -config openssl-san.cnf -out server.csr
   openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
     -days 825 -extensions v3_req -extfile openssl-san.cnf -out server.crt
   ```

2. Ins sops-YAML einpflegen:

   ```bash
   cd <vps-repo>
   sops secrets/rmfakecloud-ca.yaml
   # Werte ersetzen: ca_crt_b64, ca_key_b64, server_crt_b64, server_key_b64
   # Jeder ist `base64 -w0 <datei>`.
   ```

3. Deploy:

   ```bash
   nix run .#nrs
   ```

4. reMarkable-Tablet die neue CA vertrauen lassen:

   - Altes Tablet: `ssh root@remarkable` → neue `ca.crt` nach `/etc/ssl/certs/ca-certificates.crt` appendieren oder in den Trust-Store kopieren.
   - Details haengen von der rmfakecloud-/rM-Version ab — aktuellen Stand vor Rotation recherchieren.

5. Temp-Files schreddern:

   ```bash
   shred -u /tmp/rmfakecloud-ca-rotation/*.key
   rm -rf /tmp/rmfakecloud-ca-rotation
   ```

## Verifikation

```bash
openssl s_client -connect my.remarkable.com:443 -servername my.remarkable.com \
  --resolve my.remarkable.com:443:77.42.71.141 </dev/null 2>/dev/null | \
  openssl x509 -noout -subject -issuer -dates
```

Erwartet: `subject=CN=my.remarkable.com,...`, `issuer=CN=rmfakecloud Self-Signed CA,...`, `notAfter` liegt im gewuenschten Zeitraum.
```

- [ ] **Step 7.2: Commit**

```bash
git add docs/runbooks/rmfakecloud-ca-rotation.md
git commit -m "docs(rmfakecloud): Rotations-Runbook fuer CA und Server-Cert"
```

---

## Task 8: reMarkable-Tablet neu vertrauen lassen

**Files:** (keine — Geraete-Konfiguration)

Nach der CA-Rotation in Task 1 vertraut das reMarkable-Tablet der neuen CA nicht automatisch. Rmfakecloud-Sync wird fehlschlagen bis das Tablet die neue `ca.crt` importiert hat.

- [ ] **Step 8.1: Neue CA aus dem VPS holen**

```bash
ssh root@rusty-vault.de "cat /run/secrets/rmfakecloud-ca/ca.crt" > /tmp/new-ca.crt
cat /tmp/new-ca.crt | head -3   # Pruefen: -----BEGIN CERTIFICATE-----
```

- [ ] **Step 8.2: Auf dem Tablet installieren**

Prozedur haengt von rmfakecloud-Version auf dem Tablet ab. Referenz: `docs/plans/2026-03-01-rmfakecloud.md` (der Original-Plan fuer das Setup) beschreibt vermutlich, wo das Tablet die CA erwartet. Wenn unklar:

- rmfakecloud-Deployment-Doku lesen: https://github.com/ddvk/rmfakecloud
- Typisch: Tablet im root-Modus, neue CA nach `/usr/share/ca-certificates/` kopieren und in `/etc/ssl/certs/ca-certificates.crt` appendieren.

- [ ] **Step 8.3: Sync testen**

Auf dem Tablet: ein Dokument anlegen, sync triggern, pruefen ob es in rmfakecloud (`remarkable.rusty-vault.de`) erscheint.

- [ ] **Step 8.4: `/tmp/new-ca.crt` loeschen**

```bash
shred -u /tmp/new-ca.crt
```

---

## Rollback-Plan

**Wenn Task 6 den VPS in einen nicht-funktionierenden Zustand bringt:**

1. `ssh root@rusty-vault.de "nixos-rebuild switch --rollback"` — zurueck zur Generation vor dem Deploy.
2. Falls nginx dabei nicht mehr startet: vorher den alten Permission-Hack wiederherstellen:

   ```bash
   ssh root@rusty-vault.de "chgrp nginx /etc/nixos/secrets/rmfakecloud-ca/{server,ca}.key && chmod 640 /etc/nixos/secrets/rmfakecloud-ca/{server,ca}.key && systemctl reset-failed nginx && systemctl start nginx"
   ```

   (So wurde am 2026-04-24 der nginx-Service kurzzeitig wiederhergestellt.)

**Wenn das reMarkable-Tablet die neue CA nicht akzeptiert und sync-tot ist:**

- Die alte CA im sops-File wiederherstellen aus dem git-log eines frueheren Commits (sie liegt in `secrets/rmfakecloud-ca/ca.crt` vor dem rm-Commit). Erneut deployen.
- Dann in Ruhe einen zweiten Anlauf planen, in dem alte und neue CA parallel vom Tablet getrustet werden, bevor die alte entfernt wird.

---

## Risiken und Mitigation

| Risiko | Mitigation |
|--------|------------|
| base64-Decode-Hook im activationScript laeuft vor nginx-preStart → Race | `setupSecrets`-dep im activationScript stellt Reihenfolge sicher; nginx hat ohnehin `Requires=sops-install-secrets.service` via sops-nix-Default |
| sops-age-key auf dem Server fehlt/falsch | Bereits etabliert fuer andere Secrets (Vaultwarden, Ghostfolio); `modules/secrets.nix:age.keyFile` zeigt auf `/var/lib/sops-nix/key.txt` |
| reMarkable-Tablet vertraut der neuen CA nicht mehr, Sync bricht | Task 8 explizit; Rollback-Plan haelt alte CA verfuegbar |
| Keys in git-History bleiben lesbar | Task 1-Rotation macht die alten Keys **wertlos** (CA ist rotiert, Server-Cert ebenso); git-filter-repo als Nachfolge-Arbeit optional, aber nicht mehr sicherheitskritisch |
| `nrs`-rsync loescht `secrets/rmfakecloud-ca/` auf Server nicht automatisch | Task 6.4 prueft und raeumt ggf. manuell; `.gitignore`-Eintrag verhindert Re-Import |

---

## Nicht-Ziele

- **git-History-Rewrite** (`git filter-repo`/BFG): Da die alten Keys nach dieser Migration rotiert und wertlos sind, ist ein History-Rewrite nicht mehr sicherheitskritisch. Falls das Repo spaeter public wird, separaten Plan dafuer.
- **ACME fuer rmfakecloud-Domains**: Die `remarkableDomains` sind keine eigenen — es sind Domains der Firma reMarkable, die per lokalem CA-Trust MITMed werden. ACME geht dafuer nicht.
- **LLDAP/Authentik-Integration von rmfakecloud**: Separates Thema, kein Zusammenhang mit dem Cert-Permission-Bug.

---

## Referenzen

- Ursache des aktuellen Deploys am 2026-04-24: Commit `8387812 fix(nginx): stats.rusty-vault.de zur SNI-Preread-Map ergaenzen`
- nginx-Fehlermeldung (Log): `cannot load certificate key ... BIO_new_file() failed`
- sops-nix Doku: https://github.com/Mic92/sops-nix
- rmfakecloud: https://github.com/ddvk/rmfakecloud
