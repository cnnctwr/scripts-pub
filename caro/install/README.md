# CARO-Suite - Updater und Installer 

Dieses Skript hält die **CARO-Suite für Berechtigungsmanagement** auf dem aktuellen Stand.
Es laedt die neueste Version von der CUSATUM-Homepage, entpackt sie und installiert sie automatisch.
Du kannst das aber auch weiterhin wie gewohnt selbst durchführen für volle Kontrolle.

[https://cusatum.de/wp-content/uploads/1618/31/CARO-Suite-Setup.zip](https://cusatum.de/wp-content/uploads/1618/31/CARO-Suite-Setup.zip)

Es sit aber kein Auto-Installer der selbstständig läuft sondern muss vom Administrator gestartet werden.
Der Prozess von Herunterladen, Entpacken, Berechtigen, Ausführen und Klicken der Bestätignen entfällt und die Installation läuft nach einmaliger Zustimmung komplett durch.

---

## Voraussetzungen

- Windows mit PowerShell 5.1 oder neuer
- Internetverbindung
- Administratorrechte auf dem Rechner

---

## Einmalige Einrichtung

1. Skript herunterladen: [caro-install.ps1](caro-install.ps1)
2. Beim Herunterladen erscheint moeglicherweise eine Browser-Warnung wegen ausfuehrbarer Dateien -- bestaetigen und Datei behalten.
3. Die Datei vor dem ersten Start an den Ort verschieben, an dem sie dauerhaft verbleiben soll -- zum Beispiel in einen festen Ordner auf dem Server. Der Speicherort sollte danach nicht mehr geaendert werden.
4. Datei per **Rechtsklick** oeffnen und **"Mit PowerShell ausfuehren"** waehlen.

Beim ersten Start legt das Skript automatisch eine Verkuepfung namens **"CARO Auto-Updater"** auf dem Desktop an, die auf die Skript-Datei an ihrem aktuellen Speicherort zeigt. Ab dann genuegt ein Doppelklick auf diese Verkuepfung -- die Skript-Datei selbst sollte danach nicht mehr verschoben werden.

---

## Was das Skript tut

1. **Verkuepfung anlegen** -- einmalig beim ersten Start, danach uebersprungen.
2. **Bestaetigung einholen** -- kurze Rueckfrage bevor etwas heruntergeladen wird. Im selben Hinweis steht der Pfad, unter dem Handbuch, Lizenz und Release Notes nach der Installation zu finden sind.
3. **ZIP herunterladen** -- vom CUSATUM-Server in den Downloads-Ordner, Dateiname mit aktuellem Zeitstempel.
4. **Entpacken** -- in einen Unterordner im Downloads-Ordner, ebenfalls mit Zeitstempel benannt.
5. **ZIP loeschen** -- der entpackte Ordner bleibt erhalten.
6. **Version pruefen** -- das Skript liest die Versionsnummer aus der MSI und vergleicht sie mit der installierten Version.
7. **Installation:**
   - **Neue Version oder Erstinstallation** -- laeuft automatisch mit Fortschrittsanzeige durch, kein Klicken noetig.
   - **Gleiche Version bereits installiert** -- zeigt den Wartungsdialog: Software reparieren, aendern oder entfernen.

---

## Wo landen die Dateien?

Alle heruntergeladenen und entpackten Dateien landen im **Downloads-Ordner** des angemeldeten Benutzers, in einem automatisch erzeugten Unterordner mit Zeitstempel:

```
C:\Users\<Benutzername>\Downloads\2026-06-11-143022-CARO-Suite-Setup\
```

Dieser Ordner enthaelt nach dem Entpacken unter anderem Handbuch, Lizenzbestimmungen und Release Notes. Er wird nicht automatisch geloescht und kann spaeter manuell bereinigt werden.
