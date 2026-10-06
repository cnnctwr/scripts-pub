# CARO ServiceAccount Setup

PowerShell-Skript, das einen Service-Account für die CARO-Suite anlegt und ihm genau die Rechte gibt, die CARO für den vollen Funktionsumfang braucht. Die Rechte gelten nur in den OUs, die der Ausführende angibt.

> **Das Skript muss auf dem CARO-Server ausgeführt werden.** Es sagt das beim Start ausdrücklich und verlangt eine Bestätigung. Der Service-Account wird in die lokalen Administratoren dieses Rechners eingetragen.

Das Skript führt interaktiv durch alle Entscheidungen. Zu jeder Option steht vorher, was sie bewirkt. Zeigt eine Eingabe sich als ungültig, fragt das Skript erneut. Es fällt nie stillschweigend auf einen Standard zurück.

## Teststatus

Die Logik ohne Zielsystem (Aktionsliste, Rechte-Bausteine, Config-Prüfung, Report, Eingaben, Log) hat automatische Tests (Pester). **Der Lauf gegen ein echtes Active Directory, Exchange und Fileserver wurde noch nicht durchgeführt.** Bitte zuerst `-Mode Plan` und danach `-Mode Apply -WhatIf` auf dem CARO-Server ausprobieren, dann erst echt anwenden.

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
4. **Profil:** `Voller CARO-Umfang` (alle Funktionen der Bereiche) oder `Anpassen` (Funktionen je Bereich abwählen).
5. **Service-Account:** SamAccountName, Anzeigename, Beschreibung, OU, Kennwortstrategie. Existiert der Account schon, wird er angezeigt und es wird gefragt, ob er übernommen werden soll.
6. **AD-Bereiche und OUs:** Zu jedem Bereich zeigt das Skript **zuerst** die Funktionen mit dem dafür vergebenen Recht und fragt **danach**, ob CARO den Bereich nutzen soll.

   Dann: je Bereich (Benutzerkonten, Gruppen, Bereinigung inaktiver Benutzer) eine oder mehrere OUs (Schleife "Weitere OU hinzufügen?") oder die ganze Domäne. Optional schlägt das Skript aus einer Basis-OU die Unter-OUs vor.

   **OU-Eingabe ohne Domänenteil:** OUs werden ohne `DC=...` eingegeben, von der tiefsten OU nach oben, z. B. `OU=Service,OU=Accounts`. Das Skript ergänzt die Domäne automatisch (`OU=Service,OU=Accounts,DC=firma,DC=de`) und zeigt sie bei jeder Frage an. Wer den Domänenteil trotzdem mit eingibt, wird nicht gestört. Jede OU wird im AD geprüft. Bei einem Tippfehler zeigt das Skript den vollständigen Namen, den es gesucht hat, und nennt die Unter-OUs der übergeordneten OU. Ist das Objekt zwar vorhanden, aber eine **Gruppe** (oder ein anderer Objekttyp), sagt das Skript das ausdrücklich: Dort lassen sich keine Benutzer verschieben, es wird eine OU oder ein Container gebraucht. OUs beginnen mit `OU=`, nur Container wie `CN=Users` und Gruppen beginnen mit `CN=`.
7. **Attribut-Strategie** (wird immer ausdrücklich gefragt, siehe unten).
8. **Exchange** und **Fileserver.**
9. **Zustand prüfen** (nur lesend): Was besteht schon, was ist neu? Bei einem **neuen** Account prüft das Skript bei den lokalen Gruppen nur, ob die Gruppe existiert, und listet ihre Mitglieder nicht auf (Windows protokolliert jede Auflistung als eigenes Sicherheitsereignis 4799). Nur bei einem übernommenen Account werden die Mitglieder gelesen.
10. **Zusammenfassung** aller Aktionen. Config.json und Report.md werden geschrieben.

## Active Directory: Bereiche und Rechte

Das Skript fragt je Bereich, ob CARO ihn nutzen soll, und danach, in welchen OUs. Alle Rechte gelten **pro OU inklusive aller Unter-OUs**. Verwaltet werden Benutzer und Gruppen. Computer-Objekte sind nicht Teil des Umfangs. Lesen braucht keine Delegation (Standard-AD).

#### Benutzerkonten

CARO legt Benutzerkonten an, löscht sie und ändert sie.

| Funktion | Wirkung und vergebenes Recht |
|---|---|
| Benutzer anlegen | CARO darf in dieser OU neue Benutzerkonten anlegen (Recht: Create User objects). |
| Benutzer löschen | CARO darf Benutzerkonten in dieser OU löschen (Recht: Delete User objects). Gelöschte Konten lassen sich nur mit Aufwand wiederherstellen. |
| Benutzerattribute bearbeiten | CARO darf Attribute von Benutzern ändern (Name, Telefon, Abteilung, Manager, Erweiterungsattribute u. a.). Der Umfang richtet sich nach Ihrer späteren Wahl: alle Eigenschaften oder nur die Attributliste. |
| Kennwort zurücksetzen | CARO darf Kennwörter zurücksetzen und die Änderung bei der nächsten Anmeldung erzwingen (Recht: Reset Password, Schreiben von pwdLastSet). |
| Konto deaktivieren und aktivieren | CARO darf Konten deaktivieren und aktivieren (Schreiben von userAccountControl). |
| Konto entsperren | CARO darf gesperrte Konten entsperren (Schreiben von lockoutTime). |
| Ablaufdatum des Kontos bearbeiten | CARO darf das Ablaufdatum eines Kontos ändern (Schreiben von accountExpires). |
| Benutzer verschieben | CARO darf Benutzer aus dieser OU in andere OUs verschieben, z. B. in die OU für deaktivierte Benutzer (Rechte: Löschen hier, Anlegen im Ziel). Das Ziel muss selbst eine angegebene OU sein. |

