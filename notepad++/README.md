# Notepad++ Auto-Update

Dieses Skript ([Update-NotepadPlusPlus.ps1](Update-NotepadPlusPlus.ps1)) haelt eine bestehende
**Notepad++**-Installation auf einem Windows Server automatisch aktuell. Es laedt den offiziellen
silent-Installer von GitHub Releases herunter und installiert ihn -- gesteuert ueber eine
selbst angelegte geplante Aufgabe.

---

## Voraussetzungen

- Windows Server mit **Windows PowerShell 5.1** oder **PowerShell 7+** (beides kompatibel)
- Administratorrechte (`#Requires -RunAsAdministrator`)
- Ausgehender Internetzugang zu `api.github.com` und `github.com` (Port 443) -- ohne
  direkten GitHub-Zugriff funktioniert die Versionspruefung/der Download nicht

---

## Einmalige Einrichtung

1. Skript nach **`C:\Scripts\Update-NotepadPlusPlus.ps1`** kopieren.
2. Einmal manuell in einer **erhoehten** PowerShell-Sitzung ausfuehren.

> ⚠️ **Wichtig: Ablageort vor dem ersten Start final festlegen.**
> Beim ersten Lauf legt das Skript die geplante Aufgabe an und schreibt dabei den **aktuellen
> Speicherort der Datei fest in die Aufgabe hinein** (`-File "C:\Scripts\Update-NotepadPlusPlus.ps1"`).
> Bei jedem weiteren Lauf wird nur noch geprueft, ob die Aufgabe *existiert* -- der hinterlegte
> Pfad wird **nicht** aktualisiert. Wird das Skript danach verschoben oder umbenannt, laeuft der
> naechste manuelle Aufruf zwar weiterhin problemlos (der Pfad wird dabei dynamisch neu ermittelt),
> aber die **geplante Aufgabe zeigt weiterhin auf den alten Pfad** und schlaegt beim naechsten
> automatischen Lauf (Sonntag 03:00 Uhr) mit "Datei nicht gefunden" fehl.
> Falls ein Verschieben unumgaenglich ist: Aufgabe **"Notepad++ Update"** in der Aufgabenplanung
> loeschen -- sie wird beim naechsten Lauf am neuen Ort automatisch mit dem korrekten Pfad neu angelegt.

---

## Was das Skript bei jedem Lauf tut

1. **Versionspruefung** -- installierte Version (Registry/Dateisystem) mit der aktuellen Version
   auf GitHub vergleichen.
2. **Pruefung geplante Aufgabe** -- existiert die Aufgabe **"Notepad++ Update"** bereits?
   Falls nicht: anlegen (siehe unten).
3. Ist die installierte Version bereits aktuell → **kein Download**, Skript beendet sich hier.
4. Nur falls ein Update noetig ist:
   - Pruefen, ob Notepad++ **gerade laeuft** → falls ja: **Abbruch** (kein Download, keine Installation).
   - **Download** des passenden Installers (Architektur wird automatisch erkannt: x64 / x86 / ARM64).
   - **Integritaetspruefung** (Ersatz fuer "Entpacken", da der offizielle Installer eine einzelne
     EXE ohne Archiv ist): Authenticode-Signatur des Installers wird verifiziert.
   - Erneute Pruefung, ob Notepad++ inzwischen gestartet wurde.
   - **Silent-Installation** (`/S`) in das automatisch ermittelte Installationsverzeichnis.
   - Erfolg wird ueber die neu installierte Versionsnummer verifiziert.
5. **Aufraeumen** -- temporaeres Download-Verzeichnis wird in jedem Fall geloescht (Erfolg,
   Abbruch oder Fehler), es bleiben keine Ueberbleibsel zurueck.

---

## Geplante Aufgabe

| Eigenschaft | Wert |
|---|---|
| Name | `Notepad++ Update` |
| Zeitplan | woechentlich, **Sonntag, 03:00 Uhr** |
| Ausfuehrender Benutzer | `SYSTEM` |
| Rechteebene | Höchste Rechte (Highest) |

---

## Logging

- Verzeichnis: **`%ProgramData%\Notepad++`** -- wird angelegt, falls es noch nicht existiert.
- Ein eigenes Log pro Lauf: `YYYY-MM-DD-hh-mm-Update.log`
- Jeder Schritt (Versionspruefung, Aufgabenpruefung, Download, Integritaetspruefung, Installation)
  sowie alle Fehler werden mit Zeitstempel protokolliert.

---

## Architektur-Erkennung

Wird automatisch anhand von `PROCESSOR_ARCHITECTURE` und `[Environment]::Is64BitOperatingSystem`
bestimmt -- lädt den passenden Installer (`x64`, `x86` oder `arm64`) ohne manuelle Konfiguration.

---

## Bekannte Annahmen

- **Versionsquelle:** GitHub Releases API (`notepad-plus-plus/notepad-plus-plus`). Falls der
  Server keinen direkten Zugriff auf GitHub hat, muss dies auf einen internen Mirror/Proxy
  umgestellt werden.
- **Log-Dateiname:** `...-Update.log` (als sinnvolle Interpretation von "udate" angenommen).

---

## Deinstallation / Entfernen

1. Geplante Aufgabe **"Notepad++ Update"** in der Aufgabenplanung loeschen.
2. Datei `Update-NotepadPlusPlus.ps1` aus `C:\Scripts` entfernen.
3. Logs unter `%ProgramData%\Notepad++` bei Bedarf manuell loeschen (werden vom Skript nicht
   automatisch bereinigt).
