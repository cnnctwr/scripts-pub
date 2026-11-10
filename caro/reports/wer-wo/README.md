# CARO Berechtigungen → Excel

Wertet einen **Berechtigungs-Report der CARO Suite (PDF)** aus und erzeugt daraus eine Excel-Datei, in der je Verzeichnis die **einzelnen berechtigten Benutzer** stehen – statt des Umwegs über die Gruppen.

Die fertige Oberfläche ist eine einzige Datei: **`CARO-Berechtigungen.html`**. Doppelklick genügt, kein Server, keine Installation. Die Datei arbeitet vollständig im Browser; der Report verlässt den Rechner nicht.

## Benutzung

1. `CARO-Berechtigungen.html` im Browser öffnen (Chrome oder Edge).
2. Die PDF-Datei des Reports hineinziehen.
3. Im Ordnerbaum das Verzeichnis anhaken, um das es geht.
4. Einstellungen prüfen, Vorschau ansehen, **Excel-Datei speichern**.

Der Dateiname entsteht automatisch, zum Beispiel:

```
2026-11-10_1356_Berechtigungen_Marketing_mit-Unterordnern.xlsx
```

Datum und Uhrzeit vorn sind **Erstellzeitpunkt des Reports**, nicht der Tag des Exports – der Name sagt also, von wann die Daten sind. Er lässt sich vor dem Speichern noch ändern.

## Einstellungen

| Schalter | Wirkung |
|---|---|
| **Unterordner mit auswerten** | Zu jedem gewählten Ordner kommen alle darunterliegenden Verzeichnisse mit. Standard: an. |
| **Jedes Recht in eine eigene Zeile** | Aus steht ein Benutzer einmal je Verzeichnis, seine Rechte stehen als Kürzel nebeneinander. An bekommt jedes Recht eine eigene Zeile – gut zum Filtern, rund ein Drittel mehr Zeilen. Standard: aus. |
| **Jedermann-Gruppen auflösen** | Betrifft `Benutzer`, `Domänen-Benutzer` und `Authentifizierte Benutzer`. Aus erscheinen sie als eine Zeile „alle Mitglieder“, die Namen stehen im Blatt „Gruppen und Mitglieder“. An werden sie je Ordner ausmultipliziert – das sind schnell mehrere Tausend Zeilen. Standard: aus. |
| **Lokale Systemkonten** | `Lokales System` und vergleichbare Konten des Fileservers. Sie stehen in jedem Ordner. Standard: aus. |
| **Tabellenblatt je Ordner der obersten Ebene** | Jede Abteilung bekommt zusätzlich ein eigenes Blatt. Standard: aus. |

## Die Tabellenblätter

| Blatt | Inhalt |
|---|---|
| **Übersicht** | Reportkopf, Scanzeit, gewählte Einstellungen, Kennzahlen, Lücken, Erklärung der Spalten |
| **Berechtigte Benutzer** | Das Kernblatt: eine Zeile pro Verzeichnis + Benutzer, die Rechte als Kürzelliste, mit Gruppe, Mitgliedschaft und Vergabe. Verweigerte Rechte stehen in einer eigenen Spalte |
| **Matrix** | Verzeichnisse in den Zeilen, Konten in den Spalten, Kürzel in der Zelle |
| **Ordner** | Alle Verzeichnisse mit Besitzer, Anzahl berechtigter Konten und direkt vergebener Rechte |
| **Zugriffsrechte Gruppen** | Rohsicht wie im PDF, ohne Auflösung – die Gegenprobe zum Kernblatt |
| **Gruppen und Mitglieder** | Jede Gruppe mit ihren Mitgliedern, inklusive der über Untergruppen geerbten |
| **Direkt vergeben** | Nur die Stellen, an denen ein Recht am Ordner selbst hängt statt vererbt zu sein – das Prüfblatt |
| **Nicht aufgelöst** | Erscheint nur, wenn es etwas zu melden gibt: SIDs, gekürzte Gruppen, nicht erkannte Zeilen |

Alle Listenblätter haben Autofilter und eine fixierte Kopfzeile.

## Kürzel der Rechte

Die Kürzel sind die von CARO, in der Reihenfolge stark → schwach:

| Kürzel | Recht | Kürzel | Recht |
|---|---|---|---|
| **FC** | Vollzugriff | **W** | Schreiben |
| **MD** | Ändern | **L** | Ordnerinhalt anzeigen |
| **M-** | Eingeschränktes Ändern | **L-** | Eingeschränktes Auflisten |
| **RX** | Lesen und Ausführen | **S** | Spezial |
| **R** | Lesen | | |

In der Matrix bedeutet ein angehängtes `!`, dass das Recht verweigert wird. Spalten mit Kürzeln stehen in nicht-proportionaler Schrift, damit `L` und `L-` unterscheidbar bleiben.

## Grenzen, die im PDF liegen

Das Werkzeug kann nur auswerten, was im Report steht. Diese drei Fälle werden erkannt und in der Oberfläche sowie im Blatt „Nicht aufgelöst“ ausgewiesen, statt stillschweigend zu fehlen:

- **Gekürzte Mitgliederlisten.** Steht im Report „16 weitere Mitglieder.“, sind diese Namen nicht enthalten. Wenn sie gebraucht werden: die Begrenzung in CARO abschalten und den Report neu erzeugen.
- **Nicht aufgelöste Konten.** Steht im Report nur eine SID, kennt auch die Excel-Datei nur die SID (Kontoart „nicht aufgelöst“).
- **Verschachtelte Gruppen ohne eigene Mitgliederliste.** CARO löst im Anhang nur die Gruppen auf, die in den Zugriffsrechten vorkommen. Ist eine davon selbst Mitglied einer weiteren Gruppe, die der Report nicht aufführt, erscheint eine Zeile „Untergruppe ohne Mitglieder im Report: …“.

## Aufbau und Weiterentwicklung

```
CARO-Berechtigungen.html   fertige Oberfläche (gebaut, nicht direkt bearbeiten)
src/parser.js              Report lesen, Gruppen in Benutzer auflösen
src/excel.js               Aufbau der Arbeitsmappe
src/app.js                 Oberfläche
src/tool.template.html     Gerüst und Gestaltung
vendor/                    pdf.js 3.11.174, ExcelJS 4.4.0 (eingebettet, kein Internet nötig)
tools/build.cjs            baut alles zu einer Datei zusammen
tools/test.cjs             prüft Parser und Excel-Aufbau gegen einen echten Report
tools/browsertest.cjs      öffnet die gebaute Datei in Chrome und exportiert wirklich
```

Nach Änderungen in `src/`:

```sh
node tools/build.cjs
node tools/test.cjs <report.pdf>
node tools/browsertest.cjs <report.pdf>
```

### Wie der Report gelesen wird

CARO kodiert die Metainformationen jeder Zeile als Zeichen einer Symbolschrift, die bei der Textextraktion erhalten bleiben. Daraus ergibt sich pro Zeile die Kontoart (Benutzer, Gruppe, lokales Konto, nicht aufgelöst) und ob ein Recht am Ordner **direkt** vergeben oder **vererbt** ist. Die Zuordnung dieser Zeichen liest der Parser aus der **Legende auf der letzten Seite** des Reports – ändert CARO die Symbolschrift, bleibt die Auswertung dadurch gültig. Nicht erkannte Zeilen werden gezählt und gemeldet, nie verworfen.
