#Requires -Version 7.0
<#
.SYNOPSIS
    Mail.Send-App - richtet in Entra ID eine App-Registrierung ein, die nur E-Mails senden kann (SMTP mit OAuth 2).

.DESCRIPTION
    Menü: 1 Anlegen, 2 Testmail, 3 Secret erneuern. Vor jeder Änderung zeigt das Skript eine Übersicht und fragt nach.
    Das Client-Secret erscheint nur auf dem Bildschirm und wird nicht gespeichert.
    Details: README.md

.NOTES
    Copyright (c) 2026 Connectware Distributions GmbH - MIT-Lizenz - ohne Gewährleistung, ohne Support.
    Nutzung auf eigenes Risiko. Es sind keine Fremdkomponenten enthalten.
    Benötigte Microsoft-Module: Microsoft.Graph.Authentication, ExchangeOnlineManagement
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$script:SmtpHost     = 'smtp.office365.com'
$script:SmtpPort     = 587
$script:ExchangeApp  = '00000002-0000-0ff1-ce00-000000000000'   # Office 365 Exchange Online
$script:RoleName     = 'SMTP.SendAsApp'
$script:AppTag       = 'MailSendAppSkript'                      # daran erkennt "Secret erneuern" die Apps
$script:GraphScopes  = @('Application.ReadWrite.All', 'AppRoleAssignment.ReadWrite.All', 'Policy.Read.All')
$script:Connected    = $false

#region Eingaben ---------------------------------------------------------------

function Read-YesNo {
    param([string]$Question, [bool]$Default = $false)
    $hint = if ($Default) { '(J/n)' } else { '(j/N)' }
    while ($true) {
        $answer = "$(Read-Host "$Question $hint")".Trim().ToLowerInvariant()
        if ($answer -eq '') { return $Default }
        if ($answer -in 'j', 'ja') { return $true }
        if ($answer -in 'n', 'nein') { return $false }
        Write-Host 'Bitte j oder n eingeben.' -ForegroundColor Yellow
    }
}

function Read-Number {
    param([string]$Question, [int]$Min, [int]$Max, [int]$Default = -1)
    while ($true) {
        $text = "$(Read-Host $Question)".Trim()
        if ($text -eq '' -and $Default -ge 0) { return $Default }
        $number = 0
        if ([int]::TryParse($text, [ref]$number) -and $number -ge $Min -and $number -le $Max) { return $number }
        Write-Host "Bitte eine Zahl von $Min bis $Max eingeben." -ForegroundColor Yellow
    }
}

function Test-Address {
    param([string]$Address)
    # Bewusst streng: keine Leer- oder Steuerzeichen, keine spitzen Klammern
    return $Address -match '\A[^\s<>@,;:"\\]+@[^\s<>@,;:"\\]+\.[^\s<>@,;:"\\]+\z'
}

function Read-Address {
    param([string]$Question, [string]$Default)
    $label = if ($Default) { "$Question [$Default]" } else { $Question }
    while ($true) {
        $text = "$(Read-Host $label)".Trim()
        if ($text -eq '' -and $Default) { return $Default }
        if (Test-Address $text) { return $text }
        Write-Host 'Das ist keine gültige E-Mail-Adresse.' -ForegroundColor Yellow
    }
}

function Read-Guid {
    param([string]$Question)
    while ($true) {
        $text = "$(Read-Host $Question)".Trim()
        $guid = [guid]::Empty
        if ([guid]::TryParse($text, [ref]$guid)) { return $guid.ToString() }
        Write-Host 'Das ist keine gültige ID.' -ForegroundColor Yellow
    }
}

function Read-SecretDuration {
    Write-Host ''
    Write-Host 'Wie lange soll das Client-Secret gelten? Danach kann die Anwendung nicht mehr senden.'
    Write-Host '  1  3 Tage     nur zum Testen'
    Write-Host '  2  6 Monate'
    Write-Host '  3  12 Monate'
    Write-Host '  4  24 Monate  Vorschlag, z. B. für Alarme'
    $choice = Read-Number -Question 'Auswahl [4]' -Min 1 -Max 4 -Default 4
    return Get-SecretDuration -Choice $choice
}

function Get-SecretDuration {
    param([int]$Choice, [datetime]$Now = [datetime]::UtcNow)
    switch ($Choice) {
        1 { [pscustomobject]@{ Label = '3 Tage (Test)'; End = $Now.AddDays(3);    IsTest = $true } }
        2 { [pscustomobject]@{ Label = '6 Monate';      End = $Now.AddMonths(6);  IsTest = $false } }
        3 { [pscustomobject]@{ Label = '12 Monate';     End = $Now.AddMonths(12); IsTest = $false } }
        4 { [pscustomobject]@{ Label = '24 Monate';     End = $Now.AddMonths(24); IsTest = $false } }
    }
}

#endregion

