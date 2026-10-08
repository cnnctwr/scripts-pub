
## Kurzanleitung zum Erstellen von eigenen Templates für die Nutzeranlage

### Features

* Vorbelegung von Gruppen und Vorgesetztem
* Bildungsvorschriften für Namensfelder und E-Mail, mit Testmodus (Vorschau)
* Kennwort: Zufall (CARO-Standard) oder eigenes
* Ablaufdatum des Kontos flexibel wählbar
* Pflichtfelder wählbar
* Felder und ganze Abschnitte abwählbar

### Vorgehen

- legen sie die [CARO-UserTemplates.html](CARO-UserTemplates.html) in ein beliebiges Verzeichnis auf dem CARO-Server
- öffnen sie die HTML durch Doppelklick (empfohlen: Chrome oder Edge)
- klicken sie rechts oben auf **JSON laden**
- das JSON für die Standard-Nutzeranlage liegt hier:

`C:\Program Files\CUSATUM Service GmbH\CARO\server\tools\manage\cts.manage.nativeActiveDirectoryStandardUser.json`
- öffnen sie die angegebene Datei
    - ggf. vorab Kopien anlegen, der Builder ändert aber die Original-Datei nicht
    - immer die Standard-JSON der **installierten CARO-Version** laden; nach einem CARO-Update die neue Datei verwenden (zum Beispiel enthält sie das aktuelle Zufallskennwort)

### Muss geändert werden

- vergeben sie als erstes und unbedingt eine **neue, eindeutige Template-ID**
- vergeben sie ebenfalls aussagekräftige und eindeutige Namen für
    - Name (Deutsch/Englisch) – das ist der Menüpunkt in CARO
    - Beschreibung (Deutsch/Englisch)

    um die Einträge später im Menü klar unterscheiden zu können
- „JSON speichern“ wird orange und fragt nach, solange etwas offen ist

### Felder anpassen

- jedes Feld hat links einen Haken zum Ein- und Ausschalten, jeder Abschnitt oben ebenfalls
- **Pflicht:** bei jedem Feld lässt sich festlegen, ob in CARO ein Wert eingetragen werden muss (ob das Feld überhaupt erscheint, regelt der Haken links)
    - fest vorgegeben (nicht änderbar): Vorname, Nachname, SamAccountName, UserPrincipalName, Allgemeiner Name, Kennwort, Änderungskommentar
- hinter jedem Feldnamen steht in Klammern der **AD-Attributname** (zum Beispiel `Büro (physicalDeliveryOfficeName)`), damit klar ist, welches Attribut gemeint ist
- **Vorname und Nachname** sind im Template nicht beschreibbar, sie werden erst in CARO eingegeben
- **Bildungsvorschrift:** SamAccountName, UserPrincipalName, Anzeigename und Allgemeiner Name werden in CARO automatisch aus Vor- und Nachname gebildet. Je Feld lässt sich eine von mehreren festen Vorschriften wählen (die oberste ist der Standard):
    - SamAccountName und UserPrincipalName: `Vorname.Nachname`, `V.Nachname`, `Nachname`, erster Buchstabe + 7 Buchstaben Nachname, `VornameNachname`
    - Anzeigename und Allgemeiner Name: `Nachname, Vorname`, `Vorname Nachname`, `Vorname.Nachname`
    - der SamAccountName ist auf 20 Zeichen gekürzt; Umlaute werden umgewandelt (ä → ae) und Leerzeichen entfernt