#### Gruppen

CARO legt Gruppen an, z. B. Berechtigungsgruppen für Fileserver, und ändert deren Mitglieder. Das geschieht auch automatisch über Smart Permissions.

| Funktion | Wirkung und vergebenes Recht |
|---|---|
| Gruppen anlegen, umbenennen und ändern | CARO darf Gruppen anlegen, umbenennen und deren Eigenschaften setzen (Rechte: Create Group objects, Read/Write All Properties auf Gruppen). |
| Gruppen löschen | CARO darf Gruppen in dieser OU löschen (Recht: Delete Group objects). |
| Gruppenmitglieder ändern | CARO darf Mitglieder zu Gruppen hinzufügen und entfernen (Recht: Write Members). |
| Unter-OUs anlegen (Smart Permissions) | CARO darf in dieser OU weitere OUs anlegen und löschen, z. B. eine Unter-OU je Fileserver (Rechte: Create/Delete OU objects). |

#### Bereinigung inaktiver Benutzer

Der CARO-Baustein zur Bereinigung verschiebt Benutzer, die sich x Tage nicht angemeldet haben, in eine eigene OU und löscht sie dort nach weiteren x Tagen.

| Funktion | Wirkung und vergebenes Recht |
|---|---|
| Benutzer aufnehmen (Verschieben hierher) | CARO darf Benutzer in diese OU verschieben. Technisch ist dafür dasselbe Recht nötig wie zum Anlegen (Create User objects). CARO könnte hier also auch Benutzer neu anlegen. Das lässt sich in AD nicht trennen. |
| Benutzer löschen | CARO darf dort Benutzer löschen (Baustein "Deaktivierte Benutzer in einer OU löschen"). |
| Konto deaktivieren | CARO darf dort Konten deaktivieren (Schreiben von userAccountControl). |

#### Weitere Gruppen für neue Benutzer

Optional: Gruppen außerhalb der oben genannten Gruppen-OU, in die CARO neue Benutzer beim Anlegen automatisch einträgt. Dort darf CARO nur Mitglieder ändern.

| Funktion | Wirkung und vergebenes Recht |
|---|---|
| Gruppenmitglieder ändern | CARO darf nur Mitglieder hinzufügen und entfernen (Recht: Write Members). Kein Anlegen oder Löschen von Gruppen. |

**Domänenweit:** Statt einer OU kann die ganze Domäne gewählt werden. Gibt man die Domäne selbst als OU ein (z. B. `DC=firma,DC=de`), behandelt das Skript das genauso und verlangt dieselben Bestätigungen. Das Skript warnt dann ausdrücklich und verlangt bei Bereichen mit Anlegen, Löschen oder Verschieben von Benutzern eine zweite Bestätigung.

**Wichtig zur OU-Auswahl:** Ein CARO-Scan läuft über die ganze Domäne, **ändern** kann CARO aber nur dort, wo der Account Rechte hat. Nicht durchführbare Änderungen werden von CARO dokumentiert.

### Benutzerattribute: Alle Eigenschaften oder Attributliste

Wenn eine gewählte Funktion Benutzer-Eigenschaften braucht, fragt das Skript **immer ausdrücklich und ohne Standard**:

| Wahl | Wirkung |
|---|---|
| **Alle Eigenschaften** (Write All Properties) | Volle Funktionalität. Auch sicherheitsrelevante Eigenschaften der Benutzer sind beschreibbar. |
| **Nur die Attributliste** (Property-specific) | Weniger Rechte. **Je nach Auswahl können einige CARO-Funktionen nicht funktionieren**, wenn ein benötigtes Attribut in der Liste fehlt. |

Die Attributliste steht in `CARO-AD-Attributes.json` neben dem Skript und darf bearbeitet werden. Fehlt die Datei, nutzt das Skript die eingebettete Liste. Wählt man dann im Plan "Liste nicht verwenden", legt das Skript die Vorlage in den Unterordner `CARO-ServiceAccount-Setup-Logs` (zu den anderen JSON-Dateien und Logs). Man passt sie dort an und startet den Plan neu. Die Datei hat dann Vorrang vor der eingebetteten Liste. Grundlage ist CAROs eigene Aufgabe "Create new user" (`examples/cts.manage.nativeActiveDirectoryStandardUser.json`). Für die gewählten Funktionen ergänzt das Skript automatisch die Pflichtattribute `userAccountControl`, `lockoutTime`, `accountExpires` und `pwdLastSet`. Das Kennwort wird nicht als Attribut geschrieben, sondern über das Recht "Reset Password".

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
- **Exchange Read-Only:** Es ist nicht belegt, ob die Rolle für alle CARO-Analysen reicht.
- Das Anlegen und Löschen von Unter-OUs (Smart Permissions) wird nur auf Wunsch vergeben.
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
