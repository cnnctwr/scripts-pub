# XRechnung-XML / XRechnung-PDF

## Zweck und Nutzung

`XRechnung-PDF.html` verarbeitet **PDF** (ZUGFeRD / Factur-X) und **XML** (UBL/CII). Bei PDF wird das eingebettete XML herausgelöst, geprüft und die PDF-Struktur geprüft (Tab „PDF-Struktur“). Erkennt UBL 2.1 und CII (XRechnung, ZUGFeRD/Factur-X, Peppol).

Alles läuft lokal, es wird nichts hochgeladen.

Teilprüfung, ersetzt nicht den KoSIT-Validator (kein Schema, nicht alle Regeln).

## Haftungsausschluss

Dieses Werkzeug ist in freiwilliger Zusatzarbeit entstanden und nicht Bestandteil eines Produkts oder einer vertraglichen Leistung. Die Bereitstellung erfolgt ohne Support, ohne Pflegezusage und ohne jede Gewährleistung, insbesondere ohne Zusicherung von Richtigkeit, Vollständigkeit oder Eignung für einen bestimmten Zweck.

Die Nutzung erfolgt auf eigenes Risiko. Prüfung des Quellcodes und Validierung der Prüfergebnisse gegen die zugrunde liegende Original-Rechnungsdatei obliegen dem Anwender – zwingend, bevor aus den Ergebnissen Aussagen abgeleitet oder Entscheidungen über eine Rechnung getroffen werden. Eine Haftung für Schäden aus der Nutzung ist ausgeschlossen.

## Benutzung

1. `XRechnung-PDF.html` herunterladen und per Doppelklick im Browser öffnen.
2. XML hineinziehen (mehrere Dateien möglich).

**XML aus PDF speichern:** Button erscheint nur bei einem PDF. Speichert die Originalbytes des Anhangs unter dem Namen des PDF mit Endung `.xml`. Chrome/Edge: Dialog zur Ordnerauswahl; Firefox/Safari: Download-Ordner.

`examples/`: anonymisierte Beispiele (CII, Factur-X Extended).

## Einstellungen

Prüfmodus oben: automatisch nach BT-24, nur EN 16931, oder XRechnung erzwingen.

## Das Ergebnis

- **Prüfung:** Fehler / Warnungen / Hinweise mit Regel-Nr. (EN 16931, XRechnung BR-DE, Peppol) und BT-Nummer.
- **Rechnung:** Verkäufer, Käufer, Positionen, Steuer, Summen, Zahlung. Zum Abgleich mit dem PDF.
- **XML-Baum:** Struktur eingerückt, je Element Bezeichnung + BT/BG-Nummer + Rohname + Inhalt.

PDF-Prüfung: XML-Anhang vorhanden, Dateiname, Beziehung (AFRelationship), Medientyp, Eintrag in AF-Liste, PDF/A-3-Kennzeichnung, XMP-Erweiterung (Dateiname, Typ, Profil) und Abgleich Profil PDF ↔ BT-24 im XML.

## Grenzen

Die vollständige PDF/A-3-Konformität (Schriften, Farbprofile) wird nicht geprüft (dafür veraPDF). Die PDF-Funktion wurde bisher nur mit selbst erzeugten Test-PDFs geprüft, nicht mit PDFs echter Rechnungsprogramme. Ohne eingebettetes XML kommt eine Fehlermeldung.

## Enthaltene Fremdkomponenten

Enthält pdf-lib 1.17.1 (MIT) eingebettet, läuft offline. Die übrigen Komponenten bringt pdf-lib selbst mit; sie stecken im selben eingebetteten Block.

| Komponente | Version | Zweck | Lizenz |
|---|---|---|---|
| [pdf-lib](https://pdf-lib.js.org) | 1.17.1 | PDF lesen, Anhänge und XMP auswerten | MIT |
| [@pdf-lib/standard-fonts](https://github.com/Hopding/standard-fonts) | in pdf-lib 1.17.1 enthalten | Metriken der PDF-Standardschriften | MIT |
| [@pdf-lib/upng](https://github.com/Hopding/UPNG.js) | in pdf-lib 1.17.1 enthalten | PNG-Bilddaten lesen | MIT |
| [pako](https://github.com/nodeca/pako) | in pdf-lib 1.17.1 enthalten | PDF-Datenströme ent- und packen (zlib) | MIT |
| [tslib](https://github.com/microsoft/tslib), Microsoft Corporation | in pdf-lib 1.17.1 enthalten | Hilfsfunktionen des TypeScript-Compilers | Apache 2.0 |

Die vollständigen Lizenztexte stehen in [`THIRD-PARTY-LICENSES.md`](THIRD-PARTY-LICENSES.md).

## Lizenz

MIT-Lizenz, Copyright © 2026 Connectware Distributions GmbH – siehe [`LICENSE`](LICENSE). Nutzung, Änderung und Weitergabe sind frei, solange der Copyright- und Lizenzhinweis erhalten bleibt.

Die Lizenz gilt für den eigenen Code dieses Werkzeugs. Für die eingebetteten Bibliotheken gelten die Bedingungen in [`THIRD-PARTY-LICENSES.md`](THIRD-PARTY-LICENSES.md).