#region Verbindung -------------------------------------------------------------

function Assert-Modules {
    $missing = @('Microsoft.Graph.Authentication', 'ExchangeOnlineManagement' |
        Where-Object { -not (Get-Module -ListAvailable -Name $_) })
    if ($missing.Count -eq 0) { return }
    Write-Host "Es fehlen PowerShell-Module: $($missing -join ', ')" -ForegroundColor Yellow
    if (-not (Read-YesNo 'Jetzt für den aktuellen Benutzer aus der PowerShell Gallery installieren?')) {
        throw 'Ohne diese Module geht es nicht weiter.'
    }
    foreach ($name in $missing) { Install-Module -Name $name -Scope CurrentUser -Force -AllowClobber }
}

function Connect-Services {
    if ($script:Connected) { return }
    Assert-Modules
    Write-Host ''
    Write-Host 'Es folgen zwei Anmeldungen (Entra ID und Exchange Online). Beide mit demselben Admin-Konto durchführen.'
    Connect-MgGraph -Scopes $script:GraphScopes -ContextScope Process -NoWelcome
    $context = Get-MgContext
    if (-not $context) { throw 'Die Anmeldung an Entra ID ist fehlgeschlagen.' }
    try {
        Connect-ExchangeOnline -ShowBanner:$false
    } catch {
        # Graph und Exchange vertragen sich bei der Windows-Anmeldung nicht immer
        if (-not (Get-Command Connect-ExchangeOnline).Parameters.ContainsKey('DisableWAM')) { throw }
        Write-Host 'Exchange-Anmeldung fehlgeschlagen, neuer Versuch über den Browser.' -ForegroundColor Yellow
        Connect-ExchangeOnline -ShowBanner:$false -DisableWAM
    }
    # Nur die zuletzt aufgebaute Verbindung zählt; in der Sitzung können ältere offen sein
    $exchange = Get-ConnectionInformation | Where-Object { $_.State -eq 'Connected' } | Select-Object -Last 1
    if ("$($exchange.TenantID)" -ne "$($context.TenantId)") {
        throw "Verschiedene Mandanten: Entra ID '$($context.TenantId)', Exchange '$($exchange.TenantID)'. Es wurde nichts geändert."
    }
    $script:TenantId = "$($context.TenantId)"
    $script:Connected = $true
    Write-Host "Angemeldet als $($context.Account), Mandant $($script:TenantId)" -ForegroundColor Green
}

function Disconnect-Services {
    if (Get-Command Disconnect-ExchangeOnline -ErrorAction Ignore) {
        try { Disconnect-ExchangeOnline -Confirm:$false | Out-Null } catch { Write-Verbose $_ }
    }
    if (Get-Command Disconnect-MgGraph -ErrorAction Ignore) {
        try { Disconnect-MgGraph | Out-Null } catch { Write-Verbose $_ }
    }
    $script:Connected = $false
}

function Invoke-Graph {
    param([string]$Method = 'GET', [string]$Path, $Body)
    $request = @{ Method = $Method; Uri = "https://graph.microsoft.com/v1.0/$Path"; OutputType = 'PSObject' }
    if ($null -ne $Body) {
        $request.Body = $Body | ConvertTo-Json -Depth 8
        $request.ContentType = 'application/json'
    }
    try { Invoke-MgGraphRequest @request } catch {
        $detail = "$($_.ErrorDetails.Message)"
        if (-not $detail) { $detail = $_.Exception.Message }
        throw "Entra ID meldet: $detail"
    }
}

function Invoke-WithRetry {
    # Neue Objekte sind bei Microsoft nicht sofort überall bekannt, daher mehrere Versuche
    param([scriptblock]$Action, [string]$What, [int]$Tries = 8, [int]$WaitSeconds = 10)
    for ($i = 1; $i -le $Tries; $i++) {
        try { return & $Action } catch {
            if ($i -eq $Tries) { throw }
            Write-Host "   $What noch nicht möglich, Versuch $i von $Tries ..." -ForegroundColor DarkGray
            Start-Sleep -Seconds $WaitSeconds
        }
    }
}

#endregion

#region Postfächer -------------------------------------------------------------

function Get-KindLabel {
    param([string]$Type)
    switch ($Type) {
        'UserMailbox'   { 'Benutzer' }
        'SharedMailbox' { 'Freigegeben' }
        default         { $Type }
    }
}

function Get-SmtpAuthLabel {
    # Wert am Postfach hat Vorrang; leer = Vorgabe des Mandanten
    param($MailboxValue, $TenantValue)
    if ($null -ne $MailboxValue -and "$MailboxValue" -ne '') {
        if ([bool]$MailboxValue) { return 'aus' } else { return 'an' }
    }
    if ([bool]$TenantValue) { return 'aus (Mandant)' } else { return 'an (Mandant)' }
}

