# Set-CAROObserverPrerequisites.ps1 — Details & Hintergrund

> **Kurzanleitung mit Entscheidungsbaum:** siehe [README.md](README.md).
> Diese Datei enthält die ausführlichen Erklärungen, technischen Details und
> Hintergründe für alle, die es genauer wissen wollen.

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

## Wie das Script arbeitet

Jede einzelne Änderung wird vor der Ausführung im Klartext angezeigt:

- **was** gemacht wird
- der **exakte Befehl / Mechanismus**
- der **aktuelle Wert**
- der **Zielwert**

und muss einzeln bestätigt werden (`[J]a` / `[N]ein` / `[A]lle weiteren automatisch`
/ `[Q]uit`). Nichts geschieht unbeaufsichtigt, außer mit `-AutoApprove`.

## Was konfiguriert wird

1. **Event Log Readers** — Servicekonto zur Gruppe hinzufügen. Die Gruppe
   wird über ihre weltweit gleiche Well-Known-SID `S-1-5-32-573` identifiziert,
   nie über einen angenommenen Namen — auf lokalisierten Windows-Versionen
   können sowohl CN als auch SamAccountName dieser Builtin-Gruppe übersetzt
   sein (bestätigt z. B. deutsch: „Ereignisprotokollleser“ statt
   „Event Log Readers“). Auf einem Domänencontroller wird bevorzugt das
   ActiveDirectory-PowerShell-Modul verwendet, falls vorhanden (siehe
   Voraussetzungen), sonst ein LDAP/ADSI-Fallback.
2. **Unterkategorien erzwingen** — Sicherheitsoption
   `SCENoApplyLegacyAuditPolicy` (muss laut PDF zuerst gesetzt werden)
