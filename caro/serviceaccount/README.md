# CARO ServiceAccount Setup

PowerShell-Skript, das einen Service-Account für die CARO-Suite anlegt und ihm genau die Rechte gibt, die CARO für den vollen Funktionsumfang braucht. Die Rechte gelten nur in den OUs, die der Ausführende angibt.

> **Das Skript muss auf dem CARO-Server ausgeführt werden.** Es sagt das beim Start ausdrücklich und verlangt eine Bestätigung. Der Service-Account wird in die lokalen Administratoren dieses Rechners eingetragen.

Das Skript führt interaktiv durch alle Entscheidungen. Zu jeder Option steht vorher, was sie bewirkt. Zeigt eine Eingabe sich als ungültig, fragt das Skript erneut. Es fällt nie stillschweigend auf einen Standard zurück.

## Teststatus

Die Logik ohne Zielsystem (Aktionsliste, Rechte-Bausteine, Config-Prüfung, Report, Eingaben, Log) hat automatische Tests (Pester). **Der Lauf gegen ein echtes Active Directory, Exchange, Fileserver und einen SQL-Server wurde noch nicht durchgeführt.** Bitte zuerst `-Mode Plan` und danach `-Mode Apply -WhatIf` auf dem CARO-Server ausprobieren, dann erst echt anwenden.

## Voraussetzungen

| Voraussetzung | Hinweis |
|---|---|
| Windows PowerShell 5.1 | auf dem CARO-Server |
| Start als Administrator (erhöht) | wegen der lokalen Gruppenänderung |
| Rechner ist Mitglied der Domäne | |
| Modul ActiveDirectory (RSAT) | Feature "RSAT: Active Directory-Modul für Windows PowerShell" |
| Der Ausführende darf Konten anlegen und AD-Delegationen setzen | z. B. Domänenadministrator |
| Nur bei Exchange: Exchange Management Tools bzw. Management Shell | muss `Add-RoleGroupMember` bereitstellen |
| Nur bei Fileservern: WinRM erreichbar und Rechte, lokale Gruppen dort zu ändern | |
| Nur beim Datenbank-Konto, wenn das Skript die SQL-Rechte selbst vergibt: Verbindung zum SQL-Server (TCP) und `sysadmin`-Rechte des ausführenden Admins | Ohne diese Rechte bietet das Skript eine SQL-Datei für den DBA an. |

Fehlt eine Voraussetzung, **bricht das Skript ab**. Es simuliert nichts.

## Installation und Weitergabe

**Einfachster Weg: die Einzeldatei.** `dist\CARO-ServiceAccount-Setup.ps1` ist eine einzige Datei, die ohne weitere Dateien läuft. Sie lässt sich per GitHub, Chat oder E-Mail weitergeben. Die Datei ist reines ASCII (Umlaute stehen als ae, oe, ue), damit sie nach dem Einfügen in einen beliebigen Editor fehlerfrei läuft.

Die Attributliste bleibt eine eigene, bearbeitbare Datei: `dist\CARO-AD-Attributes.json`. Das Skript sucht sie in dieser Reihenfolge: 1. neben dem Skript, 2. im Unterordner `CARO-ServiceAccount-Setup-Logs`, 3. die im Skript eingebettete Kopie. Die Datei muss nur mitgegeben werden, wenn die Liste angepasst werden soll.

Das Skript kann aus jedem Verzeichnis gestartet werden. Alle Ausgaben landen im Ordner `CARO-ServiceAccount-Setup-Logs` neben dem Skript. Wird das Skript ohne Datei gestartet (z. B. direkt in die Konsole eingefügt), ist es das aktuelle Verzeichnis.

**Einzeldatei neu erzeugen:** Nach jeder Änderung in `src` erzeugt `python3 scripts/build_single_file.py` die Dateien in `dist` neu. Ein Test meldet, wenn die Einzeldatei nicht mehr zu `src` passt.

