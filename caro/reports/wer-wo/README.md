# CARO Berechtigungen → Excel

## Zweck und Nutzung

Wertet den Report **„Wer hat wo Zugriff“ der CARO Suite (PDF)** aus und erzeugt daraus eine Excel-Datei, in der je Verzeichnis die **einzelnen berechtigten Benutzer** stehen – statt des Umwegs über die Gruppen. Das Werkzeug ist ausschließlich für diesen Reporttyp bestimmt; die übrigen Reporte der CARO Suite sind anders aufgebaut und dürfen hiermit nicht ausgewertet werden.

Die fertige Oberfläche ist eine einzige Datei: **`CARO-Berechtigungen.html`**. Doppelklick genügt, kein Server, keine Installation. Die Datei arbeitet vollständig im Browser; der Report verlässt den Rechner nicht.

## Haftungsausschluss

Dieses Werkzeug ist in freiwilliger Zusatzarbeit entstanden und nicht Bestandteil eines Produkts oder einer vertraglichen Leistung. Die Bereitstellung erfolgt ohne Support, ohne Pflegezusage und ohne jede Gewährleistung, insbesondere ohne Zusicherung von Richtigkeit, Vollständigkeit oder Eignung für einen bestimmten Zweck.

Die Nutzung erfolgt auf eigenes Risiko. Prüfung des Quellcodes und Validierung der Auswertungsergebnisse gegen den zugrunde liegenden Originalreport obliegen dem Anwender – zwingend, bevor aus den Ergebnissen Aussagen abgeleitet oder Änderungen an Berechtigungen vorgenommen werden. Eine Haftung für Schäden aus der Nutzung ist ausgeschlossen.

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

## Wie der Report gelesen wird

CARO kodiert die Metainformationen jeder Zeile als Zeichen einer Symbolschrift, die bei der Textextraktion erhalten bleiben. Daraus ergibt sich pro Zeile die Kontoart (Benutzer, Gruppe, lokales Konto, nicht aufgelöst) und ob ein Recht am Ordner **direkt** vergeben oder **vererbt** ist. Die Zuordnung dieser Zeichen wird aus der **Legende auf der letzten Seite** des Reports gelesen und ist nicht fest eingebaut. Nicht erkannte Zeilen werden gezählt und in der Oberfläche gemeldet, nie stillschweigend verworfen.

## Enthaltene Fremdkomponenten

Beide Bibliotheken sind in `CARO-Berechtigungen.html` eingebettet, damit die Datei ohne Internetverbindung arbeitet.

| Komponente | Version | Zweck | Lizenz |
|---|---|---|---|
| [pdf.js](https://mozilla.github.io/pdf.js/), Mozilla Foundation | 3.11.174 | PDF lesen | Apache 2.0 |
| [ExcelJS](https://github.com/exceljs/exceljs) | 4.4.0 | XLSX schreiben | MIT |

Die vollständigen Lizenztexte stehen in [`THIRD-PARTY-LICENSES.md`](THIRD-PARTY-LICENSES.md).

## Quellcode und Bauvorgang

Veröffentlicht wird die fertige Datei `CARO-Berechtigungen.html`. Quelldateien, Build- und Testskripte sind nicht Teil dieser Veröffentlichung.

## Lizenz

MIT-Lizenz, Copyright © 2026 Connectware Distributions GmbH – siehe [`LICENSE`](LICENSE). Nutzung, Änderung und Weitergabe sind frei, solange der Copyright- und Lizenzhinweis erhalten bleibt.

Die Lizenz gilt für den eigenen Code dieses Werkzeugs. Für die eingebetteten Bibliotheken gelten die Bedingungen in [`THIRD-PARTY-LICENSES.md`](THIRD-PARTY-LICENSES.md).
