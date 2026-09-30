# CARO-AD-Observer — Setup

Zwei PowerShell-Scripte zur Konfiguration der technischen Voraussetzungen für
den **CUSATUM CARO-AD-Observer** auf einem Windows-Domänencontroller, auf
Basis der offiziellen
[CARO-Observer-Voraussetzungen-de-DE.pdf](https://cusatum.de/downloads/docs/CARO-Observer-Voraussetzungen-de-DE.pdf).

> Ausführliche Erklärungen, Hintergründe und technische Details:
> siehe [readme-details.md](readme-details.md). Diese Datei hier ist bewusst
> kurz gehalten — nur der Weg, den du gehen musst.

## Voraussetzungen (kurz)

- Windows Server 2012 R2+ auf einem **Domänencontroller**, PowerShell **5.1**, Ausführung als **Administrator**
- `New-CAROObserverAuditGPO.ps1` zusätzlich: **GroupPolicy-PowerShell-Modul** (RSAT-GPMC)
- Details/Begründung: siehe [readme-details.md](readme-details.md#voraussetzungen)

## Entscheidungsbaum

### Schritt 1 — Umgebung prüfen

```powershell
.\Set-CAROObserverPrerequisites.ps1 -GPOCheck
```

Ergebnis bestimmt, welcher Pfad als Nächstes gilt:

### Pfad A — Keine GPO-Konflikte gefunden

```powershell
.\Set-CAROObserverPrerequisites.ps1 -ServiceAccount "CUSATUM\sa-caro"
```

Fertig — ein Script reicht, alle Einstellungen bleiben dauerhaft.

### Pfad B — Konflikt bei Audit-Richtlinien

Eine bestehende Gruppenrichtlinie verwaltet bereits Audit-Unterkategorien und
würde eine rein lokale Einstellung beim nächsten Refresh zurücksetzen.
Stattdessen eine eigene, dedizierte Gruppenrichtlinie anlegen — **plus** das
Hauptscript für die übrigen Bereiche:

```powershell
.\New-CAROObserverAuditGPO.ps1
.\Set-CAROObserverPrerequisites.ps1 -ServiceAccount "CUSATUM\sa-caro"
```

Beide Scripte nötig: Die GPO deckt ausschließlich die Audit-Richtlinien ab,
das Hauptscript die übrigen fünf Bereiche (Event Log Readers, Security-Eventlog,
SACL, Firewall).

### Pfad C — Konflikt bei Event Log Readers oder Firewall

Kein automatisierter Weg vorhanden — das Servicekonto bzw. die Firewall-Regeln
müssen manuell in der von `-GPOCheck` genannten Gruppenrichtlinie ergänzt
werden. Details: [readme-details.md](readme-details.md#-gpocheck--gpo-konflikte-erkennen).

---

> **Optional, vor Schritt 1 oder zwischendurch:** Ein reiner Lesepass ohne
> Änderung, um den Ist-Zustand zu dokumentieren:
> `.\Set-CAROObserverPrerequisites.ps1 -ReportOnly -ServiceAccount "CUSATUM\sa-caro"`
> — kein Pflichtschritt, aber empfehlenswert als Referenz vor dem ersten
> echten Lauf.

## Rollback

```powershell
# Hauptscript rückgängig machen
.\Set-CAROObserverPrerequisites.ps1 -RestoreFrom "<CARO-Observer-Backup-*.json>"

# Dedizierte Audit-GPO wieder entfernen (Verknüpfung lösen + GPO löschen)
.\New-CAROObserverAuditGPO.ps1 -RemoveGPO -BackupFile "<CARO-Observer-AuditGPO-Backup-*.json>"
```

Details: [readme-details.md](readme-details.md#rollback).

## Parameter — Set-CAROObserverPrerequisites.ps1

| Parameter               | Typ     | Default                  | Beschreibung                                                                                                   |
|--------------------------|---------|----------------------------|---------------------------------------------------------------------------------------------------------------|
| `-ServiceAccount`        | string  | *(interaktive Abfrage)*   | `Domain\Benutzername` des CARO-Servicekontos für die Gruppe `Event Log Readers`. Leere Eingabe überspringt den Schritt. |
| `-OutputPath`            | string  | `.\CARO-Observer-Setup-Logs`       | Verzeichnis für Log-, Backup- und Zieleinstellungsdateien.                                                     |
| `-RestoreFrom`           | string  | *(nicht gesetzt)*         | Pfad zu einer `CARO-Observer-Backup-*.json`. Aktiviert den Rollback-Modus. Nicht kombinierbar mit `-ReportOnly`/`-GPOCheck`. |
| `-MaxLogSizeKB`          | int     | `131072` (128 MB)         | Gewünschte Mindest-Maximalgröße des Security-Eventlogs in KB. |
| `-DesiredSettingsFile`   | string  | *(nicht gesetzt)*         | Pfad zu einer JSON-Eingabedatei mit `ServiceAccount`, `MaxLogSizeKB` und/oder `Scope`. Details: [readme-details.md](readme-details.md#-desiredsettingsfile--eingabe-json). |
| `-ReportOnly`            | switch  | `false`                    | Reiner Lesepass: ändert nichts, dokumentiert Ist-/Soll-Wert. Nicht kombinierbar mit `-RestoreFrom`/`-GPOCheck`. |
| `-GPOCheck`              | switch  | `false`                    | Diagnose-Modus, siehe Entscheidungsbaum oben. Nicht kombinierbar mit `-ReportOnly`/`-RestoreFrom`. |
| `-GPOCheckWaitMinutes`   | int     | `6`                         | Wartezeit für den aktiven Firewall-Persistenztest bei `-GPOCheck`. |
| `-AutoApprove`           | switch  | `false`                    | Überspringt die Einzelbestätigung (weiterhin vollständig protokolliert). Nicht für den ersten Lauf empfohlen. |

## Parameter — New-CAROObserverAuditGPO.ps1

| Parameter        | Typ    | Default                                  | Beschreibung                                                                                           |
|-------------------|--------|--------------------------------------------|-----------------------------------------------------------------------------------------------------------|
| `-GpoName`        | string | `CARO-AD-Observer-Audit`                   | Name der neu anzulegenden GPO. Muss noch nicht existieren.                                               |
| `-TargetOU`       | string | `OU=Domain Controllers,<Domain-DN>`        | DN der OU, mit der die GPO verknüpft wird.                                                                |
| `-GpoLinkOrder`   | int    | `1`                                         | Link-Priorität bei der Verknüpfung (1 = höchste). |
| `-OutputPath`     | string | `.\CARO-Observer-Setup-Logs`               | Verzeichnis für Log- und Backup-Datei — dasselbe wie beim Hauptscript.                                    |
| `-RemoveGPO`      | switch | `false`                                     | Rückbau-Modus: löst Verknüpfung und löscht die GPO aus `-BackupFile`. Erfordert `-BackupFile`.            |
| `-BackupFile`     | string | *(nicht gesetzt)*                          | Pfad zu einer `CARO-Observer-AuditGPO-Backup-*.json` eines früheren Erstellungslaufs. Nötig bei `-RemoveGPO`. |
| `-AutoApprove`    | switch | `false`                                     | Überspringt die Einzelbestätigung. Angesichts der Tragweite (geteilte AD-Infrastruktur) nicht empfohlen.  |

## Erzeugte Dateien — Set-CAROObserverPrerequisites.ps1

Alle Dateien landen in `-OutputPath` (Standard: `CARO-Observer-Setup-Logs`), benannt mit Servername und Zeitstempel:

| Datei                                         | Inhalt                                                                                          |
|------------------------------------------------|---------------------------------------------------------------------------------------------------|
| `CARO-Observer-Setup_<Server>_<Zeitstempel>.log`         | Vollständiges Textprotokoll: jeder Schritt, alle Fehler und Warnungen.           |
| `CARO-Observer-DesiredSettings_<Server>_<Zeitstempel>.json` | Strukturierte Liste aller **Ziel**-Einstellungen (Titel, Beschreibung, Befehl, Zielwert). |
| `CARO-Observer-Backup_<Server>_<Zeitstempel>.json`       | Je Einstellung: Original- und neuer Wert, Befehl, Zeitstempel, Status. Grundlage für `-RestoreFrom`. |
| `CARO-Observer-GPOCheck_<Server>_<Zeitstempel>.log`      | Nur bei `-GPOCheck`: menschenlesbarer Bericht mit Handlungsempfehlung. |

## Erzeugte Dateien — New-CAROObserverAuditGPO.ps1

Landen wie beim Hauptscript in `-OutputPath`:

| Datei                                                    | Inhalt                                                                                           |
|------------------------------------------------------------|-----------------------------------------------------------------------------------------------------|
| `CARO-Observer-AuditGPO_<Server>_<Zeitstempel>.log`         | Textprotokoll: jeder Schritt, alle Fehler und Warnungen. |
| `CARO-Observer-AuditGPO-Backup_<Server>_<Zeitstempel>.json` | GPO-GUID, Name, verknüpfte OU, Link-Priorität, Erstellungszeitpunkt — Grundlage für `-RemoveGPO`.  |

## Lizenz / Haftung

Internes Hilfsscript ohne Gewähr. Vor Einsatz auf produktiven
Domänencontrollern in einer Testumgebung verifizieren.
