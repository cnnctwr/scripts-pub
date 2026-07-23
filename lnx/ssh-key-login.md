# Ubuntu: SSH-Login auf SSH-Key umstellen und Root-Login deaktivieren

Diese Anleitung beschreibt die empfohlene Vorgehensweise für Ubuntu.

## Voraussetzungen

- SSH-Zugriff als `root`
- Ein vorhandenes SSH-Schlüsselpaar auf dem lokalen Rechner (z. B. `~/.ssh/id_ed25519` und `~/.ssh/id_ed25519.pub`)

---

## 1. Neuen Benutzer anlegen

Als `root` anmelden:

```bash
adduser <BENUTZERNAME>
```

Den Anweisungen folgen und ein Passwort vergeben.

---

## 2. Benutzer zur sudo-Gruppe hinzufügen

```bash
usermod -aG sudo <BENUTZERNAME>
```

---

## 3. SSH-Verzeichnis anlegen

```bash
mkdir -p /home/<BENUTZERNAME>/.ssh
chmod 700 /home/<BENUTZERNAME>/.ssh
```

---

## 4. Öffentlichen Schlüssel hinterlegen

Die komplette Zeile aus der lokalen Datei

```text
~/.ssh/id_ed25519.pub
```

in folgende Datei auf dem Server einfügen:

```text
/home/<BENUTZERNAME>/.ssh/authorized_keys
```

Beispiel:

```text
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... meinname@macbook
```

Anschließend die Berechtigungen setzen:

```bash
chown -R <BENUTZERNAME>:<BENUTZERNAME> /home/<BENUTZERNAME>/.ssh
chmod 600 /home/<BENUTZERNAME>/.ssh/authorized_keys
```

---

## 5. SSH-Key-Login testen

Vom lokalen Rechner:

```bash
ssh <BENUTZERNAME>@<SERVER>
```

Wenn der Login funktioniert, sudo testen:

```bash
sudo -i
```

---

## 6. Passwort für sudo deaktivieren (optional)

Falls für den Administrator kein sudo-Passwort erforderlich sein soll:

```bash
visudo
```

Am Ende der Datei ergänzen:

```text
<BENUTZERNAME> ALL=(ALL:ALL) NOPASSWD: ALL
```

Speichern und schließen.

---

## 7. Root-Login per SSH deaktivieren

Datei öffnen:

```bash
nano /etc/ssh/sshd_config
```

Folgende Zeile setzen bzw. anpassen:

```text
PermitRootLogin no
```

Optional zusätzlich den Passwort-Login für den neuen Admin-Benutzer deaktivieren:

```text
Match User <BENUTZERNAME>
    PasswordAuthentication no
```

Dadurch gilt:

- `root`: kein SSH-Login möglich
- `<BENUTZERNAME>`: Anmeldung ausschließlich per SSH-Key
- Andere Benutzer: unverändertes Verhalten

---

## 8. SSH-Konfiguration neu laden

```bash
systemctl reload ssh
```

---

## 9. Abschließender Test

In einem **neuen Terminal** prüfen:

```bash
ssh <BENUTZERNAME>@<SERVER>
```

Anschließend:

```bash
sudo -i
```

Wenn beides funktioniert, ist die Umstellung abgeschlossen.

---

# Ergebnis

- Root kann sich nicht mehr per SSH anmelden.
- Der Administrator meldet sich ausschließlich mit einem SSH-Key an.
- Administrative Aufgaben werden über `sudo` ausgeführt.
- Optional erfolgt `sudo` ohne Passwortabfrage.