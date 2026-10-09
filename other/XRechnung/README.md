# XRechnung-XML / XRechnung-PDF

`XRechnung-PDF.html` per Doppelklick im Browser öffnen, XML hineinziehen (mehrere Dateien möglich). Alles läuft lokal, es wird nichts hochgeladen.

- **Prüfung:** Fehler / Warnungen / Hinweise mit Regel-Nr. (EN 16931, XRechnung BR-DE, Peppol) und BT-Nummer.
- **Rechnung:** Verkäufer, Käufer, Positionen, Steuer, Summen, Zahlung. Zum Abgleich mit dem PDF.
- **XML-Baum:** Struktur eingerückt, je Element Bezeichnung + BT/BG-Nummer + Rohname + Inhalt.
- Erkennt UBL 2.1 und CII (XRechnung, ZUGFeRD/Factur-X, Peppol).
- Prüfmodus oben: automatisch nach BT-24, nur EN 16931, oder XRechnung erzwingen.

## Datei
`XRechnung-PDF.html` verarbeitet **PDF** (ZUGFeRD / Factur-X) und **XML** (UBL/CII). Bei PDF wird das eingebettete XML herausgelöst, geprüft und die PDF-Struktur geprüft (Tab „PDF-Struktur“). Enthält pdf-lib 1.17.1 (MIT) eingebettet, läuft offline. Ohne eingebettetes XML kommt eine Fehlermeldung.

**XML aus PDF speichern:** Button erscheint nur bei einem PDF. Speichert die Originalbytes des Anhangs unter dem Namen des PDF mit Endung `.xml`. Chrome/Edge: Dialog zur Ordnerauswahl; Firefox/Safari: Download-Ordner.

PDF-Prüfung: XML-Anhang vorhanden, Dateiname, Beziehung (AFRelationship), Medientyp, Eintrag in AF-Liste, PDF/A-3-Kennzeichnung, XMP-Erweiterung (Dateiname, Typ, Profil) und Abgleich Profil PDF ↔ BT-24 im XML.

Grenzen: Teilprüfung, ersetzt nicht den KoSIT-Validator (kein Schema, nicht alle Regeln). Die vollständige PDF/A-3-Konformität (Schriften, Farbprofile) wird nicht geprüft (dafür veraPDF). Die PDF-Funktion wurde bisher nur mit selbst erzeugten Test-PDFs geprüft, nicht mit PDFs echter Rechnungsprogramme.

`examples/`: anonymisierte Beispiele (CII, Factur-X Extended).