function Get-MailboxList {
    Write-Host 'Postfächer werden geladen ...'
    $tenant = (Get-TransportConfig).SmtpClientAuthenticationDisabled
    $cas = @{}
    $casLoaded = $false
    try {
        Get-EXOCasMailbox -ResultSize Unlimited -Properties PrimarySmtpAddress, SmtpClientAuthenticationDisabled | ForEach-Object {
            $cas["$($_.PrimarySmtpAddress)".ToLowerInvariant()] = $_.SmtpClientAuthenticationDisabled
        }
        $casLoaded = $true
    } catch { Write-Verbose "SMTP-AUTH-Status nicht lesbar: $_" }
    Get-EXOMailbox -ResultSize Unlimited -RecipientTypeDetails UserMailbox, SharedMailbox | ForEach-Object {
        $address = "$($_.PrimarySmtpAddress)"
        $key = $address.ToLowerInvariant()
        $label = if ($casLoaded -and $cas.ContainsKey($key)) { Get-SmtpAuthLabel $cas[$key] $tenant } else { '?' }
        [pscustomobject]@{
            Name = "$($_.DisplayName)"; Address = $address
            Kind = Get-KindLabel $_.RecipientTypeDetails; SmtpAuth = $label
        }
    } | Sort-Object Name, Address
}

function Select-Mailbox {
    param([object[]]$Mailboxes, [string]$Title)
    $shown = $Mailboxes
    while ($true) {
        Write-Host ''
        Write-Host $Title -ForegroundColor Cyan
        if ($shown.Count -eq 0) {
            Write-Host 'Kein Treffer.' -ForegroundColor Yellow
        } else {
            $page = @($shown | Select-Object -First 40)
            $n = 0
            $page | ForEach-Object {
                $n++
                [pscustomobject]@{ Nr = $n; Name = $_.Name; Adresse = $_.Address; Art = $_.Kind; 'SMTP AUTH' = $_.SmtpAuth }
            } | Format-Table -AutoSize | Out-Host
            if ($shown.Count -gt 40) { Write-Host "$($shown.Count) Treffer, die ersten 40 werden angezeigt. Suchtext eingeben, um einzugrenzen." }
        }
        $text = "$(Read-Host 'Nummer wählen oder Suchtext eingeben (* = alle)')".Trim()
        if ($text -eq '') { continue }
        if ($text -eq '*') { $shown = $Mailboxes; continue }
        $number = 0
        if ([int]::TryParse($text, [ref]$number) -and $number -ge 1 -and $number -le [Math]::Min(40, $shown.Count)) {
            return @($shown)[$number - 1]
        }
        $shown = @($Mailboxes | Where-Object {
            $_.Name.Contains($text, [StringComparison]::OrdinalIgnoreCase) -or
            $_.Address.Contains($text, [StringComparison]::OrdinalIgnoreCase)
        })
    }
}

#endregion

#region SMTP -------------------------------------------------------------------

function Get-XOAuth2String {
    param([string]$User, [string]$Token)
    $a = [char]1
    [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("user=$User${a}auth=Bearer $Token$a$a"))
}

function Read-SmtpReply {
    param([IO.StreamReader]$Reader)
    $lines = @()
    do {
        $line = $Reader.ReadLine()
        if ($null -eq $line) { throw 'Der Mailserver hat die Verbindung beendet.' }
        $lines += $line
    } while ($line.Length -gt 3 -and $line[3] -eq '-')
    [pscustomobject]@{ Code = $line.Substring(0, [Math]::Min(3, $line.Length)); Text = $lines -join ' | ' }
}

function Send-SmtpCommand {
    param([IO.StreamReader]$Reader, [IO.StreamWriter]$Writer, [string]$Command, [string[]]$Expect, [string]$Step)
    $Writer.Write("$Command`r`n"); $Writer.Flush()
    $reply = Read-SmtpReply $Reader
    if ($reply.Code -eq '334' -and '334' -notin $Expect) {
        # Fehlerdetails bei XOAUTH2 werden erst nach einer Leerzeile abgeschlossen
        $Writer.Write("`r`n"); $Writer.Flush()
        $reply = Read-SmtpReply $Reader
    }
    if ($reply.Code -notin $Expect) { throw "$Step abgelehnt: $($reply.Text)" }
    return $reply
}

function New-TestMessage {
    param([string]$From, [string]$To)
    $domain = $From.Split('@')[1]
    $date = [DateTimeOffset]::Now.ToString('ddd, dd MMM yyyy HH:mm:ss', [Globalization.CultureInfo]::InvariantCulture)
    $zone = [DateTimeOffset]::Now.ToString('zzz').Replace(':', '')
    @(
        "From: <$From>", "To: <$To>", 'Subject: Testmail Mail.Send-App', "Date: $date $zone"
        "Message-ID: <$([guid]::NewGuid())@$domain>", 'MIME-Version: 1.0'
        'Content-Type: text/plain; charset=us-ascii', ''
        'Diese Testmail wurde per SMTP mit OAuth 2 gesendet. Die Einrichtung funktioniert.'
    ) -join "`r`n"
}

