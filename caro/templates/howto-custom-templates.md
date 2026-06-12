
## Kurzanleitung zum Erstellen von eigenen Templates für die Nutzeranlage

**Inklusive der Zuordnung zu bestehenden Gruppen**

- legen sie die [json_builder_v2.html](https://github.com/cnnctwr/scripts-pub/blob/main/caro/templates/json_builder_v2.html) in ein beliebiges Verzeichnis auf dem CARO-Server 
- öffnen sie die HTML durch Doppleklick
- klicken sie rechts oben auf **JSON laden**
- das JSON für die Standard-Nutzeranalge liegt hier:

`C:\Program Files\CUSATUM Service GmbH\CARO\server\tools\manage\cts.manage.nativeActiveDirectoryStandardUser.json`
- öffnen sie die angegebene Datei
    - ggf. vorab Kopien anlegen, der Builder ändert aber die Original-Datei nicht
- vergeben Sie als erstes und unbedingt eine **neue, eindeutige Template-ID** 
- vergeben sie ebenfalls aussagekräftige und eindeutige Namen für
    - Name (Deutsch/Englisch)
    - Beschreibung (Deutsch/Englisch)
    
    um die Einträge später im Menü klar unterscheiden zu können
- füllen Sie nach ihren Vorgaben beliebige Felder aus
    - Hinweis: Felder die mit **Pflicht** markiert sind müssen nicht ausgefüllt werden im JSON Builder, es wird lediglich aus dem JSON ausgelsen und ist später bei der Nutzeranlage in CARO ein Pflichtfeld
- speichern sie oben recht über **JSON speichern**
    - die Datei wird im standardmäßig im Download-Ordner des Nutzers abgelegt
- Kopieren sie die neu erstelle JSON Datei an folgende Stelle

`C:\ProgramData\CUSATUM Service GmbH\CARO\tools\manage`

- nicht vorhandene Unterordner müssen manuell erstellt werden
- beachten sie den Unterschied der Pfade:
    - Quelle: `Programme` bzw. `Program Files`
    - Ziel: `ProgramData`

- öffnen sie den Task-Manager und starten den Service neu: `CARO-Suite Server` 
- alternativ über PowerShell: `Restart-Service -Name 'CARO-Suite Server'`
- eventuell benötigt die Web-Anwendung im Browser anschliessend eine Aktualisierung
- navigierne Sie zu
    - Ressourcenansicht > LIVE > 
    
    und markieren die OU in der ein Nutzer angelegt werden soll (nicht auf den Namen klicken, nur auf die Zeile)
- im Menü-Band unter **Verwalten** erscheint der neue Eintrag
