# Runbook: rmfakecloud-CA rotieren

## Wann

- CA-Ablauf naehert sich (10 Jahre ab Erstellung, siehe
  `openssl x509 -in /run/secrets/rmfakecloud-ca/ca.crt -noout -enddate`).
- Server-Cert-Ablauf naehert sich (825 Tage ab Erstellung).
- Kompromittierungsverdacht (Key-Leak, verlorenes Geraet mit Repo-Clone).

## Prozedur

### 1. Neue Keys lokal generieren (ausserhalb des Repos, in `/tmp`)

```bash
mkdir -p /tmp/rmfakecloud-ca-rotation
cd /tmp/rmfakecloud-ca-rotation
```

`openssl-san.cnf` rekonstruieren — die SAN-Liste muss zu den Domains in
`modules/services/containers/rmfakecloud.nix` (`remarkableDomains`) plus
`*.appspot.com`, `backtrace-proxy.cloud.remarkable.engineering` passen. Der
letzte bekannte Stand liegt in der git-History bei `secrets/rmfakecloud-ca/openssl-san.cnf`
vor Commit `02f7156` (2026-04-24):

```bash
git show 02f7156^:secrets/rmfakecloud-ca/openssl-san.cnf > openssl-san.cnf
```

Dann generieren:

```bash
nix-shell -p openssl --run '
  openssl ecparam -name secp384r1 -genkey -noout -out ca.key
  openssl req -new -x509 -key ca.key -days 3650 \
    -subj "/CN=rmfakecloud Self-Signed CA/O=rusty-vault.de" -out ca.crt

  openssl ecparam -name secp384r1 -genkey -noout -out server.key
  openssl req -new -key server.key -config openssl-san.cnf -out server.csr
  openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
    -days 825 -extensions v3_req -extfile openssl-san.cnf -out server.crt

  openssl verify -CAfile ca.crt server.crt
  openssl x509 -in server.crt -noout -ext subjectAltName
'
```

### 2. Ins sops-YAML einpflegen

```bash
cd <vps-repo>
sops secrets/rmfakecloud-ca.yaml
```

Im Editor die 4 Werte ersetzen:

- `ca_crt_b64` → `base64 -w0 /tmp/rmfakecloud-ca-rotation/ca.crt`
- `ca_key_b64` → `base64 -w0 /tmp/rmfakecloud-ca-rotation/ca.key`
- `server_crt_b64` → `base64 -w0 /tmp/rmfakecloud-ca-rotation/server.crt`
- `server_key_b64` → `base64 -w0 /tmp/rmfakecloud-ca-rotation/server.key`

### 3. Deploy

```bash
git add secrets/rmfakecloud-ca.yaml
git commit -m "rotate(rmfakecloud): CA + Server-Cert erneuert"
nix run .#nrs
```

sops-nix triggert `restartUnits = [ "nginx.service" ]`, nginx laedt die neuen
Zertifikate. Kein weiterer Handgriff noetig auf VPS-Seite.

### 4. reMarkable-Tablet die neue CA vertrauen lassen

- Neue CA vom VPS holen:

  ```bash
  ssh root@rusty-vault.de "cat /run/secrets/rmfakecloud-ca/ca.crt" > /tmp/new-ca.crt
  ```

- Auf dem Tablet installieren. Prozedur haengt von rM-OS-Version und
  rmfakecloud-Client-Variante ab — aktuellen Stand vor Rotation recherchieren
  (https://github.com/ddvk/rmfakecloud). Typisch:

  ```bash
  scp /tmp/new-ca.crt root@<tablet-ip>:/home/root/
  ssh root@<tablet-ip>
  # im Tablet: neue CA in den Trust-Store einhaengen (path abhaengig)
  ```

- Sync testen: ein Dokument erstellen, sync-Knopf druecken, in
  `remarkable.rusty-vault.de` pruefen ob es erscheint.

### 5. Temp-Files schreddern

```bash
shred -u /tmp/rmfakecloud-ca-rotation/*.key /tmp/new-ca.crt
rm -rf /tmp/rmfakecloud-ca-rotation
```

## Verifikation

```bash
openssl s_client -connect local.appspot.com:443 -servername local.appspot.com \
  --resolve local.appspot.com:443:77.42.71.141 </dev/null 2>/dev/null | \
  openssl x509 -noout -subject -issuer -dates
```

Erwartet:

- `subject=CN=remarkable-cloud, O=rusty-vault, C=DE`
- `issuer=CN=rmfakecloud Self-Signed CA, O=rusty-vault.de`
- `notAfter` liegt im gewuenschten Zeitraum (~825 Tage in der Zukunft).

## Notfall-Rollback

Falls das Tablet die neue CA nicht akzeptiert und Sync bricht:

```bash
cd <vps-repo>
git revert <rotation-commit-sha>
nix run .#nrs
```

Damit ist die alte CA wieder im sops-File und nginx benutzt sie. Tablet sollte
wieder syncen. Dann in Ruhe einen zweiten Anlauf planen — idealerweise mit
einer Phase, in der alte + neue CA parallel vom Tablet getrustet werden.
