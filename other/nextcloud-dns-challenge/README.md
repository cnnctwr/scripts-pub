# Nextcloud AIO mit DNS-Challenge

Dieses Projekt stellt eine Nextcloud-AIO-Installation so um, dass die Zertifikate per DNS-Challenge statt über Port 80 bezogen werden. Die Prüfung läuft über einen CNAME von Strato zu deSEC, und die Umstellung übersteht AIO-Updates.

## Dateien

| Datei | Inhalt |
|---|---|
| `docker-compose.yml` | Startet Traefik als Reverse Proxy vor Nextcloud. Traefik holt die Zertifikate bei Let's Encrypt per DNS-Challenge über deSEC. |
| `nextcloud.yml` | Leitet Anfragen an die Nextcloud-Adresse an AIO auf `127.0.0.1:11000` weiter. Hier wird der Hostname eingetragen. |
| `ANLEITUNG-AIO-DNS-Challenge.md` | Schritte zur Umstellung von AIO und zur Einrichtung von Traefik, mit Tests und Firewall-Einstellungen. Enthält eine Fehlertabelle und den Rückweg. |
| `README.md` | Diese Übersicht. |

Vor dem Einsatz in `docker-compose.yml` und `nextcloud.yml` die Platzhalter ersetzen: `<deSEC-Token>`, `<admin-adresse>` und `cloud.example.de`.