3. **9 Audit-Unterkategorien** — auf zwei möglichen Wegen, je nachdem, ob
   dieselben Unterkategorien bereits von einer bestehenden Gruppenrichtlinie
   verwaltet werden (siehe `-GPOCheck` unten und der Entscheidungsbaum in der
   [README.md](README.md)):
   - **Kein GPO-Konflikt:** lokal via `auditpol` (sprachunabhängig per GUID
     angesteuert, GUID wird beim Start gegen den real aufgelösten Namen
     validiert)
   - **GPO-Konflikt:** stattdessen über eine eigene, dedizierte
     Gruppenrichtlinie — siehe
     [New-CAROObserverAuditGPO.ps1](#new-carobserverauditgpops1--dedizierte-gpo-statt-lokaler-audit-einstellung)
     weiter unten
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
- Kein GroupPolicy-Modul erforderlich. Das **ActiveDirectory-PowerShell-Modul**
  (RSAT-AD-PowerShell) ist **optional, aber empfohlen** auf einem DC: Ist es
  vorhanden, wird `Event Log Readers` darüber verwaltet (`Get-/Add-/Remove-ADGroupMember`,
  robust, offiziell unterstützt). Ohne das Modul greift ein LDAP/ADSI-Eigenbau,
  der in der Praxis fragiler war (siehe „Bekannte Einschränkungen“) — auf
  einem DC ohne das Modul lohnt sich `Install-WindowsFeature RSAT-AD-PowerShell`.

## Verwendung

```powershell
# Interaktiv, fragt bei Bedarf nach dem Servicekonto
.\Set-CAROObserverPrerequisites.ps1

# Servicekonto direkt angeben
.\Set-CAROObserverPrerequisites.ps1 -ServiceAccount "CUSATUM\sa-caro"

# Alle Änderungen rückgängig machen (mit erneuter Einzelbestätigung)
.\Set-CAROObserverPrerequisites.ps1 -RestoreFrom ".\CARO-Observer-Setup-Logs\CARO-Observer-Backup_DC01_20260922-101500.json"

# Nur lesen, nichts ändern (Bestandsaufnahme)
.\Set-CAROObserverPrerequisites.ps1 -ReportOnly

# Konto/Größe/Scope aus einer Eingabedatei übernehmen
.\Set-CAROObserverPrerequisites.ps1 -DesiredSettingsFile ".\caro-example-config.json"

# Pruefen, ob eine bestehende Gruppenrichtlinie mit dem Script kollidiert
.\Set-CAROObserverPrerequisites.ps1 -GPOCheck
```

## Best Practice: Empfohlener Ablauf beim ersten Einsatz auf einem Server

### 1. GPO-Konflikte ausschließen

```powershell
.\Set-CAROObserverPrerequisites.ps1 -GPOCheck
```

Prüft, ob eine bestehende Gruppenrichtlinie bereits Audit-Richtlinien, die
Registry-Option „Unterkategorien erzwingen" oder die
Event-Log-Readers-Gruppenmitgliedschaft verwaltet — in dem Fall würde eine
rein lokale Änderung durch dieses Script beim nächsten
Sicherheitsrichtlinien-Refresh wieder zurückgesetzt. Details siehe Abschnitt
„`-GPOCheck` — GPO-Konflikte erkennen" weiter unten. Ändert nichts dauerhaft
(der Firewall-Teil setzt testweise, wartet, und stellt danach immer den
Ausgangswert wieder her).

### 2. Bestandsaufnahme, bevor irgendetwas angefasst wird

```powershell
.\Set-CAROObserverPrerequisites.ps1 -ReportOnly -ServiceAccount "CUSATUM\sa-caro"
```

Das Servicekonto hier mit angeben — ohne `-ServiceAccount` fehlt der Schritt
`EventLogReaders` komplett im Report (wird sonst interaktiv nachgefragt);
alle anderen Einstellungen sind davon unabhängig.

Erzeugt werden drei Dateien, benannt nach Server und Zeitstempel, z. B.:

- `CARO-Observer-Setup_SRV-CARO_20260925-101500.log` — Textprotokoll: jeder geprüfte
  Schritt, alle Fehler und Warnungen.
- `CARO-Observer-DesiredSettings_SRV-CARO_20260925-101500.json` — Vorschau aller
  Einstellungen, die ein echter Lauf anfassen würde, mit Sollwert und Befehl —
  geschrieben, *bevor* überhaupt etwas passiert (siehe Hinweis unten).
- `CARO-Observer-Backup_SRV-CARO_20260925-101500.json` — der **Ist-Zustand** jeder
  Einstellung zu diesem Zeitpunkt. Da `-ReportOnly` nichts verändert, sind
  Original- und Neu-Wert hier identisch — trotzdem ist diese Datei bereits
  **vollwertig für `-RestoreFrom` nutzbar** (siehe Abschnitt „Rollback").

**Diese Backup-Datei sofort sichern**: an einen sicheren, klar benannten Ort
kopieren (z. B. außerhalb des `CARO-Observer-Setup-Logs`-Ordners), bevor weitere Läufe
stattfinden. Es ist die einzige Quelle für den echten Urzustand des Servers —
jeder spätere Lauf sieht als „aktuell" bereits das Ergebnis vorheriger Läufe,
nicht mehr den ursprünglichen Zustand. Geht diese eine Datei verloren, lässt
sich der Urzustand nicht mehr automatisiert wiederherstellen.

> **Zum Namen „DesiredSettings“:** Der Name klingt nach einer vom Anwender
> vorab festgelegten Spezifikation, ist aber eine vom Script berechnete
> Vorschau — kein Eingabeformat. Es gibt bewusst **keine** vollständige,
> vorab von Hand editierbare „alle 16 Einstellungen“-Datei: Einige Angaben
> (z. B. der tatsächliche, ggf. lokalisierte Name der `Event Log
> Readers`-Gruppe, der Domain-DN, ob die Audit-Unterkategorien auf diesem
> System valide Namen ergeben) lassen sich nicht ohne Kontakt zum Zielsystem
> zuverlässig vorwegnehmen. Zusätzlich sind die eigentlichen Sollwerte
> (`Erfolg`, SACL-Rechte usw.) PDF-fest vorgegeben und bewusst nicht
> überschreibbar, um versehentliche Fehlkonfiguration zu verhindern — ein
> volles Eingabeformat würde sie fälschlich als frei änderbar erscheinen
> lassen. `-ReportOnly` deckt den Vorab-Einblick trotzdem vollständig ab.

### 3. Erster echter Lauf, mit demselben Servicekonto

```powershell
.\Set-CAROObserverPrerequisites.ps1 -ServiceAccount "CUSATUM\sa-caro"
```

Jede Einstellung einzeln bestätigen wie gewohnt. Erzeugt dieselben drei
Dateitypen wie in Schritt 2 — diesmal mit echten Änderungen: Die
`CARO-Observer-Backup_*.json` enthält für jede tatsächlich geänderte Einstellung
Original- **und** neuen Wert (Status `Geändert`).

### 4. Rollback bei Bedarf

```powershell
.\Set-CAROObserverPrerequisites.ps1 -RestoreFrom "<gesicherte Backup-Datei aus Schritt 2 oder 3>"
```

Erzeugt wieder ein Log und eine eigene, neue Backup-Datei — **keine**
`DesiredSettings`-Datei, da hier nichts „angestrebt", sondern etwas
zurückgesetzt wird. Empfehlenswert: danach einmal mit `-ReportOnly`
gegenprüfen, dass wieder alles dem gewünschten Zustand entspricht, bevor
erneut angewendet wird.

## Parameter

| Parameter               | Typ     | Default                  | Beschreibung                                                                                                   |
|--------------------------|---------|----------------------------|---------------------------------------------------------------------------------------------------------------|
| `-ServiceAccount`        | string  | *(interaktive Abfrage)*   | `Domain\Benutzername` des CARO-Servicekontos für die Gruppe `Event Log Readers`. Leere Eingabe überspringt den Schritt. Überschreibt einen Wert aus `-DesiredSettingsFile`. |
| `-OutputPath`            | string  | `.\CARO-Observer-Setup-Logs`       | Verzeichnis für Log-, Backup- und Zieleinstellungsdateien.                                                     |
| `-RestoreFrom`           | string  | *(nicht gesetzt)*         | Pfad zu einer zuvor erzeugten `CARO-Observer-Backup-*.json`. Aktiviert den Rollback-Modus. Nicht kombinierbar mit `-ReportOnly`. |
| `-MaxLogSizeKB`          | int     | `131072` (128 MB)         | Gewünschte Mindest-Maximalgröße des Security-Eventlogs in KB. Überschreibt einen Wert aus `-DesiredSettingsFile`. |
| `-DesiredSettingsFile`   | string  | *(nicht gesetzt)*         | Pfad zu einer JSON-Eingabedatei mit `ServiceAccount`, `MaxLogSizeKB` und/oder `Scope` (siehe unten). Ein explizit auf der Kommandozeile gesetzter Parameter hat immer Vorrang vor dem Wert aus der Datei. |
| `-ReportOnly`            | switch  | `false`                    | Reiner Lesepass: ändert nichts, schreibt Ist-Wert + Soll-Wert + Übereinstimmung jeder Einstellung in die Backup-Datei (Status `Nur gelesen (Report)`). Fragt wie der Apply-Modus bei fehlendem `-ServiceAccount` interaktiv danach (Enter = Schritt auslassen). Nicht kombinierbar mit `-RestoreFrom`/`-GPOCheck`. |
| `-GPOCheck`              | switch  | `false`                    | Reiner Diagnose-Modus: prüft, ob eine bestehende Gruppenrichtlinie Audit-Richtlinien, „Unterkategorien erzwingen" oder die Event-Log-Readers-Gruppenmitgliedschaft verwaltet. Braucht kein `-ServiceAccount`. Nicht kombinierbar mit `-ReportOnly`/`-RestoreFrom`. Details siehe eigener Abschnitt unten. |
| `-GPOCheckWaitMinutes`   | int     | `6`                         | Wartezeit für den aktiven Firewall-Persistenztest bei `-GPOCheck`. |
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
erzeugte `CARO-Observer-Backup-*.json` enthält für jede Einstellung Ist- und (unveränderten)
Neu-Wert sowie den Status `Nur gelesen (Report) - entspricht Ziel` bzw.
`- weicht vom Ziel ab`. Ein späterer `-RestoreFrom` auf diese Datei setzt jede
Einstellung auf genau diesen dokumentierten Ist-Zustand zurück — eine
Report-Only-Datei ist also, unabhängig davon, ob das Script vorher schon
einmal gelaufen ist, sofort als vollständige Rollback-Referenz nutzbar
(siehe Abschnitt „Rollback").

### `-GPOCheck` — GPO-Konflikte erkennen

```powershell
.\Set-CAROObserverPrerequisites.ps1 -GPOCheck
```

**Hintergrund:** Dieses Script setzt Audit-Richtlinien, die Registry-Option
„Unterkategorien erzwingen" und die Event-Log-Readers-Gruppenmitgliedschaft
lokal auf dem Server. Verwaltet in der Domäne bereits eine Gruppenrichtlinie
(GPO) denselben Bereich, wird die lokale Änderung beim nächsten
Sicherheitsrichtlinien-Refresh (auf einem DC alle paar Minuten) wieder
zurückgesetzt — das Script selbst bearbeitet aus Sicherheitsgründen **keine**
GPO automatisch (zu großer, geteilter Wirkungsradius). `-GPOCheck` macht ein
solches Risiko sichtbar, **bevor** es zu stillen Fehlfunktionen führt.

**Was geprüft wird und wie:**

| Bereich | Prüfmethode | Dauer |
|---|---|---|
| Audit-Richtlinien (9 Unterkategorien) | Rein lesend: `audit.csv` aller GPOs im SYSVOL | Sekunden |
| Unterkategorien erzwingen (Registry) | Rein lesend: `GptTmpl.inf` (Registry Values) derselben GPOs | Sekunden |
| Event Log Readers (Gruppenmitgliedschaft) | Rein lesend: `GptTmpl.inf` (Eingeschränkte Gruppen) derselben GPOs | Sekunden |
| SACL | Nicht betroffen — AD-repliziertes Objekt, kein Gruppenrichtlinien-Refresh-Mechanismus. Nur Hinweistext, kein Test. | — |
| Firewall (3 Regeln) | Aktiver Test: testweise aktiviert, `-GPOCheckWaitMinutes` gewartet, erneut geprüft, danach **immer** auf Ausgangswert zurückgesetzt (kein bleibender Seiteneffekt) | Standard 6 Minuten |

**Konsequenz für den produktiven Lauf**, je nach Ergebnis:

| Bereich | Kein GPO-Konflikt | GPO-Konflikt gefunden |
|---|---|---|
| Audit-Richtlinien | Normaler Lauf reicht aus, Einstellung bleibt dauerhaft stehen. | Stattdessen [New-CAROObserverAuditGPO.ps1](#new-carobserverauditgpops1--dedizierte-gpo-statt-lokaler-audit-einstellung) verwenden (siehe Entscheidungsbaum in [README.md](README.md)). |
| Event Log Readers | Normaler Lauf reicht aus, Mitgliedschaft bleibt bestehen. | Konto muss zusätzlich manuell in der „Eingeschränkte Gruppen"-Liste der genannten GPO eingetragen werden. |
| Firewall | Normaler Lauf reicht aus, Regeln bleiben aktiv. | Betroffene Regeln müssen zusätzlich in der zuständigen Firewall-GPO aktiviert werden. |

Der normale Lauf schadet in keinem Fall — die Frage ist nur, ob er **allein**
ausreicht oder **zusätzlich** eine manuelle GPO-Anpassung (bzw. die dedizierte
Audit-GPO) nötig ist, damit die Einstellung dauerhaft hält.

**Ausgabe:** Neben dem üblichen Log schreibt `-GPOCheck` einen eigenen,
menschenlesbaren Bericht mit den konkreten Handlungsempfehlungen:
`CARO-Observer-GPOCheck_<Server>_<Zeitstempel>.log` (siehe „Erzeugte Dateien").

**Bekannte Einschränkung:** Bei mehreren GPOs mit widersprüchlichen
Einstellungen im selben Bereich wird nicht die volle
RSoP-Präzedenzauflösung (Vererbung, Erzwungen, Verknüpfungsreihenfolge)
nachgebildet — der Check meldet, *dass* mindestens eine zuständige GPO die
benötigte Unterkategorie nicht korrekt abdeckt, nennt aber ggf. nicht
zwingend die einzelne „gewinnende" GPO. Bei mehreren infrage kommenden GPOs
zusätzlich `gpresult /h` prüfen.

## Erzeugte Dateien

Alle Dateien landen in `-OutputPath` (Standard: `CARO-Observer-Setup-Logs` neben dem
Script), benannt mit Servername und Zeitstempel:

| Datei                                         | Inhalt                                                                                          |
|------------------------------------------------|---------------------------------------------------------------------------------------------------|
| `CARO-Observer-Setup_<Server>_<Zeitstempel>.log`         | Vollständiges Textprotokoll: jeder Schritt, alle Fehler und Warnungen, mit Zeitstempel.           |
| `CARO-Observer-DesiredSettings_<Server>_<Zeitstempel>.json` | Strukturierte Liste aller **Ziel**-Einstellungen (Titel, Beschreibung, Befehl, Zielwert) — unabhängig davon, ob sie angewendet wurden. |
| `CARO-Observer-Backup_<Server>_<Zeitstempel>.json`       | Je Einstellung: Original- und neuer Wert, Befehl, Zeitstempel, Status (`Geändert`, `Bereits korrekt`, `Übersprungen`, `Nur gelesen (Report) …`, `Fehler …`). Grundlage für `-RestoreFrom`. |
| `CARO-Observer-GPOCheck_<Server>_<Zeitstempel>.log`      | Nur bei `-GPOCheck`: menschenlesbarer Bericht mit Ergebnis je Bereich und konkreter Handlungsempfehlung, falls eine GPO etwas verwaltet. |

Bei `-ReportOnly` werden dieselben zwei Dateien geschrieben (kein Log-Eintrag
mit Status `Geändert`, da nichts angewendet wird) — die Backup-Datei ist
trotzdem eine vollständige, für `-RestoreFrom` nutzbare Ist-Zustands-Momentaufnahme
(siehe „Rollback"). Bei `-GPOCheck` werden nur das Log und der GPOCheck-Bericht
geschrieben — keine Backup- oder DesiredSettings-Datei, da hier nichts
angewendet oder angestrebt wird.

## Rollback

Ein Rollback-Lauf mit `-RestoreFrom <Backup-Datei>` liest die Backup-JSON und
bietet für **jeden Eintrag, für den ein echter Originalwert vorliegt**, an,
ihn — wieder mit derselben Klartext-Bestätigung — auf diesen Wert
zurückzusetzen. Das ist unabhängig vom Status: `Geändert`, `Bereits korrekt`,
`Übersprungen`, `Nur gelesen (Report) - ...` und `Fehler: ...` (Setzen
fehlgeschlagen, aber Lesen erfolgreich) enthalten alle einen gültigen
`OriginalValueRaw`-Wert und werden gleichermaßen restauriert. Für `Bereits
korrekt`/bereits konforme Einträge ist das ein No-op (Ist- und Sollwert sind
identisch), richtet also nichts an.

**Jede** Backup-Datei — auch aus einem reinen `-ReportOnly`-Lauf, auch wenn
das Script vorher noch nie etwas geändert hat — ist damit vollwertig für
`-RestoreFrom` nutzbar.

Einzige Ausnahme: **`Fehler beim Lesen`** (ohne Doppelpunkt) — hier ist schon
das Lesen des Ist-Zustands gescheitert, es gibt also keinen echten Wert, auf
den zurückgesetzt werden könnte. Dieser eine Eintrag wird beim Rollback
übersprungen.

Der Rollback-Lauf erzeugt selbst wieder ein eigenes Log und eine eigene
Backup-Datei.

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
- Für `Event Log Readers` auf einem DC **ohne** ActiveDirectory-PowerShell-Modul
  greift ein LDAP/ADSI-Eigenbau, der sich in der Praxis als weniger robust
  erwiesen hat als die Modul-Cmdlets. Empfehlung: `RSAT-AD-PowerShell` auf dem
  DC installieren, dann wird dieser Pfad automatisch bevorzugt.

## New-CAROObserverAuditGPO.ps1 — dedizierte GPO statt lokaler Audit-Einstellung

Zweites, eigenständiges Script im selben Verzeichnis. Löst gezielt genau das
eine Problem, das `-GPOCheck` oben aufdecken kann: Eine bestehende
Gruppenrichtlinie verwaltet bereits Advanced-Audit-Policy-Unterkategorien und
setzt dadurch die lokal per `auditpol` gesetzten CARO-Werte bei jedem
Sicherheitsrichtlinien-Refresh zurück. Anstatt die betroffene fremde GPO
manuell zu bearbeiten, legt dieses Script eine **neue, ausschließlich für
CARO zuständige GPO** an (Name laut PDF-Vorschlag: `CARO-AD-Observer-Audit`)
und verknüpft sie mit der Domain-Controllers-OU. Windows führt Advanced
Audit Policy mehrerer GPOs pro Unterkategorie zusammen (Merge) — die neue GPO
koexistiert daher mit der bestehenden, solange keine der beiden dieselbe
Unterkategorie widersprüchlich belegt.

**Wichtiger Unterschied zum Hauptscript:** `Set-CAROObserverPrerequisites.ps1`
wirkt ausschließlich lokal auf den Server, auf dem es läuft. Dieses Script
schreibt dagegen in **geteilte, domänenweite Infrastruktur** (neue GPO,
Verknüpfung mit einer OU) — mit entsprechend größerer Tragweite. Jeder
Schritt wird einzeln im Klartext angezeigt und bestätigt, genau wie beim
Hauptscript. In einer Testdomäne verifiziert — trotzdem vor jedem
produktiven Einsatz zuerst in einer eigenen Testdomäne durchlaufen lassen und
den erzeugten GPO-Inhalt zusätzlich in `gpmc.msc` gegenprüfen.

**Was die neue GPO enthält** (ausschließlich das, kein anderer Inhalt):

- Sicherheitsoption „Unterkategorien erzwingen" (`SCENoApplyLegacyAuditPolicy`)
- Dieselben 9 Audit-Unterkategorien wie das Hauptscript, auf „Erfolg" gesetzt
- Registrierung der beiden zuständigen Client-Side-Extensions im AD-Attribut
  `gPCMachineExtensionNames` — ohne diesen Eintrag ignoriert der
  Group-Policy-Client den oben geschriebenen Inhalt vollständig, obwohl
  Verknüpfung und Berechtigungen korrekt sind (beim ersten Testlauf so
  gefunden: die GPO erschien nicht einmal unter „Angewendete
  Gruppenrichtlinienobjekte"). Die beiden GUID-Paare sind feste,
  windows-weit identische Kennungen — eine live verifiziert, die andere laut
  offizieller Microsoft-Spezifikation
  ([MS-GPAC](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-gpac/ac9c8234-d2e8-455d-be76-f84244dd1e58)).

### Voraussetzungen (zusätzlich zu denen des Hauptscripts)

- Das **GroupPolicy-PowerShell-Modul** (RSAT-GPMC) — anders als das
  Hauptscript, das bewusst ohne dieses Modul auskommt. Installieren mit
  `Install-WindowsFeature GPMC`. Das Script bricht mit einer klaren
  Fehlermeldung ab, falls es fehlt.
- Berechtigung zum Anlegen und Verknüpfen von GPOs in der Domäne (i. d. R.
  Domänen-Admin oder Mitgliedschaft in „Group Policy Creator Owners" plus
  Verknüpfungsrecht auf der Ziel-OU).

### Verwendung

```powershell
# Anlegen mit Standardwerten (Name "CARO-AD-Observer-Audit", Domain-Controllers-OU, Prioritaet 1)
.\New-CAROObserverAuditGPO.ps1

# Eigener Name / eigene Ziel-OU / andere Link-Prioritaet
.\New-CAROObserverAuditGPO.ps1 -GpoName "CARO-AD-Observer-Audit" -TargetOU "OU=Domain Controllers,DC=contoso,DC=com" -GpoLinkOrder 1

# Rueckbau: Verknuepfung loesen und die GPO wieder vollstaendig loeschen
.\New-CAROObserverAuditGPO.ps1 -RemoveGPO -BackupFile ".\CARO-Observer-Setup-Logs\CARO-Observer-AuditGPO-Backup_DC01_20260929-101500.json"
```

### Parameter

| Parameter        | Typ    | Default                                  | Beschreibung                                                                                           |
|-------------------|--------|--------------------------------------------|-----------------------------------------------------------------------------------------------------------|
| `-GpoName`        | string | `CARO-AD-Observer-Audit`                   | Name der neu anzulegenden GPO. Muss noch nicht existieren.                                               |
| `-TargetOU`       | string | `OU=Domain Controllers,<Domain-DN>`        | DN der OU, mit der die GPO verknüpft wird.                                                                |
| `-GpoLinkOrder`   | int    | `1`                                         | Link-Priorität bei der Verknüpfung (1 = höchste). Reine organisatorische Entscheidung, keine PDF-Vorgabe. |
| `-OutputPath`     | string | `.\CARO-Observer-Setup-Logs`               | Verzeichnis für Log- und Backup-Datei — dasselbe wie beim Hauptscript.                                    |
| `-RemoveGPO`      | switch | `false`                                     | Rückbau-Modus: löst Verknüpfung und löscht die GPO aus `-BackupFile`. Erfordert `-BackupFile`.            |
| `-BackupFile`     | string | *(nicht gesetzt)*                          | Pfad zu einer `CARO-Observer-AuditGPO-Backup-*.json` eines früheren Erstellungslaufs. Nötig bei `-RemoveGPO`. |
| `-AutoApprove`    | switch | `false`                                     | Überspringt die Einzelbestätigung. Angesichts der Tragweite (geteilte AD-Infrastruktur) nicht empfohlen.  |

### Erzeugte Dateien

Landen wie beim Hauptscript in `-OutputPath` (Standard:
`CARO-Observer-Setup-Logs`):

| Datei                                                    | Inhalt                                                                                           |
|------------------------------------------------------------|-----------------------------------------------------------------------------------------------------|
| `CARO-Observer-AuditGPO_<Server>_<Zeitstempel>.log`         | Textprotokoll: jeder Schritt (Anlegen, Registry-Option, Audit-Unterkategorien, Versionsnummer, Verknüpfung), alle Fehler und Warnungen. |
| `CARO-Observer-AuditGPO-Backup_<Server>_<Zeitstempel>.json` | GPO-GUID, Name, verknüpfte OU, Link-Priorität, Erstellungszeitpunkt — Grundlage für `-RemoveGPO`.  |

### Rückbau

```powershell
.\New-CAROObserverAuditGPO.ps1 -RemoveGPO -BackupFile "<CARO-Observer-AuditGPO-Backup-*.json aus dem Erstellungslauf>"
```

Löst die Verknüpfung und löscht die GPO vollständig. Da die GPO ausschließlich
von diesem Script angelegten Inhalt enthält (kein bestehender GPO-Inhalt wird
je verändert), ist das gefahrlos — es geht kein fremder Inhalt verloren. Die
Identifikation erfolgt über die in der Backup-Datei gespeicherte GPO-**GUID**,
nicht über den Namen, für den Fall, dass zwischenzeitlich umbenannt wurde.

## Lizenz / Haftung

Internes Hilfsscript ohne Gewähr. Vor Einsatz auf produktiven
Domänencontrollern in einer Testumgebung verifizieren.
