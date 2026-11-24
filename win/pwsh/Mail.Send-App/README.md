# Mail.Send-App

## Zweck und Nutzung

PowerShell-Skript, das in Entra ID eine App-Registrierung einrichtet, mit der eine Anwendung über Microsoft 365 E-Mails senden kann (SMTP mit OAuth 2, ohne Anmeldefenster). Es liefert Mandanten-ID, Client-ID, Client-Secret, Postfach und Absender.

Nicht gedacht zum Lesen von Postfächern, für Microsoft Graph, für lokales Exchange oder für Massenversand.

## Haftungsausschluss

Das Skript ist eine freiwillige Zusatzarbeit und kein Produktbestandteil. Es wird ohne Support, Pflege und Gewährleistung bereitgestellt. Die Nutzung erfolgt auf eigenes Risiko. Die Prüfung von Code und Ergebnissen obliegt dem Anwender.

**Teststatus:** Anlegen und SMTP-Anmeldung liefen in einem echten Mandanten. Der Versand der Testmail ist noch nicht bestätigt, das Abbrechen und der Menüpunkt Prüfen sind noch ungetestet. Zuerst mit einem 3-Tage-Secret testen.

## Voraussetzungen

| Was | Hinweis |
|---|---|
| PowerShell 7 unter Windows | `winget install Microsoft.PowerShell` |
| Module `Microsoft.Graph.Authentication`, `ExchangeOnlineManagement` | das Skript bietet die Installation an |
| Globaler Administrator | zwei Anmeldungen: Entra ID und Exchange Online |
| Postfach in Exchange Online | Benutzer oder freigegeben |
| Security Defaults aus | sonst ist SMTP AUTH laut Microsoft abgeschaltet. Das Skript warnt nur und ändert nichts |

Beim Anmelden verlangt das Skript drei Rechte: Apps verwalten, Administratorzustimmung erteilen und Richtlinien lesen (für den Hinweis zu Security Defaults).

## Benutzung

```powershell
Unblock-File .\Mail.Send-App.ps1
pwsh -ExecutionPolicy Bypass -File .\Mail.Send-App.ps1
```

In allen Punkten bricht `x` ab und führt zurück ins Menü.

| Menü | Wirkung |
|---|---|
| 1 Anlegen | Postfach aus Liste wählen (mit Art und SMTP AUTH), Absender (Vorgabe: dasselbe Postfach), Laufzeit. Danach Übersicht, Rückfrage, Einrichtung |
| 2 Testmail | vorhandene Werte prüfen, ohne Admin-Anmeldung |
| 3 Secret erneuern | App wählen, neues Secret ausstellen, alte auf Wunsch löschen |
| 4 Prüfen | zeigt Secret, Zustimmung, Exchange-Rechte, SMTP AUTH und Security Defaults einer App mit kurzem Fazit. Fehlende Zustimmung, Exchange-Rechte, Einträge und SMTP AUTH behebt es nach einzelner Rückfrage. Nicht verändert werden Security Defaults, falsche Objekt-IDs, deaktivierte Anwendungen und ausdrückliche Verweigerungen |

**Laufzeit des Secrets:** 3 Tage (Test), 6, 12 oder 24 Monate. Ab 6 Monaten auf Wunsch eine Kalenderdatei (`.ics`) mit Erinnerung 30 Tage vor Ablauf. Sie enthält kein Secret.

**Vom Test in den Betrieb:** Menü 3, langes Secret ausstellen, in der Anwendung nur das Client-Secret tauschen, danach das Test-Secret löschen.

## Ergebnis

| Feld der Anwendung | Wert |
|---|---|
| Server | `smtp.office365.com`, Port 587, STARTTLS, OAuth 2 |
| Mandanten-ID, Client-ID, Client-Secret | werden angezeigt |
| Postfach, Absender | das gewählte Postfach |

Das Secret wird einmal angezeigt und nicht gespeichert. Kein PowerShell-Transkript mitlaufen lassen.

**Was eingerichtet wird:** Anwendungsrecht `SMTP.SendAsApp` mit Zustimmung, Anmeldung der App in Exchange, Vollzugriff auf das gewählte Postfach, bei anderem Absender „Senden als“, SMTP AUTH ausdrücklich am Postfach. Lesen kann die App nicht, dafür fehlen ihr die Rechte.

## Wenn es nicht klappt

| Meldung | Mögliche Ursache |
|---|---|
| `AADSTS7000215` / `AADSTS7000222` | Secret falsch / abgelaufen |
| `430 4.2.0 … MapiExceptionLogonFailed` | Vollzugriff fehlt oder ist noch nicht wirksam (Vermutung): Menü 4, sonst warten |
| `535 5.7.3` | Rechte noch nicht wirksam (warten), Postfach falsch |
| `5.7.139` | SMTP AUTH aus, Security Defaults oder Authentifizierungsrichtlinie |
| `5.7.60 SendAsDenied` | Bei abweichendem Absender: Menü 4. Ist der Absender das Postfach selbst: `Add-RecipientPermission -Identity <Absender> -Trustee <Objekt-ID der Unternehmensanwendung> -AccessRights SendAs` |
| Exchange-Anmeldung bricht ab | PowerShell neu starten, erneut versuchen |

## Grenzen

- Ein Postfach pro App. Dass freigegebene Postfächer ohne Lizenz senden können, ist angenommen und muss der Test zeigen.
- Nach Ablauf des Secrets wird nicht mehr gesendet. Das Skript überwacht das nicht.
- „Secret erneuern“ und „Prüfen“ zeigen nur Apps, die mit diesem Skript angelegt wurden.
- Rückbau von Hand: App-Registrierung in Entra löschen, in Exchange die Rechte der App am Postfach und den Eintrag (`Remove-ServicePrincipal`) entfernen.

## Fremdkomponenten

Keine enthalten. Die beiden Microsoft-Module werden bei Bedarf aus der PowerShell Gallery installiert.

## Lizenz

MIT, © 2026 Connectware Distributions GmbH, siehe `LICENSE`.
