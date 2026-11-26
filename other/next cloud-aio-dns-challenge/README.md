# Nextcloud AIO mit DNS-Challenge

Dieses Projekt stellt eine Nextcloud-AIO-Installation so um, dass die Zertifikate per DNS-Challenge statt über Port 80 bezogen werden. Die Prüfung läuft über einen CNAME von Strato zu deSEC, und die Umstellung übersteht AIO-Updates. Für diese Aufgabe genügen `docker-compose.yml`, `nextcloud.yml` und die AIO-Anleitung.

> **Optional:** Die Anleitung zum DNS-Umzug zu Hetzner gehört zur allgemeinen Server-Migration und ist für die DNS-Challenge nicht nötig. Die Lösung funktioniert mit dem DNS bei Strato genauso wie nach einem Umzug.

## Dateien

| Datei | Inhalt |
|---|---|
| `docker-compose.yml` | Startet Traefik als Reverse Proxy vor Nextcloud. Traefik holt die Zertifikate bei Let's Encrypt per DNS-Challenge über deSEC. |
| `nextcloud.yml` | Leitet Anfragen an die Nextcloud-Adresse an AIO auf `127.0.0.1:11000` weiter. Hier wird der Hostname eingetragen. |
| `ANLEITUNG-AIO-DNS-Challenge.md` | Schritte zur Umstellung von AIO und zur Einrichtung von Traefik, mit Tests und Firewall-Einstellungen. Enthält eine Fehlertabelle und den Rückweg. |
| `ANLEITUNG-DNS-Umzug-Strato-Hetzner.md` | *Optional.* Umzug der DNS-Zone zu Hetzner, wobei die Domain zunächst bei Strato registriert bleibt. Enthält eine Checkliste, ein Vergleichsskript für beide Nameserver und den Rückweg. |
| `README.md` | Diese Übersicht. |

Vor dem Einsatz in `docker-compose.yml` und `nextcloud.yml` die Platzhalter ersetzen: `<deSEC-Token>`, `<admin-adresse>` und `cloud.example.de`.