function Get-SmtpToken {
    param([string]$TenantId, [string]$ClientId, [string]$Secret)
    try {
        $answer = Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" -Body @{
            client_id = $ClientId; client_secret = $Secret
            scope = 'https://outlook.office365.com/.default'; grant_type = 'client_credentials'
        }
        return $answer.access_token
    } catch {
        $detail = "$($_.ErrorDetails.Message)"
        if (-not $detail) { $detail = $_.Exception.Message }
        throw "Anmeldung der App bei Entra ID fehlgeschlagen: $detail"
    }
}

function Send-TestMail {
    param([string]$TenantId, [string]$ClientId, [string]$Secret, [string]$Mailbox, [string]$Sender, [string]$Recipient)
    $token = Get-SmtpToken -TenantId $TenantId -ClientId $ClientId -Secret $Secret
    Write-Host '   Anmeldung bei Entra ID: in Ordnung'
    $client = [Net.Sockets.TcpClient]::new()
    $ssl = $null
    try {
        if (-not $client.ConnectAsync($script:SmtpHost, $script:SmtpPort).Wait(15000)) {
            throw "Keine Verbindung zu $($script:SmtpHost):$($script:SmtpPort) (Firewall?)"
        }
        $client.ReceiveTimeout = 60000
        $client.SendTimeout = 60000
        $stream = $client.GetStream()
        $reader = [IO.StreamReader]::new($stream, [Text.Encoding]::ASCII)
        $writer = [IO.StreamWriter]::new($stream, [Text.ASCIIEncoding]::new())
        $hello = Read-SmtpReply $reader
        if ($hello.Code -ne '220') { throw "Mailserver nicht bereit: $($hello.Text)" }
        $null = Send-SmtpCommand $reader $writer 'EHLO mailsendapp' @('250') 'Begrüßung'
        $null = Send-SmtpCommand $reader $writer 'STARTTLS' @('220') 'STARTTLS'
        $ssl = [Net.Security.SslStream]::new($stream, $false)
        $ssl.AuthenticateAsClient($script:SmtpHost)
        $reader = [IO.StreamReader]::new($ssl, [Text.Encoding]::ASCII)
        $writer = [IO.StreamWriter]::new($ssl, [Text.ASCIIEncoding]::new())
        $null = Send-SmtpCommand $reader $writer 'EHLO mailsendapp' @('250') 'Begrüßung'
        $null = Send-SmtpCommand $reader $writer 'AUTH XOAUTH2' @('334') 'SMTP-Anmeldung'
        $null = Send-SmtpCommand $reader $writer (Get-XOAuth2String $Mailbox $token) @('235') 'SMTP-Anmeldung'
        Write-Host '   Anmeldung am Mailserver: in Ordnung'
        $null = Send-SmtpCommand $reader $writer "MAIL FROM:<$Sender>" @('250') 'Absender'
        $null = Send-SmtpCommand $reader $writer "RCPT TO:<$Recipient>" @('250', '251') 'Empfänger'
        $null = Send-SmtpCommand $reader $writer 'DATA' @('354') 'Nachricht'
        $null = Send-SmtpCommand $reader $writer "$(New-TestMessage $Sender $Recipient)`r`n." @('250') 'Versand'
        try { $writer.Write("QUIT`r`n"); $writer.Flush() } catch { Write-Verbose $_ }
        Write-Host "   Testmail an $Recipient vom Server angenommen." -ForegroundColor Green
    } finally {
        if ($ssl) { $ssl.Dispose() }
        $client.Dispose()
    }
}

function Invoke-TestMailDialog {
    param([string]$TenantId, [string]$ClientId, [string]$Secret, [string]$Mailbox, [string]$Sender)
    $recipient = Read-Address 'Empfänger der Testmail'
    while ($true) {
        try {
            Send-TestMail -TenantId $TenantId -ClientId $ClientId -Secret $Secret -Mailbox $Mailbox -Sender $Sender -Recipient $recipient
            return
        } catch {
            Write-Host "   $($_.Exception.Message)" -ForegroundColor Red
            Write-Host '   Direkt nach der Einrichtung ist das normal: Änderungen greifen teils erst nach einiger Zeit.'
            if (-not (Read-YesNo 'Noch einmal versuchen?')) { return }
        }
    }
}

#endregion

#region Ausgabe und Erinnerung -------------------------------------------------

