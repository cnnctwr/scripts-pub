
## Kurzanleitung zum Erstellen von eigenen Templates für die Nutzeranlage

**Inklusive Pflichtfeldern, Zuordnung zu bestehenden Gruppen und Vorgesetztem**

- legen sie die [CARO-UserTemplates.html](CARO-UserTemplates.html) in ein beliebiges Verzeichnis auf dem CARO-Server
- öffnen sie die HTML durch Doppelklick (empfohlen: Chrome oder Edge)
- klicken sie rechts oben auf **JSON laden**
- das JSON für die Standard-Nutzeranlage liegt hier:

`C:\Program Files\CUSATUM Service GmbH\CARO\server\tools\manage\cts.manage.nativeActiveDirectoryStandardUser.json`
- öffnen sie die angegebene Datei
    - ggf. vorab Kopien anlegen, der Builder ändert aber die Original-Datei nicht

### Muss geändert werden

- vergeben sie als erstes und unbedingt eine **neue, eindeutige Template-ID**
- vergeben sie ebenfalls aussagekräftige und eindeutige Namen für
    - Name (Deutsch/Englisch) – das ist der Menüpunkt in CARO
    - Beschreibung (Deutsch/Englisch)

    um die Einträge später im Menü klar unterscheiden zu können
- „JSON speichern“ wird orange und fragt nach, solange etwas offen ist

### Felder anpassen

- jedes Feld hat links einen Haken zum Ein- und Ausschalten, jeder Abschnitt oben ebenfalls
- **Pflicht:** bei jedem Feld lässt sich festlegen, ob es bei der Nutzeranlage in CARO ausgefüllt werden muss
    - fest vorgegeben (nicht änderbar): Vorname, Nachname, SamAccountName, UserPrincipalName, Allgemeiner Name, Kennwort, Änderungskommentar
- hinter jedem Feldnamen steht in Klammern der **AD-Attributname** (zum Beispiel `Büro (physicalDeliveryOfficeName)`), damit klar ist, welches Attribut gemeint ist
- **Vorname und Nachname** sind im Template nicht beschreibbar, sie werden erst in CARO eingegeben
- **Bildungsvorschrift:** SamAccountName, UserPrincipalName, Anzeigename und Allgemeiner Name werden in CARO automatisch aus Vor- und Nachname gebildet. Je Feld lässt sich eine von mehreren festen Vorschriften wählen (die oberste ist der Standard), zum Beispiel `Nachname, Vorname` oder `Vorname.Nachname`
- **Testmodus** (Knopf im Abschnitt „LDAP - notwendig“): Beispielnamen und Suffix eintippen, die Zeilen zeigen das Ergebnis jeder Vorschrift. Im Testmodus wird nichts gespeichert und das Speichern ist gesperrt. Er zeigt auch die Mailadresse, die sich laut den gewählten Vorschriften ergäbe (gelbe Zeile im Abschnitt „Allgemeines“, der dabei aufklappt)
- **UPN-Suffix:** CARO ermittelt ihn selbst (Domänenname aus den DC-Teilen der OU, z. B. `meine.firma.gmbh`). Ein eigener Wert im Feld ersetzt das
- **Mail:** keine Vorbelegung (Standard) oder die Adresse aus zwei unabhängig wählbaren Teilen zusammensetzen: **Namensteil** (wie UserPrincipalName, wie SamAccountName ohne Kürzung, oder offen, dann ergänzt der Nutzer den Namen in CARO und CARO lehnt die Eingabe ohne Namen ab) und **Domänenteil** (wie UPN-Suffix oder eine eigene Domäne). Die Adresse folgt den oben gewählten Varianten für UPN und SamAccountName. Bei „Namensteil offen“ muss der Nutzer in CARO zuerst die Automatik am Feld ausschalten, um den Namen vor dem @ zu ergänzen (bis dahin meldet CARO „Wert entspricht nicht dem Muster“). Wird die Adresse von einer externen Instanz gesetzt (zum Beispiel Exchange), das Feld abwählen
- **Ablaufdatum des Kontos:** drei Möglichkeiten: **läuft nie ab** (Standard), **nach N Tagen** (ab Anlage gerechnet, am Ablauftag um 23:59 Uhr) oder **festes Datum** mit Uhrzeit. CARO trägt das Datum beim Öffnen der Maske vor, der Nutzer kann es dort noch ändern. Die Uhrzeit gilt in der Ortszeit des Servers (im AD als UTC gespeichert, in CARO bestätigt). Fehleingaben (keine ganze Zahl, Datum in der Vergangenheit) sperren das Speichern
- **Gruppen:** sAMAccountNames der Gruppen eintragen, CARO löst sie beim Öffnen der Maske auf
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
