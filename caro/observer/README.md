# Set-CAROObserverPrerequisites.ps1

PowerShell-Script zur Konfiguration der technischen Voraussetzungen für den
**CUSATUM CARO-AD-Observer** auf einem Windows-Domänencontroller (Audit-Richtlinien,
SACL, Firewall, Gruppe `Event Log Readers`) — auf Basis der offiziellen
Schritt-für-Schritt-Anleitung
[CARO-Observer-Voraussetzungen-de-DE.pdf](https://cusatum.de/downloads/docs/CARO-Observer-Voraussetzungen-de-DE.pdf)
(Version 2026.9). Bei Unklarheiten oder für die manuelle Durchführung einzelner
Schritte gilt immer die PDF als Referenz.

Das Script wirkt **ausschließlich auf den lokalen Server**, auf dem es ausgeführt
wird. Bei mehreren Domänencontrollern muss es auf jedem einzeln laufen — mit
Ausnahme der SACL-Einstellung, die nur auf **einem** DC gesetzt werden muss, da sie
per AD-Replikation automatisch verteilt wird.

## Warum dieses Script

Jede einzelne Änderung wird vor der Ausführung im Klartext angezeigt:

- **was** gemacht wird
- der **exakte Befehl / Mechanismus**
- der **aktuelle Wert**
- der **Zielwert**

und muss einzeln bestätigt werden (`[J]a` / `[N]ein` / `[A]lle weiteren automatisch`
/ `[Q]uit`). Nichts geschieht unbeaufsichtigt, außer mit `-AutoApprove`.

## Was konfiguriert wird

1. **Event Log Readers** — Servicekonto zur lokalen Gruppe hinzufügen
2. **Unterkategorien erzwingen** — Sicherheitsoption
   `SCENoApplyLegacyAuditPolicy` (muss laut PDF zuerst gesetzt werden)
3. **9 Audit-Unterkategorien** via `auditpol` (sprachunabhängig per GUID
   angesteuert, GUID wird beim Start gegen den real aufgelösten Namen validiert):
   - Kontoverwaltung: Benutzer-, Computer-, Sicherheitsgruppen-,
     Verteilergruppen-, Anwendungsgruppen-, Andere Kontoverwaltungsereignisse
   - DS-Zugriff: Verzeichnisdienstzugriff, Verzeichnisdienständerungen
   - Richtlinienänderung: Überwachungsrichtlinienänderung
4. **Security-Eventlog** — Maximalgröße (Standard ≥ 128 MB) und
   Überschreibmodus "Ereignisse bei Bedarf überschreiben"
5. **SACL auf dem Domain-Objekt** — Audit-Eintrag für „Jeder“ (Zulassen /
   Erfolg / Dieses und alle untergeordneten Objekte / die 6 in der PDF
   genannten Rechte)
6. **Windows-Firewall** — die drei eingehenden Regeln
   „Remote-Ereignisprotokollverwaltung“ (NP, RPC, RPC-EPMAP)

## Voraussetzungen

- Windows Server 2012 R2 oder neuer (2019/2022 empfohlen, siehe
  [PDF](https://cusatum.de/downloads/docs/CARO-Observer-Voraussetzungen-de-DE.pdf) S.3),
  ausgeführt **auf einem Domänencontroller**
- PowerShell **5.1** (kein `pwsh`/PS7 nötig)
- Ausführung als **Administrator** (Domänen-Admin empfohlen, wegen
  `SeSecurityPrivilege` für die SACL-Änderung)
- Kein GroupPolicy-/RSAT-Modul erforderlich

## Verwendung

```powershell
# Interaktiv, fragt bei Bedarf nach dem Servicekonto
.\Set-CAROObserverPrerequisites.ps1

# Servicekonto direkt angeben
.\Set-CAROObserverPrerequisites.ps1 -ServiceAccount "CUSATUM\sa-caro"

# Alle Änderungen rückgängig machen (mit erneuter Einzelbestätigung)
.\Set-CAROObserverPrerequisites.ps1 -RestoreFrom ".\CARO-Setup-Logs\CARO-Backup_DC01_20260922-101500.json"

# Nur lesen, nichts ändern (Bestandsaufnahme)
.\Set-CAROObserverPrerequisites.ps1 -ReportOnly

# Konto/Größe/Scope aus einer Eingabedatei übernehmen
.\Set-CAROObserverPrerequisites.ps1 -DesiredSettingsFile ".\caro-example-config.json"
```

## Best Practice: Empfohlener Ablauf beim ersten Einsatz auf einem Server

1. **Bestandsaufnahme, bevor irgendetwas angefasst wird:**
   ```powershell
   .\Set-CAROObserverPrerequisites.ps1 -ReportOnly -ServiceAccount "CUSATUM\sa-caro"
   ```
   Das Servicekonto hier mit angeben — ohne `-ServiceAccount` fehlt der Schritt
   `EventLogReaders` komplett im Report, da er ohne bekanntes Konto gar nicht
   erst geprüft werden kann; alle anderen Einstellungen sind davon unabhängig.
   Die dabei erzeugte `CARO-Backup_*.json` dokumentiert den **Ist-Zustand vor
   jeder Änderung** - rein informativ. **Wichtig:** Diese Report-Only-Datei
   eignet sich NICHT für `-RestoreFrom` - im Report-Modus wird nichts als
   `Geändert` markiert (nur `Nur gelesen (Report) - ...`), und `-RestoreFrom`
   wirkt ausschließlich auf `Geändert`-Einträge. Sie dient ausschließlich der
   Dokumentation/Verifikation, nicht dem Rollback.

2. **Erster echter Lauf, mit demselben Servicekonto:**
   ```powershell
   .\Set-CAROObserverPrerequisites.ps1 -ServiceAccount "CUSATUM\sa-caro"
   ```
   Jede Einstellung einzeln bestätigen wie gewohnt. Die dabei entstehende
   `CARO-Backup_*.json` ist die für ein **echtes Rollback nutzbare** Datei -
   sie enthält für jede tatsächlich geänderte Einstellung sowohl den
   ursprünglichen als auch den neuen Wert.

3. **Diese Backup-Datei sichern**, sofort nach dem ersten Lauf: an einen
   sicheren, klar benannten Ort kopieren (z. B. außerhalb des
   `CARO-Setup-Logs`-Ordners), bevor weitere Läufe stattfinden. Es ist die
   einzige Quelle für den echten Urzustand des Servers - jeder spätere Lauf
   sieht als „aktuell" bereits das Ergebnis dieses ersten Laufs, nicht mehr
   den ursprünglichen Zustand. Geht diese eine Datei verloren, lässt sich der
   Urzustand nicht mehr automatisiert wiederherstellen.

4. **Rollback bei Bedarf:**
   ```powershell
   .\Set-CAROObserverPrerequisites.ps1 -RestoreFrom "<gesicherte Backup-Datei aus Schritt 2>"
   ```
   Empfehlenswert: danach einmal mit `-ReportOnly` gegenprüfen, dass wieder
   alles dem Urzustand entspricht, bevor erneut angewendet wird.

## Parameter

| Parameter               | Typ     | Default                  | Beschreibung                                                                                                   |
|--------------------------|---------|----------------------------|---------------------------------------------------------------------------------------------------------------|
| `-ServiceAccount`        | string  | *(interaktive Abfrage)*   | `Domain\Benutzername` des CARO-Servicekontos für die Gruppe `Event Log Readers`. Leere Eingabe überspringt den Schritt. Überschreibt einen Wert aus `-DesiredSettingsFile`. |
| `-OutputPath`            | string  | `.\CARO-Setup-Logs`       | Verzeichnis für Log-, Backup- und Zieleinstellungsdateien.                                                     |
| `-RestoreFrom`           | string  | *(nicht gesetzt)*         | Pfad zu einer zuvor erzeugten `CARO-Backup-*.json`. Aktiviert den Rollback-Modus. Nicht kombinierbar mit `-ReportOnly`. |
| `-MaxLogSizeKB`          | int     | `131072` (128 MB)         | Gewünschte Mindest-Maximalgröße des Security-Eventlogs in KB. Überschreibt einen Wert aus `-DesiredSettingsFile`. |
| `-DesiredSettingsFile`   | string  | *(nicht gesetzt)*         | Pfad zu einer JSON-Eingabedatei mit `ServiceAccount`, `MaxLogSizeKB` und/oder `Scope` (siehe unten). Ein explizit auf der Kommandozeile gesetzter Parameter hat immer Vorrang vor dem Wert aus der Datei. |
| `-ReportOnly`            | switch  | `false`                    | Reiner Lesepass: fragt nichts ab, ändert nichts, schreibt Ist-Wert + Soll-Wert + Übereinstimmung jeder Einstellung in die Backup-Datei (Status `Nur gelesen (Report)`). Nicht kombinierbar mit `-RestoreFrom`. |
| `-AutoApprove`           | switch  | `false`                    | Überspringt die Einzelbestätigung (weiterhin vollständig protokolliert). Nicht für den ersten Lauf empfohlen. |

### `-DesiredSettingsFile` — Eingabe-JSON

Damit lassen sich die Dinge vorgeben, die tatsächlich pro Umgebung variieren:
Servicekonto, Mindest-Log-Größe und welche der sechs Konfigurationsblöcke
überhaupt angeboten werden sollen (`Scope`). **Nicht** überschreibbar sind die
fachlich vorgegebenen Zielwerte selbst (z. B. `Erfolg` bei den
Audit-Unterkategorien oder die sechs SACL-Rechte) — das sind feste Vorgaben
aus der PDF, keine Umgebungsentscheidung, und bleiben im Script hinterlegt.

`MaxLogSizeKB` ist ein **Mindestwert** (das Script prüft mit `>=`, siehe PDF:
„mindestens 131.072 KB"): ein größerer vorhandener Wert gilt bereits als
konform und wird nicht verkleinert; ein kleinerer wird auf den angegebenen
Wert angehoben.

Beispiel (liegt als [`caro-example-config.json`](caro-example-config.json) bei
— hier für eine Testumgebung, in der CARO-Server und Domänencontroller derselbe
Host sind und die Firewall-Schritte deshalb übersprungen werden):

```json
{
  "ServiceAccount": "CUSATUM\\sa-caro",
  "MaxLogSizeKB": 131072,
  "Scope": {
    "EventLogReaders": true,
    "ForceSubcategoryPolicy": true,
    "AuditPolicies": true,
    "SecurityLogConfig": true,
    "Sacl": true,
    "Firewall": false
  }
}
```

```powershell
.\Set-CAROObserverPrerequisites.ps1 -DesiredSettingsFile ".\caro-example-config.json"
```

### `-ReportOnly` — Bestandsaufnahme ohne Änderung

```powershell
.\Set-CAROObserverPrerequisites.ps1 -ReportOnly
```

Praktisch als Ausgangspunkt: einmal `-ReportOnly` laufen lassen, um den
Ist-Zustand zu dokumentieren, bevor irgendetwas angefasst wird — die dabei
erzeugte `CARO-Backup-*.json` enthält für jede Einstellung Ist- und (unveränderten)
Neu-Wert sowie den Status `Nur gelesen (Report) - entspricht Ziel` bzw.
`- weicht vom Ziel ab`. Ein späterer `-RestoreFrom` auf diese Datei macht
nichts (es gibt nichts zurückzusetzen), da nur Einträge mit Status `Geändert`
für den Rollback berücksichtigt werden.

## Erzeugte Dateien

Alle Dateien landen in `-OutputPath` (Standard: `CARO-Setup-Logs` neben dem
Script), benannt mit Servername und Zeitstempel:

| Datei                                         | Inhalt                                                                                          |
|------------------------------------------------|---------------------------------------------------------------------------------------------------|
| `CARO-Setup_<Server>_<Zeitstempel>.log`         | Vollständiges Textprotokoll: jeder Schritt, alle Fehler und Warnungen, mit Zeitstempel.           |
| `CARO-DesiredSettings_<Server>_<Zeitstempel>.json` | Strukturierte Liste aller **Ziel**-Einstellungen (Titel, Beschreibung, Befehl, Zielwert) — unabhängig davon, ob sie angewendet wurden. |
| `CARO-Backup_<Server>_<Zeitstempel>.json`       | Je Einstellung: Original- und neuer Wert, Befehl, Zeitstempel, Status (`Geändert`, `Bereits korrekt`, `Übersprungen`, `Nur gelesen (Report) …`, `Fehler …`). Grundlage für `-RestoreFrom`. |

Bei `-ReportOnly` werden dieselben zwei Dateien geschrieben (kein Log-Eintrag
mit Status `Geändert`, da nichts angewendet wird) — die Backup-Datei dient
hier als reine Ist-Zustands-Momentaufnahme.

## Rollback

Ein Rollback-Lauf mit `-RestoreFrom <Backup-Datei>` liest die Backup-JSON,
geht jeden als `Geändert` protokollierten Eintrag einzeln durch und bietet an,
ihn — wieder mit derselben Klartext-Bestätigung — auf den ursprünglich
protokollierten Wert zurückzusetzen. Einträge mit anderem Status
(`Bereits korrekt`, `Übersprungen`) werden übersprungen, da dort nichts
geändert wurde. Der Rollback-Lauf erzeugt selbst wieder ein eigenes Log und
eine eigene Backup-Datei.

## Bekannte Einschränkungen

- Es wird ausschließlich der **lokale Server** konfiguriert; bei mehreren DCs
  muss das Script mehrfach ausgeführt werden (SACL-Schritt ausgenommen).
- Die Audit-Unterkategorien werden über fest hinterlegte, von Microsoft
  dokumentierte GUIDs angesteuert. Vor jeder Anwendung wird der tatsächlich
  aufgelöste Name geprüft; bei Abweichung wird der betroffene Schritt
  sicherheitshalber **nicht** angeboten, statt eine möglicherweise falsche
  Unterkategorie zu setzen.
- Vor dem produktiven Einsatz sollte das Script in einer Test-/Lab-Umgebung
  gegengeprüft werden.

## Lizenz / Haftung

Internes Hilfsscript ohne Gewähr. Vor Einsatz auf produktiven
Domänencontrollern in einer Testumgebung verifizieren.