function Show-Values {
    param([string]$ClientId, [string]$Secret, [string]$Mailbox, [string]$Sender, [datetime]$End)
    Write-Host ''
    Write-Host 'Werte für die Anwendung' -ForegroundColor Cyan
    Write-Host "  Server          $($script:SmtpHost), Port $($script:SmtpPort), STARTTLS, OAuth 2"
    Write-Host "  Mandanten-ID    $($script:TenantId)"
    Write-Host "  Client-ID       $ClientId"
    Write-Host "  Client-Secret   $Secret" -ForegroundColor Yellow
    Write-Host "  Postfach        $Mailbox"
    Write-Host "  Absender        $Sender"
    Write-Host "  Secret gültig bis $($End.ToLocalTime().ToString('dd.MM.yyyy HH:mm'))"
    Write-Host ''
    Write-Host 'Das Secret wird nur jetzt angezeigt und nicht gespeichert. Bitte sicher ablegen.' -ForegroundColor Yellow
}

function ConvertTo-IcsLine {
    # Kalenderdateien erlauben höchstens 75 Byte je Zeile
    param([string]$Line)
    $out = [Text.StringBuilder]::new()
    $bytes = 0
    foreach ($rune in $Line.EnumerateRunes()) {
        if ($bytes + $rune.Utf8SequenceLength -gt 73) { $null = $out.Append("`r`n "); $bytes = 1 }
        $null = $out.Append($rune.ToString())
        $bytes += $rune.Utf8SequenceLength
    }
    $out.ToString()
}