- **Testmodus** (Knopf im Abschnitt „LDAP - notwendig“): Beispielnamen und Suffix eintippen, die Zeilen zeigen das Ergebnis jeder Vorschrift. Im Testmodus wird nichts gespeichert und das Speichern ist gesperrt. Er zeigt auch die Mailadresse, die sich laut den gewählten Vorschriften ergäbe (gelbe Zeile im Abschnitt „Allgemeines“, der dabei aufklappt)
- **UPN-Suffix:** CARO ermittelt ihn selbst (Domänenname aus den DC-Teilen der OU, z. B. `meine.firma.gmbh`). Ein eigener Wert im Feld ersetzt das
- **Mail:** keine Vorbelegung (Standard) oder die Adresse aus zwei unabhängig wählbaren Teilen zusammensetzen:
    - **Namensteil** (vor dem @): wie UserPrincipalName, wie SamAccountName (ohne Kürzung) oder offen
    - **Domänenteil** (hinter dem @): wie UPN-Suffix oder eine eigene Domäne
    - die Adresse folgt den oben gewählten Varianten für UPN und SamAccountName
    - bei „Namensteil offen“ ergänzt der Nutzer den Namen in CARO; er muss dafür zuerst die **Automatik am Feld ausschalten**. Bis ein Name davor steht, meldet CARO „Wert entspricht nicht dem Muster“
    - wird die Adresse von einer externen Instanz gesetzt (zum Beispiel Exchange), das Feld abwählen
- **Kennwort:** **Zufall** (CARO-Standard: CARO erzeugt beim Öffnen der Maske ein neues Kennwort, vor dem Anlegen kopieren, später nicht mehr einsehbar) oder **eigenes Kennwort** (mindestens 12 Zeichen; steht im Klartext in der JSON)
- **Ablaufdatum des Kontos:** drei Möglichkeiten: **läuft nie ab** (Standard), **nach N Tagen** (ab Anlage gerechnet, am Ablauftag um 23:59 Uhr) oder **festes Datum** mit Uhrzeit. CARO trägt das Datum beim Öffnen der Maske vor, der Nutzer kann es dort noch ändern. Die Uhrzeit gilt in der Ortszeit des Servers (im AD als UTC gespeichert, in CARO bestätigt). Fehleingaben (keine ganze Zahl, Datum in der Vergangenheit) sperren das Speichern
- **Gruppen** („Benutzer den Gruppen hinzufügen“): sAMAccountNames der Gruppen eintragen, CARO löst sie beim Öffnen der Maske auf. Eine Zeile ist vorgegeben, weitere fügt man mit „+ Gruppe hinzufügen“ an; leer lassen = keine Vorbelegung
- **Vorgesetzter:** sAMAccountName eintragen, CARO löst ihn beim Öffnen der Maske auf und trägt ihn vor. Leer lassen = Auswahl im CARO-Dialog über die Suche
    - existiert der Name im AD nicht, meldet CARO vermutlich einen Fehler (nicht getestet)
- **abgewählte Abschnitte** (z. B. „Adresse“, „Erweiterte Attribute“) werden beim Speichern samt zugehöriger Einträge aus dem Template entfernt und erscheinen in CARO nicht mehr
- einzeln abgewählte Felder bleiben im Template, sind aber in CARO unsichtbar
- rechts zeigt die Vorschau, was gespeichert wird

### Speichern

- speichern sie oben rechts über **JSON speichern**
    - die Datei wird standardmäßig im Download-Ordner des Nutzers abgelegt
    - der Dateiname entspricht der Template-ID
- verschieben oder kopieren sie die neu erstellte JSON Datei an folgende Stelle

`C:\ProgramData\CUSATUM Service GmbH\CARO\tools\manage`

- nicht vorhandene Unterordner müssen manuell erstellt werden
- beachten sie den Unterschied der Pfade:
    - Quelle: `Programme` bzw. `Program Files`
    - Ziel: `ProgramData`

### In CARO aktivieren

- öffnen sie den Task-Manager und starten den Service neu: `CARO-Suite Server`
- alternativ über PowerShell: `Restart-Service -Name 'CARO-Suite Server'`
- eventuell benötigt die Web-Anwendung im Browser anschließend eine Aktualisierung
- navigieren Sie zu
    - Ressourcenansicht > LIVE >

    und markieren die OU in der ein Nutzer angelegt werden soll (nicht auf den Namen klicken, nur auf die Zeile)
- im Menü-Band unter **Verwalten** erscheint der neue Eintrag
