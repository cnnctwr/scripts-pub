# Nextcloud AIO: Zertifikat per DNS-Challenge statt Port 80

**Ziel:** Nicht mehr AIO holt die Zertifikate, sondern ein vorgeschalteter Traefik. Der prüft per DNS-Challenge über deSEC (CNAME von Strato), dadurch kann Port 80 zu.
Die Einstellung liegt am Mastercontainer und in Traefik. AIO-Updates überschreiben sie nicht.

> Ungetestet auf eurem System. Vorher einen Snapshot des Servers bzw. ein AIO-Backup machen.

Platzhalter in dieser Anleitung: `cloud.example.de` = Nextcloud-Adresse, `<deSEC-Ziel>` = Name, auf den der CNAME zeigt.

---

## 1. Vorbereitung

1. **CNAME prüfen**, er muss für genau diesen Hostnamen existieren:
   ```
   dig +short _acme-challenge.cloud.example.de CNAME
   ```
   Erwartet wird `<deSEC-Ziel>`. Fehlt er, bei Strato (oder später Hetzner) anlegen:
   `_acme-challenge.cloud` → CNAME → `<deSEC-Ziel>.`
2. **deSEC-Token** besorgen. Er braucht Schreibrechte auf die deSEC-Zone, in der `<deSEC-Ziel>` liegt.
3. **Aktuellen Startbefehl des Mastercontainers sichern.** Eigene Optionen wie `NEXTCLOUD_DATADIR` oder `NEXTCLOUD_MOUNT` müssen später wieder rein.
   ```
   docker inspect nextcloud-aio-mastercontainer --format '{{range .Config.Env}}{{println .}}{{end}}'
   ```
   Wurde AIO per `compose.yaml` gestartet, einfach diese Datei sichern.

## 2. AIO auf „Betrieb hinter Reverse Proxy" umstellen

1. Im AIO-Webinterface (`https://<server>:8080`) **alle Container stoppen**.
2. Den Mastercontainer entfernen. Daten und Einstellungen liegen in Volumes und bleiben erhalten.
   ```
   docker stop nextcloud-aio-mastercontainer
   docker rm nextcloud-aio-mastercontainer
   ```
3. Neu starten, **ohne** Port 80 und 8443, mit den drei neuen Variablen. Der Volume-Name muss genau so bleiben.
   ```
   docker run -d \
     --init \
     --sig-proxy=false \
     --name nextcloud-aio-mastercontainer \
     --restart always \
     --publish 8080:8080 \
     -e APACHE_PORT=11000 \
     -e APACHE_IP_BINDING=127.0.0.1 \
     -e SKIP_DOMAIN_VALIDATION=true \
     --volume nextcloud_aio_mastercontainer:/mnt/docker-aio-config \
     --volume /var/run/docker.sock:/var/run/docker.sock:ro \
     ghcr.io/nextcloud-releases/all-in-one:latest
   ```
   Eigene Optionen aus Schritt 1.3 ergänzen. Bei `compose.yaml` die drei `environment`-Einträge dort eintragen, `80:80` und `8443:8443` entfernen und `docker compose up -d` ausführen.
4. Im AIO-Webinterface **Container starten**. Nextcloud lauscht jetzt nur noch auf `127.0.0.1:11000`, ohne eigenes Zertifikat.

## 3. Traefik einrichten

1. Diesen Ordner auf den Server kopieren, z. B. nach `/opt/traefik`.
2. Platzhalter ersetzen:
   - `docker-compose.yml`: `<deSEC-Token>`, `<admin-adresse>`
   - `nextcloud.yml`: `cloud.example.de`
3. **Erst gegen die Test-CA von Let's Encrypt** probieren, damit Fehlversuche nicht ins Limit laufen. In `docker-compose.yml` unter `command` vorübergehend ergänzen:
   ```
   - --certificatesresolvers.desec.acme.caserver=https://acme-staging-v02.api.letsencrypt.org/directory
   ```
4. Starten und Log beobachten:
   ```
   mkdir -p letsencrypt
   docker compose up -d
   docker compose logs -f traefik
   ```
   Erfolg: keine `error`-Zeilen zu `acme`, und `letsencrypt/acme.json` enthält ein Zertifikat.
5. **Auf echte Zertifikate umstellen:** die Zeile `caserver` wieder entfernen, `letsencrypt/acme.json` löschen, dann `docker compose up -d`.

## 4. Prüfen

```
echo | openssl s_client -connect cloud.example.de:443 -servername cloud.example.de 2>/dev/null \
  | openssl x509 -noout -issuer -dates
```
Erwartet: Aussteller Let's Encrypt (nicht „STAGING"), gültiges Datum.
Danach im Browser anmelden, Datei hochladen und den Client-Sync testen.

## 5. Firewall

- **Schließen:** 80/tcp, 8443/tcp
- **Offen lassen:** 443/tcp (Traefik), 3478/tcp+udp (nur bei Nextcloud Talk)
- **8080/tcp** (AIO-Verwaltung) nur aus dem Firmennetz oder per VPN erreichbar machen.

## Fehler und Rückweg

| Problem | Ursache / Lösung |
|---|---|
| Log: `NXDOMAIN` oder Zeitüberschreitung bei `_acme-challenge` | CNAME fehlt oder ist falsch geschrieben (Punkt am Ende bei Strato?). |
| Log: `403` / `unauthorized` von deSEC | Token falsch oder ohne Rechte auf die Zielzone. |
| Traefik startet nicht, Port 443 belegt | Der Apache-Container von AIO läuft noch auf 443, Schritt 2 prüfen. |
| `502 Bad Gateway` | Die AIO-Container laufen nicht, oder `APACHE_PORT` passt nicht zu `nextcloud.yml`. |

**Rückweg:** Traefik stoppen (`docker compose down`), den Mastercontainer wie in Schritt 2 entfernen und mit dem gesicherten alten Befehl neu starten, dann Port 80 wieder öffnen.