function New-ReminderText {
    param([string]$AppName, [string]$ClientId, [string]$Mailbox, [datetime]$End)
    $escape = { param($t) $t.Replace('\', '\\').Replace(';', '\;').Replace(',', '\,').Replace("`n", '\n') }
    $localEnd = $End.ToLocalTime()
    $day = $localEnd.Date.AddDays(-30)
    $text = "Das Client-Secret läuft am $($localEnd.ToString('dd.MM.yyyy')) ab. Danach sendet die Anwendung nicht mehr.`n" +
        "App: $AppName`nClient-ID: $ClientId`nPostfach: $Mailbox`nErneuern mit Mail.Send-App.ps1, Punkt 3 (Secret erneuern)."
    $lines = @(
        'BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//Connectware Distributions GmbH//Mail.Send-App//DE', 'BEGIN:VEVENT'
        "UID:$([guid]::NewGuid())@mail.send-app"
        "DTSTAMP:$([datetime]::UtcNow.ToString('yyyyMMddTHHmmssZ'))"
        "DTSTART;VALUE=DATE:$($day.ToString('yyyyMMdd'))"
        "DTEND;VALUE=DATE:$($day.AddDays(1).ToString('yyyyMMdd'))"
        "SUMMARY:$(& $escape "Client-Secret erneuern: $AppName")"
        "DESCRIPTION:$(& $escape $text)"
        'END:VEVENT', 'END:VCALENDAR'
    )
    (($lines | ForEach-Object { ConvertTo-IcsLine $_ }) -join "`r`n") + "`r`n"
}

function Invoke-ReminderDialog {
    param([string]$AppName, [string]$ClientId, [string]$Mailbox, $Duration)
    if ($Duration.IsTest) { return }
    if (-not (Read-YesNo 'Erinnerung als Kalenderdatei speichern (30 Tage vor Ablauf)?')) { return }
    try {
        $folder = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
        $safe = $AppName -replace '[^\w.\-]', '_'
        $path = Join-Path $folder "Secret-Ablauf_${safe}_$($Duration.End.ToLocalTime().ToString('yyyy-MM-dd')).ics"
        $text = New-ReminderText -AppName $AppName -ClientId $ClientId -Mailbox $Mailbox -End $Duration.End
        [IO.File]::WriteAllText($path, $text, [Text.UTF8Encoding]::new($false))
        Write-Host "Gespeichert: $path" -ForegroundColor Green
    } catch {
        Write-Host "Kalenderdatei konnte nicht gespeichert werden: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function New-Secret {
    param([string]$ObjectId, $Duration)
    try {
        Invoke-Graph -Method POST -Path "applications/$ObjectId/addPassword" -Body @{
            passwordCredential = @{
                displayName = "Mail.Send-App $($Duration.Label)"
                endDateTime = $Duration.End.ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture)
            }
        }
    } catch {
        throw "Das Secret wurde nicht ausgestellt. Möglich ist eine Mandantenrichtlinie, die Secrets oder diese Laufzeit nicht erlaubt. $($_.Exception.Message)"
    }
}

#endregion

#region 1 Anlegen --------------------------------------------------------------

function Invoke-Create {
    Connect-Services

    while ($true) {
        $name = "$(Read-Host 'Name der App-Registrierung [Mail.Send-App]')".Trim()
        if (-not $name) { $name = 'Mail.Send-App' }
        $filter = [uri]::EscapeDataString("displayName eq '$($name.Replace("'", "''"))'")
        $found = @((Invoke-Graph -Path "applications?`$filter=$filter&`$select=id").value)
        if ($found.Count -eq 0) { break }
        Write-Host 'Eine App mit diesem Namen gibt es schon. Bitte anderen Namen wählen (neues Secret: Menüpunkt 3).' -ForegroundColor Yellow
    }

    $mailboxes = @(Get-MailboxList)
    if ($mailboxes.Count -eq 0) { throw 'Es wurden keine Postfächer gefunden.' }
    $mailbox = Select-Mailbox -Mailboxes $mailboxes -Title 'Über welches Postfach soll gesendet werden?'
    $sender = $mailbox
    if (-not (Read-YesNo "Absender ebenfalls $($mailbox.Address)?" $true)) {
        $sender = Select-Mailbox -Mailboxes $mailboxes -Title 'Welches Postfach soll als Absender erscheinen?'
    }
    $otherSender = $sender.Address -ne $mailbox.Address
    $duration = Read-SecretDuration

    $casBefore = (Get-CASMailbox -Identity $mailbox.Address).SmtpClientAuthenticationDisabled
    $tenantOff = (Get-TransportConfig).SmtpClientAuthenticationDisabled
    $enableSmtp = (Get-SmtpAuthLabel $casBefore $tenantOff) -like 'aus*'
    $securityDefaults = $null
    try { $securityDefaults = (Invoke-Graph -Path 'policies/identitySecurityDefaultsEnforcementPolicy').isEnabled } catch { Write-Verbose $_ }

    Write-Host ''
    Write-Host 'Das wird geändert' -ForegroundColor Cyan
    Write-Host "  Entra ID   App-Registrierung '$name' mit $($script:RoleName) und Administratorzustimmung"
    Write-Host "  Entra ID   Client-Secret, gültig $($duration.Label)"
    Write-Host '  Exchange   App bekannt machen'
    Write-Host "  Exchange   Vollzugriff der App auf $($mailbox.Address) ($($mailbox.Kind))"
    if ($otherSender) { Write-Host "  Exchange   'Senden als' der App für $($sender.Address) ($($sender.Kind))" }
    if ($enableSmtp) { Write-Host "  Exchange   SMTP AUTH einschalten für $($mailbox.Address)" }
    if ($securityDefaults) {
        Write-Host ''
        Write-Host 'Achtung: Im Mandanten sind die Sicherheitsstandards (Security Defaults) aktiv. Laut Microsoft ist SMTP AUTH' -ForegroundColor Yellow
        Write-Host 'damit abgeschaltet, der Versand kann scheitern. Das Skript ändert diese Einstellung nicht.' -ForegroundColor Yellow
    } elseif ($null -eq $securityDefaults) {
        Write-Host 'Hinweis: Ob Security Defaults aktiv sind, konnte nicht gelesen werden.' -ForegroundColor Yellow
    }
    Write-Host ''
    if (-not (Read-YesNo 'So ausführen?')) { Write-Host 'Abgebrochen, nichts geändert.'; return }

    $app = $null; $exoPrincipal = $null; $fullAccess = $false; $sendAs = $false; $smtpChanged = $false
    try {
        $exchange = Invoke-Graph -Path "servicePrincipals(appId='$($script:ExchangeApp)')?`$select=id,appRoles"
        $role = $exchange.appRoles | Where-Object { $_.value -eq $script:RoleName } | Select-Object -First 1
        if (-not $role) { throw "Das Recht $($script:RoleName) wurde im Mandanten nicht gefunden." }

        Write-Host '1/5 App-Registrierung ...'
        $app = Invoke-Graph -Method POST -Path 'applications' -Body @{
            displayName = $name; signInAudience = 'AzureADMyOrg'; tags = @($script:AppTag)
            notes = "Postfach=$($mailbox.Address);Absender=$($sender.Address)"
            requiredResourceAccess = @(@{
                resourceAppId = $script:ExchangeApp
                resourceAccess = @(@{ id = $role.id; type = 'Role' })
            })
        }
        $principal = Invoke-WithRetry -What 'Unternehmensanwendung' -Action {
            Invoke-Graph -Method POST -Path 'servicePrincipals' -Body @{ appId = $app.appId }
        }

        Write-Host '2/5 Administratorzustimmung ...'
        $null = Invoke-WithRetry -What 'Zustimmung' -Action {
            Invoke-Graph -Method POST -Path "servicePrincipals/$($principal.id)/appRoleAssignments" -Body @{
                principalId = $principal.id; resourceId = $exchange.id; appRoleId = $role.id
            }
        }

        Write-Host '3/5 App in Exchange bekannt machen ...'
        $exoPrincipal = Invoke-WithRetry -What 'Exchange' -Action {
            New-ServicePrincipal -AppId $app.appId -ObjectId $principal.id -DisplayName $name -ErrorAction Stop
        }

        Write-Host '4/5 Rechte am Postfach ...'
        $null = Invoke-WithRetry -What 'Vollzugriff' -Action {
            Add-MailboxPermission -Identity $mailbox.Address -User $exoPrincipal.Identity -AccessRights FullAccess -Confirm:$false -ErrorAction Stop
        }
        $fullAccess = $true
        if ($otherSender) {
            $null = Invoke-WithRetry -What 'Senden als' -Action {
                Add-RecipientPermission -Identity $sender.Address -Trustee $exoPrincipal.Identity -AccessRights SendAs -Confirm:$false -ErrorAction Stop
            }
            $sendAs = $true
        }
        if ($enableSmtp) {
            Set-CASMailbox -Identity $mailbox.Address -SmtpClientAuthenticationDisabled $false -ErrorAction Stop
            $smtpChanged = $true
        }

        Write-Host '5/5 Client-Secret ...'
        $secret = New-Secret -ObjectId $app.id -Duration $duration
    } catch {
        Write-Host "Fehler: $($_.Exception.Message)" -ForegroundColor Red
        if ($app -and (Read-YesNo 'Die Einrichtung ist unvollständig. Bereits Angelegtes wieder entfernen?' $true)) {
            $undo = @()
            if ($smtpChanged)  { $undo += @{ What = 'SMTP AUTH zurücksetzen'; Do = { Set-CASMailbox -Identity $mailbox.Address -SmtpClientAuthenticationDisabled $casBefore -ErrorAction Stop } } }
            if ($sendAs)       { $undo += @{ What = 'Senden als entfernen'; Do = { Remove-RecipientPermission -Identity $sender.Address -Trustee $exoPrincipal.Identity -AccessRights SendAs -Confirm:$false -ErrorAction Stop } } }
            if ($fullAccess)   { $undo += @{ What = 'Vollzugriff entfernen'; Do = { Remove-MailboxPermission -Identity $mailbox.Address -User $exoPrincipal.Identity -AccessRights FullAccess -Confirm:$false -ErrorAction Stop } } }
            if ($exoPrincipal) { $undo += @{ What = 'App aus Exchange entfernen'; Do = { Remove-ServicePrincipal -Identity $exoPrincipal.Identity -Confirm:$false -ErrorAction Stop } } }
            $undo += @{ What = 'App-Registrierung löschen'; Do = { Invoke-Graph -Method DELETE -Path "applications/$($app.id)" } }
            foreach ($step in $undo) {
                try { $null = & $step.Do; Write-Host "   $($step.What): erledigt" }
                catch { Write-Host "   $($step.What): nicht möglich, bitte von Hand ($($_.Exception.Message))" -ForegroundColor Red }
            }
        }
        return
    }

    Show-Values -ClientId $app.appId -Secret $secret.secretText -Mailbox $mailbox.Address -Sender $sender.Address -End $duration.End
    Invoke-ReminderDialog -AppName $name -ClientId $app.appId -Mailbox $mailbox.Address -Duration $duration
    if (Read-YesNo 'Jetzt eine Testmail senden?') {
        Invoke-TestMailDialog -TenantId $script:TenantId -ClientId $app.appId -Secret $secret.secretText -Mailbox $mailbox.Address -Sender $sender.Address
    }
}

#endregion

#region 2 Testmail -------------------------------------------------------------

function Invoke-Test {
    Write-Host 'Sendet eine Testmail mit genau den Werten der Anwendung. Eine Admin-Anmeldung ist nicht nötig.'
    $tenant = Read-Guid 'Mandanten-ID'
    $client = Read-Guid 'Client-ID'
    $secret = Read-Host 'Client-Secret' -MaskInput
    $mailbox = Read-Address 'Postfach'
    $sender = Read-Address 'Absender' $mailbox
    Invoke-TestMailDialog -TenantId $tenant -ClientId $client -Secret $secret.Trim() -Mailbox $mailbox -Sender $sender
}

#endregion

#region 3 Secret erneuern ------------------------------------------------------

function ConvertFrom-AppNotes {
    param([string]$Notes)
    $result = @{ Mailbox = '(siehe Anwendung)'; Sender = '(siehe Anwendung)' }
    if ($Notes -match 'Postfach=([^;\s]+)') { $result.Mailbox = $Matches[1] }
    if ($Notes -match 'Absender=([^;\s]+)') { $result.Sender = $Matches[1] }
    $result
}

function Show-Secrets {
    param([object[]]$Secrets)
    $n = 0
    foreach ($s in $Secrets) {
        $n++
        $end = ([datetime]$s.endDateTime).ToUniversalTime()
        $state = if ($end -lt [datetime]::UtcNow) { 'abgelaufen' } else { 'gültig' }
        Write-Host ("  {0}  {1}  beginnt mit {2}  bis {3:dd.MM.yyyy}  {4}" -f $n, $s.displayName, $s.hint, $end.ToLocalTime(), $state)
    }
}

function Remove-OldSecrets {
    param([string]$ObjectId, [object[]]$Secrets)
    $left = @($Secrets)
    while ($left.Count -gt 0) {
        Write-Host ''
        Write-Host 'Welches Secret soll gelöscht werden? Es ist danach sofort unbrauchbar.'
        Show-Secrets $left
        $n = Read-Number -Question 'Nummer (Enter = keins)' -Min 0 -Max $left.Count -Default 0
        if ($n -eq 0) { return }
        $target = $left[$n - 1]
        if (Read-YesNo "Wirklich löschen: '$($target.displayName)', beginnt mit $($target.hint)?") {
            $null = Invoke-Graph -Method POST -Path "applications/$ObjectId/removePassword" -Body @{ keyId = $target.keyId }
            Write-Host 'Gelöscht.' -ForegroundColor Green
            $left = @($left | Where-Object { $_.keyId -ne $target.keyId })
        }
    }
}

function Invoke-Renew {
    Connect-Services
    $filter = [uri]::EscapeDataString("tags/any(t:t eq '$($script:AppTag)')")
    $apps = @((Invoke-Graph -Path "applications?`$filter=$filter&`$select=id,appId,displayName,notes,passwordCredentials&`$top=100").value)
    if ($apps.Count -eq 0) { Write-Host 'Es gibt keine mit diesem Skript angelegte App.' -ForegroundColor Yellow; return }
    Write-Host ''
    for ($i = 0; $i -lt $apps.Count; $i++) {
        Write-Host "  $($i + 1)  $($apps[$i].displayName)  ($((ConvertFrom-AppNotes $apps[$i].notes).Mailbox))"
    }
    $app = $apps[(Read-Number -Question 'Welche App? Nummer' -Min 1 -Max $apps.Count) - 1]
    $info = ConvertFrom-AppNotes $app.notes
    $old = @($app.passwordCredentials | Where-Object { $_ })

    Write-Host ''
    Write-Host 'Vorhandene Secrets:'
    if ($old.Count) { Show-Secrets $old } else { Write-Host '  keine' }
    Write-Host ''
    Write-Host '  1  Neues Secret ausstellen'
    Write-Host '  2  Nur alte Secrets löschen'
    if ((Read-Number -Question 'Auswahl [1]' -Min 1 -Max 2 -Default 1) -eq 2) {
        Remove-OldSecrets -ObjectId $app.id -Secrets $old
        return
    }

    $duration = Read-SecretDuration
    if (-not (Read-YesNo "Neues Secret für '$($app.displayName)' ausstellen, gültig $($duration.Label)?")) { Write-Host 'Abgebrochen, nichts geändert.'; return }
    $secret = New-Secret -ObjectId $app.id -Duration $duration
    Show-Values -ClientId $app.appId -Secret $secret.secretText -Mailbox $info.Mailbox -Sender $info.Sender -End $duration.End
    Write-Host 'In der Anwendung nur das Client-Secret austauschen.'
    Invoke-ReminderDialog -AppName $app.displayName -ClientId $app.appId -Mailbox $info.Mailbox -Duration $duration
    if ((Test-Address $info.Mailbox) -and (Test-Address $info.Sender) -and (Read-YesNo 'Jetzt eine Testmail senden?')) {
        Invoke-TestMailDialog -TenantId $script:TenantId -ClientId $app.appId -Secret $secret.secretText -Mailbox $info.Mailbox -Sender $info.Sender
    }
    if ($old.Count -and (Read-YesNo 'Sendet die Anwendung bereits mit dem neuen Secret? Dann können alte gelöscht werden.')) {
        Remove-OldSecrets -ObjectId $app.id -Secrets $old
    }
}

#endregion

function Start-Menu {
    Write-Host ''
    Write-Host 'Mail.Send-App - App-Registrierung nur zum Senden von E-Mails' -ForegroundColor Cyan
    Write-Host '(c) 2026 Connectware Distributions GmbH - MIT-Lizenz - ohne Gewährleistung'
    try {
        while ($true) {
            Write-Host ''
            Write-Host '  1  Anlegen          App einrichten und Zugangsdaten anzeigen'
            Write-Host '  2  Testmail         vorhandene Zugangsdaten prüfen'
            Write-Host '  3  Secret erneuern  neues Secret ausstellen, alte löschen'
            Write-Host '  0  Beenden'
            $choice = Read-Number -Question 'Auswahl' -Min 0 -Max 3
            try {
                switch ($choice) {
                    0 { return }
                    1 { Invoke-Create }
                    2 { Invoke-Test }
                    3 { Invoke-Renew }
                }
            } catch {
                Write-Host "Fehler: $($_.Exception.Message)" -ForegroundColor Red
                if (-not $script:Connected) { Disconnect-Services }
            }
        }
    } finally {
        Disconnect-Services
    }
}

# Beim Einbinden mit ". .\Mail.Send-App.ps1" (Tests) startet das Menü nicht
if ($MyInvocation.InvocationName -ne '.') { Start-Menu }