**Entwicklungsfassung:** Wer in `src` arbeitet, kopiert den **gesamten Ordner `src`** (nicht nur die .ps1-Datei). Er enthält `CARO-ServiceAccount-Setup.ps1`, den Ordner `Private\` mit den Bibliotheksdateien und `CARO-AD-Attributes.json`.

## Aufruf

```powershell
.\CARO-ServiceAccount-Setup.ps1                  # fragt nach dem Modus
.\CARO-ServiceAccount-Setup.ps1 -Mode Plan
.\CARO-ServiceAccount-Setup.ps1 -Mode Apply -ConfigPath <Config.json> -WhatIf
.\CARO-ServiceAccount-Setup.ps1 -Mode Apply -ConfigPath <Config.json>
.\CARO-ServiceAccount-Setup.ps1 -Mode Rollback -ResultPath <Result.json>
```

### Parameter

| Parameter | Bedeutung |
|---|---|
| `-Mode` | `Plan`, `Apply` oder `Rollback`. Ohne Angabe fragt das Skript nach dem Modus. |
| `-ConfigPath` | Nur Apply: Pfad der Config.json. Ohne Angabe bietet das Skript die jüngsten Dateien zur Auswahl an. |
| `-ResultPath` | Nur Rollback: Pfad der Result.json. Ohne Angabe bietet das Skript die jüngsten Dateien zur Auswahl an. |
| `-WhatIf` | Bei Apply und Rollback: alle Aktionen anzeigen, nichts ändern. Result.json bzw. Rollback.json werden trotzdem geschrieben und als WhatIf-Lauf markiert. |

Hilfe im Skript: `Get-Help .\CARO-ServiceAccount-Setup.ps1 -Full`

### Modi

| Modus | Ändert etwas? | Zweck |
|---|---|---|
| **Plan** | nein | Fragen stellen, Umgebung nur lesend prüfen, Config.json und Report.md erzeugen. Am Ende kann direkt Apply gestartet werden. |
| **Apply** | ja | Config.json ausführen. Zeigt vorher eine Zusammenfassung (Was, Wo, Warum) und verlangt die Eingabe von `JA`. Stoppt beim ersten Fehler. |
| **Rollback** | ja | Baut zurück, was ein früherer Apply-Lauf **neu angelegt** hat (nach Result.json). Verlangt die Eingabe von `JA`. |

### Exitcodes

| Code | Bedeutung |
|---|---|
| 0 | erfolgreich |
| 1 | Fehler, Voraussetzung fehlt oder nicht bestätigt (Apply, Rollback) |
| 2 | Abbruch: nicht auf dem CARO-Server oder Plan ohne Ergebnis |

## Ablauf des Plans

1. **Startbanner:** Das Skript sagt, dass es auf dem CARO-Server laufen muss, und fragt, ob der erkannte Rechner der CARO-Server ist.
2. **Voraussetzungen** werden geprüft.
3. **Übersicht "Was kommt auf Sie zu":** alle Bereiche mit ihren Funktionen und Rechten sowie die Zusatzbereiche, bevor etwas gefragt wird.
4. **Bereiche des Accounts:** freie Mehrfachauswahl (siehe unten). Danach wird nur noch abgefragt, was gewählt wurde.
5. **Profil** (nur bei Active Directory): `Voller CARO-Umfang` (alle Funktionen der Bereiche) oder `Anpassen` (Funktionen je Bereich abwählen).
6. **Service-Account:** SamAccountName, Anzeigename, Beschreibung, OU, Kennwortstrategie. Existiert der Account schon, wird er angezeigt und es wird gefragt, ob er übernommen werden soll. Bei einem reinen Datenbank-Account kann es stattdessen ein SQL-Konto sein.
7. **AD-Bereiche und OUs:** Je Bereich (Benutzerkonten, Gruppen, Bereinigung inaktiver Benutzer, Weitere Gruppen für neue Benutzer) nennt das Skript in einem Satz, was CARO tut, und fragt dann **„Wo darf CARO das tun?“**: [1] in bestimmten OUs (schließt alle untergeordneten OUs ein), [2] in der ganzen Domäne oder [3] gar nicht. Bei [1] fragt es „In welcher OU soll das erfolgen?“ und wiederholt die Frage („Weitere OU hinzufügen?“), solange du weitere OUs angeben willst. Danach zeigt es als Bestätigung, welche Rechte der Service-Account dort bekommt (deutscher Name und Windows-Begriff).

   **OU-Eingabe ohne Domänenteil:** OUs werden ohne `DC=...` eingegeben, von der tiefsten OU nach oben, z. B. `OU=Service,OU=Accounts`. Das Skript ergänzt die Domäne automatisch (`OU=Service,OU=Accounts,DC=firma,DC=de`) und zeigt sie bei jeder Frage an. Wer den Domänenteil trotzdem mit eingibt, wird nicht gestört. Jede OU wird im AD geprüft. Bei einem Tippfehler zeigt das Skript den vollständigen Namen, den es gesucht hat, und nennt die Unter-OUs der übergeordneten OU. Ist das Objekt zwar vorhanden, aber eine **Gruppe** (oder ein anderer Objekttyp), sagt das Skript das ausdrücklich: Dort lassen sich keine Benutzer verschieben, es wird eine OU oder ein Container gebraucht. OUs beginnen mit `OU=`, nur Container wie `CN=Users` und Gruppen beginnen mit `CN=`.
8. **Attribut-Strategie** (wird immer ausdrücklich gefragt, siehe unten).
9. **Exchange**, **Fileserver** und **Datenbank**, soweit gewählt.
10. **Zustand prüfen** (nur lesend): Was besteht schon, was ist neu? Bei einem **neuen** Account prüft das Skript bei den lokalen Gruppen nur, ob die Gruppe existiert, und listet ihre Mitglieder nicht auf (Windows protokolliert jede Auflistung als eigenes Sicherheitsereignis 4799). Nur bei einem übernommenen Account werden die Mitglieder gelesen.
11. **Zusammenfassung** aller Aktionen. Config.json und Report.md werden geschrieben.

Am Ende **jedes Bereichs** (Active Directory, Exchange, Fileserver, Datenbank) fragt das Skript: „Diese Angaben übernehmen?“ Bei „Nein“ wird nur dieser Bereich noch einmal abgefragt. So lässt sich eine Eingabe korrigieren, ohne neu zu starten.

## Für welche Bereiche ist ein Account?

Zu Beginn wählst du frei, für welche Bereiche der Account gelten soll, mit Nummern, durch Komma getrennt (Enter = 1,2,3):

| Nr. | Bereich |
|---|---|
| 1 | Active Directory |
| 2 | Fileserver |
| 3 | Exchange |
| 4 | Datenbank (SQL Server) |

Der vorgeschlagene Kontoname ist `sa-caro` plus ein Kürzel je Bereich in fester Reihenfolge: `ad` (Active Directory), `fs` (Fileserver), `ex` (Exchange), `db` (Datenbank). Beispiele: `sa-caro-ad`, `sa-caro-db`, `sa-caro-adfs`, `sa-caro-adfsex`. Enter übernimmt den Vorschlag, du kannst ihn überschreiben.

Jede Kombination geht, zum Beispiel `4` für einen reinen Datenbank-Account, `1,2` für AD und Fileserver oder `1,2,3,4` für alles in einem Account. Für weitere Accounts rufst du das Skript erneut auf.

Die Mitgliedschaft in den **lokalen Administratoren des CARO-Servers** bekommt nur ein Account, der AD, Fileserver oder Exchange bedient. Ein reiner Datenbank-Account bekommt sie nicht.

## Active Directory: Bereiche und Rechte

Je Bereich fragt das Skript, wo CARO das tun darf: in bestimmten OUs, in der ganzen Domäne oder gar nicht. Alle Rechte gelten **pro OU inklusive aller Unter-OUs**. Verwaltet werden Benutzer und Gruppen. Computer-Objekte sind nicht Teil des Umfangs. Lesen braucht keine Delegation (Standard-AD).

#### Benutzerkonten

CARO legt Benutzerkonten an, löscht sie und ändert sie.

| Funktion | Windows-Recht |
|---|---|
| Benutzer anlegen | Create User objects |
| Benutzer löschen | Delete User objects |
| Benutzerattribute bearbeiten | Read/Write Properties |
| Kennwort zurücksetzen | Reset Password, Write pwdLastSet |
| Konto deaktivieren und aktivieren | Write userAccountControl |
| Konto entsperren | Write lockoutTime |
| Ablaufdatum des Kontos bearbeiten | Write accountExpires |
| Benutzer verschieben | Delete + Create User objects |

#### Gruppen

CARO legt Gruppen an, z. B. Berechtigungsgruppen für Fileserver, ändert und löscht sie und ändert deren Mitglieder (auch automatisch über Smart Permissions).

| Funktion | Windows-Recht |
|---|---|
| Gruppen anlegen, umbenennen und ändern | Create Group objects, Read/Write All Properties |
| Gruppen löschen | Delete Group objects |
| Gruppenmitglieder ändern | Write Members |
| Unter-OUs anlegen und löschen | Create/Delete OU objects |

#### Bereinigung inaktiver Benutzer

Die CARO-Bereinigung verschiebt Benutzer, die sich x Tage nicht angemeldet haben, in eine eigene OU und löscht sie dort nach weiteren x Tagen. Zum Verschieben braucht CARO dort technisch dasselbe Recht wie zum Anlegen von Benutzern.

| Funktion | Windows-Recht |
|---|---|
| Benutzer aufnehmen (Verschieben hierher) | Create User objects |
| Benutzer löschen | Delete User objects |
| Konto deaktivieren | Write userAccountControl |

#### Weitere Gruppen für neue Benutzer

Optional: Gruppen außerhalb der oben genannten Gruppen-OU, in die CARO neue Benutzer beim Anlegen einträgt. Dort darf CARO nur Mitglieder ändern.

| Funktion | Windows-Recht |
|---|---|
| Gruppenmitglieder ändern | Write Members |

**Domänenweit:** Statt einer OU kann die ganze Domäne gewählt werden. Gibt man die Domäne selbst als OU ein (z. B. `DC=firma,DC=de`), behandelt das Skript das genauso und verlangt dieselben Bestätigungen. Das Skript warnt dann ausdrücklich und verlangt bei Bereichen mit Anlegen, Löschen oder Verschieben von Benutzern eine zweite Bestätigung.

**Wichtig zur OU-Auswahl:** Ein CARO-Scan läuft über die ganze Domäne, **ändern** kann CARO aber nur dort, wo der Account Rechte hat. Nicht durchführbare Änderungen werden von CARO dokumentiert.

### Benutzerattribute: Alle Eigenschaften oder Attributliste

Wenn eine gewählte Funktion Benutzer-Eigenschaften braucht, fragt das Skript **immer ausdrücklich und ohne Standard**:

| Wahl | Wirkung |
|---|---|
| **Alle Eigenschaften** (Write All Properties) | Volle Funktionalität. Auch sicherheitsrelevante Eigenschaften der Benutzer sind beschreibbar. |
| **Nur die Attributliste** (Property-specific) | Weniger Rechte. **Je nach Auswahl können einige CARO-Funktionen nicht funktionieren**, wenn ein benötigtes Attribut in der Liste fehlt. |

Die Attributliste steht in `CARO-AD-Attributes.json` neben dem Skript und darf bearbeitet werden. Fehlt die Datei, nutzt das Skript die eingebettete Liste. Wählt man dann im Plan "Liste nicht verwenden", legt das Skript die Vorlage in den Unterordner `CARO-ServiceAccount-Setup-Logs` (zu den anderen JSON-Dateien und Logs). Man passt sie dort an und startet den Plan neu. Die Datei hat dann Vorrang vor der eingebetteten Liste. Grundlage ist CAROs eigene Aufgabe "Create new user" (`examples/cts.manage.nativeActiveDirectoryStandardUser.json`). Für die gewählten Funktionen ergänzt das Skript automatisch die Pflichtattribute `userAccountControl`, `lockoutTime`, `accountExpires` und `pwdLastSet`. Das Kennwort wird nicht als Attribut geschrieben, sondern über das Recht "Reset Password". Attribute, die es im Active Directory nicht gibt (z. B. `extensionAttribute1` bis `15` ohne Exchange-Schemaerweiterung), meldet der Plan und gibt sie nicht frei. Apply überspringt sie ebenfalls mit einem Hinweis, statt abzubrechen.

## Exchange (On-Premises)

| Wahl | Rollengruppe | Wirkung |
|---|---|---|
| Kein Exchange | | nichts wird geändert |
| Management | `Organization Management` | CARO kann Exchange verwalten (Postfächer aktivieren oder erstellen, Abwesenheitsnotizen, Vollzugriff, Senden-als, Limits, SMTP) |
| Read-Only | `View-Only Organization Management` | nur Analysen, die Verwaltungsaufgaben funktionieren damit nicht |

Das Skript prüft, ob die Rollengruppe existiert, und trägt den Account mit `Add-RoleGroupMember` ein. Ist der Account schon in der anderen Rollengruppe, warnt das Skript und entfernt nichts. **Exchange Online und Entra ID** werden in CARO über die App-Registrierung "CARO-Suite M365 Connector" angebunden, nicht über dieses Skript.

## Fileserver

| Wahl | Mitgliedschaft auf dem Fileserver | Wirkung |
|---|---|---|
| Kein Fileserver | | nichts wird geändert |
| Lesen | `Backup Operators` (S-1-5-32-551), `Print Operators` (S-1-5-32-550) | Berechtigungen und Freigaben (Share-Permissions) auslesen |
| Verwalten | zusätzlich `Administrators` (S-1-5-32-544) | Ordner anlegen und löschen, Besitzer ändern, Vererbung schalten, Zugriffsrechte ändern |

Einzelrechte pro Ordner (Traverse, Berechtigungen ändern) reichen für den vollen Umfang nicht aus und werden nicht umgesetzt.

### Domänencontroller als Zielrechner

Ist der CARO-Server oder ein Fileserver zugleich ein **Domänencontroller** (z. B. in einer Testumgebung, in der alles auf einem Rechner läuft), warnt das Skript ausdrücklich, **verweigert aber nichts**. Auf einem Domänencontroller sind die „lokalen“ Gruppen **Domänengruppen** (Container Builtin) und gelten für die ganze Domäne. Der Service-Account hätte dann praktisch Domänenadministrator-Rechte (Administrators), dürfte Dateien und Registrierung der Domänencontroller sichern und wiederherstellen (Backup Operators) und Druckertreiber laden (Print Operators). Die Warnung steht in der Zusammenfassung des Plans, im Report und noch einmal vor der Bestätigung bei Apply. In der Praxis sollten CARO-Server und Fileserver keine Domänencontroller sein. Gruppen werden über ihre SID angesprochen, nicht über den (sprachabhängigen) Namen.

## Datenbank-Konto (SQL Server)

CARO schreibt seine Daten in eine SQL-Datenbank. Dafür braucht es ein Konto mit `db_owner` auf der CARO-Datenbank, oder mit `dbcreator`, wenn der CARO-Configurator die Datenbank selbst anlegen soll. Die meisten Admins nehmen dafür ein eigenes Konto. Das Skript legt es an, wenn der Bereich „Datenbank“ gewählt ist.

| Auswahl | Möglichkeiten |
|---|---|
| Kontoart | **Windows-Konto** (neues AD-Konto, bekommt Zugriff auf den SQL-Server) oder, nur bei einem reinen Datenbank-Account, **SQL-Konto** (SQL-Login mit Kennwort, ohne AD-Konto) |
| Rechte | **DB-Owner** (`db_owner`, Standard, nur auf der CARO-Datenbank) oder **DB-Creator** (`dbcreator`, größeres Recht auf dem ganzen Server) |
| Vergabe | **direkt** im SQL-Server, **SQL-Datei für den DBA** oder, nur beim Windows-Konto, **gar nicht** (nur das Konto anlegen) |

**DB-Owner:** Das Skript fragt den Namen der Datenbank. Existiert sie nicht, legt es sie nach Rückfrage mit den **Standardeinstellungen** des SQL-Servers an. Das Konto braucht dadurch nur `db_owner` und nicht `dbcreator`. Den Datenbanknamen trägst du später im CARO-Configurator ein.

**Direkte Vergabe:** Das Skript fragt SQL-Server (Rechnername) und Instanz (Enter = Standardinstanz), verbindet sich mit dem Windows-Konto des ausführenden Admins und prüft, ob dieser `sysadmin` ist. Ist keine Verbindung möglich oder fehlen Rechte, bietet es an: Server neu eingeben, eine andere Option wählen (ein Schritt zurück zu Rechten und Vergabe), eine **SQL-Datei für den DBA** erzeugen oder abbrechen.

**SQL-Datei für den DBA:** `...-CARO-SA-Datenbank.sql` im Ordner der Logdateien. Sie enthält Datenbank (falls nötig), Login, Benutzer und Rolle. Bei einem SQL-Konto steht darin ein Platzhalter statt des Kennworts, das Kennwort gibt der Admin dem DBA auf sicherem Weg.

**Hinweise für den CARO-Configurator:** Am Ende von Plan und Apply listet das Skript, was im Bereich „Datenbank“ des Configurators einzutragen ist: SQL-Server, Instanz, DB-Name, Benutzer, Windows-Domäne und ob „Windows-Konto verwenden“ gilt. Das Kennwort steht nie darin.

**Rollback:** Entfernt Rolle, Benutzer und Login, die das Skript angelegt hat. Eine **Datenbank wird nie gelöscht**, auch nicht, wenn das Skript sie angelegt hat, denn dort könnten schon Daten liegen.

## Kennwort

Bei einem neuen Account wählt man: **generieren** (24 Zeichen, wird genau **einmal** angezeigt, danach wird die Anzeige gelöscht) oder **selbst eingeben** (verdeckt, mit Wiederholung). Das Kennwort steht **nie** in Config, Result, Report oder Log. Es wird erst bei Apply abgefragt bzw. erzeugt. Der Plan fragt nur die Strategie.

## Vorhandener Account

Existiert der Account schon, zeigt das Skript ihn (DN, aktiv, Beschreibung, Gruppen) und fragt, ob er übernommen werden soll. Bei "Ja" werden nur fehlende Rechte ergänzt. Kennwort und Attribute bleiben unverändert, und **ein Rollback löscht einen übernommenen Account nicht**.

## Ausgabedateien

Alle Dateien liegen im Ordner `CARO-ServiceAccount-Setup-Logs` neben dem Skript. Schema: `<yyyy-MM-dd-HHmmss>-CARO-SA-<Typ>.<Endung>`

| Datei | Inhalt | Modus |
|---|---|---|
| `...-Plan.log`, `...-Apply.log`, `...-Rollback.log` | Laufzeitprotokoll: Zeit, Stufe, Meldung, Objekt, Ergebnis. Wird **ab der ersten Zeile** geschrieben, auch bei Abbruch oder Fehler. Auch die Eingaben stehen darin (Kennwörter nie). | jeder Lauf |
| `...-Config.json` | geplante Aktionen mit Was, Wo, Warum und dem Zustand bei Plan | Plan |
| `...-Report.md` | lesbare Zusammenfassung für Review und Freigabe | Plan |
| `...-Datenbank.sql` | SQL-Datei für den DBA, wenn die SQL-Rechte nicht direkt vergeben werden | Apply |
| `...-Result.json` | tatsächlich ausgeführte Aktionen mit Status (`Created`, `AlreadyPresent`, `Error`, `WhatIf`) und den Angaben für den Rollback | Apply |
| `...-Rollback.json` | tatsächlich zurückgebaute Aktionen | Rollback |

Kennungen: `ConfigurationId` und `PlanId` stehen in der Config, `ExecutionId` in der Result-Datei.

## Rollback

- Es wird nur zurückgebaut, was im Result mit Status `Created` steht. Was schon vorhanden war (`AlreadyPresent`), bleibt.
- Reihenfolge: umgekehrt zum Apply, der Account wird zuletzt gelöscht.
- Der Account wird nur gelöscht, wenn die gespeicherte SID zum erwarteten SamAccountName passt.
- Ein zweiter Rollback ist ungefährlich: Fehlendes wird als "nicht mehr vorhanden" gemeldet.

## Tests

```powershell
Install-Module Pester -MinimumVersion 5.0 -Scope CurrentUser
Invoke-Pester .\tests
```

Die Tests prüfen unter anderem, dass diese README jeden Parameter, jeden Modus, jede Ausgabedatei und jeden Bereich und jede Funktion des Katalogs nennt. Sie prüfen außerdem, dass die Einzeldatei in `dist` aktuell, reines ASCII und ohne weitere Dateien startfähig ist.

## Bekannte Grenzen und ungeprüfte Punkte

- Nicht Teil dieses Skripts: **Observer** (eigene Voraussetzungen auf den Domänencontrollern), **Entra ID** und **Exchange Online** (App-Registrierung), **Computer-Objekte**, Einzelrechte pro Ordner.
- **Verschieben von Benutzern:** Die genauen AD-Rechte (Löschen im Quell-OU, Anlegen im Ziel-OU) sind nach Microsoft-Standard abgeleitet und noch nicht gegen ein echtes AD getestet. Alle Rechte stehen in `src\Private\03-Catalog.ps1` und können dort angepasst werden.
- **Datenbank:** Der SQL-Teil (Verbindung, Datenbank, Login, Rechte) ist nicht gegen einen echten SQL-Server getestet. Die angelegte Datenbank hat die Standardeinstellungen des SQL-Servers (Sortierung, Dateipfade). Ob CARO bestimmte Einstellungen erwartet, ist nicht belegt.
- **Exchange Read-Only:** Es ist nicht belegt, ob die Rolle für alle CARO-Analysen reicht.
- „Unter-OUs anlegen und löschen“ (Smart Permissions) gehört fest zum Bereich Gruppen und steht offen in der Rechteliste. Im Profil „Anpassen“ lässt es sich abwählen.
- **CARO-Observer:** Er zeigt nach bisherigem Eindruck die Zeit, zu der er ein Ereignis **eingelesen** hat, nicht unbedingt die Zeit, zu der es passiert ist. Die tatsächliche Reihenfolge der Aktionen steht im Apply-Log und in der Ereignisanzeige des Domänencontrollers.
- Windows PowerShell 5.1: Die .ps1-Dateien in `src` müssen als UTF-8 mit BOM gespeichert bleiben (sonst werden Umlaute falsch gelesen). Die Einzeldatei in `dist` ist reines ASCII und davon nicht betroffen. Beides prüfen Tests.

## Projektstruktur

| Pfad | Inhalt |
|---|---|
| `dist\CARO-ServiceAccount-Setup.ps1` | **Einzeldatei-Fassung zum Weitergeben** (erzeugt, nicht von Hand bearbeiten) |
| `dist\CARO-AD-Attributes.json` | Attributliste (bearbeitbar), liegt der Einzeldatei bei |
| `scripts\build_single_file.py` | erzeugt `dist` aus `src` |
| `src\CARO-ServiceAccount-Setup.ps1` | Hauptskript (Entwicklungsfassung) |
| `src\Private\` | Bibliotheksdateien: Log, Eingaben, Katalog der Rechte, Aktionsliste, Umgebung, AD-Rechte, Plan, Apply, Rollback |
| `src\CARO-AD-Attributes.json` | Attributliste (Quelle) |
| `tests\` | Pester-Tests |
| `docs\ANFORDERUNGEN.md` | Anforderungen |
| `docs\2026-09-Benutzerhandbuch.md` | Textauszug des CARO-Handbuchs (Funktionskontext) |
| `docs\archive\` | Überholte Dokumente |
| `examples\` | CAROs Beispiel-Aufgabe "Create new user" |
