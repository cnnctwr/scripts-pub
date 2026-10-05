# CARO-ServiceAccount-Setup.ps1 - Einzeldatei-Fassung (nicht von Hand bearbeiten)
# Erzeugt aus src/ mit scripts/build_single_file.py. Der Hash dient nur der Aktualitaetspruefung.
# Quell-Hash: bbfb7fe9bf2c82d55c34433946ae4f55bdb809119738a48e60d139ec9e383585
<#
.SYNOPSIS
    Legt einen Service-Account fuer die CARO-Suite an und vergibt die dafuer noetigen Rechte.

.DESCRIPTION
    DIESES SKRIPT MUSS AUF DEM CARO-SERVER AUSGEFUEHRT WERDEN.

    Das Skript fuehrt interaktiv durch alle Entscheidungen und erklaert vorher, was jede Option bewirkt.
    Es arbeitet in drei Modi:

      Plan      Fragen stellen, Umgebung nur lesend pruefen, Config.json und Report.md erzeugen.
                Aendert nichts.
      Apply     Eine Config.json ausfuehren. Zeigt vorher eine Zusammenfassung und verlangt die
                ausdrueckliche Bestaetigung. Schreibt Result.json.
      Rollback  Baut zurueck, was ein frueherer Apply-Lauf NEU angelegt hat (nach Result.json).

    Alle Ausgaben (Log, Config, Result, Report) landen im Ordner
    "CARO-ServiceAccount-Setup-Logs" neben diesem Skript, unabhaengig vom aktuellen Arbeitsverzeichnis.
    Das Laufzeit-Log (<Zeitstempel>-CARO-SA-<Modus>.log) wird ab der ersten Zeile geschrieben.

    Weitergabe: Die Einzeldatei-Fassung (dist\CARO-ServiceAccount-Setup.ps1) braucht keine weiteren Dateien.
    Die Attributliste ist darin eingebettet. Eine Datei CARO-AD-Attributes.json hat Vorrang, zuerst die neben
    dem Skript, dann die im Ordner CARO-ServiceAccount-Setup-Logs. Dort legt das Skript auf Wunsch die Vorlage ab.

.PARAMETER Mode
    Plan, Apply oder Rollback. Ohne Angabe fragt das Skript nach dem Modus.

.PARAMETER ConfigPath
    Nur fuer Apply: Pfad der Config.json. Ohne Angabe wird eine der letzten Dateien zur Auswahl angeboten.

.PARAMETER ResultPath
    Nur fuer Rollback: Pfad der Result.json. Ohne Angabe wird eine der letzten Dateien zur Auswahl angeboten.

.PARAMETER WhatIf
    Zeigt bei Apply und Rollback alle Aktionen, ohne etwas zu aendern. Result.json bzw. Rollback.json
    werden trotzdem geschrieben und als WhatIf-Lauf markiert.

.EXAMPLE
    .\CARO-ServiceAccount-Setup.ps1
    Fragt nach dem Modus und fuehrt durch den Ablauf.

.EXAMPLE
    .\CARO-ServiceAccount-Setup.ps1 -Mode Plan

.EXAMPLE
    .\CARO-ServiceAccount-Setup.ps1 -Mode Apply -ConfigPath .\CARO-ServiceAccount-Setup-Logs\2026-10-05-120000-CARO-SA-Config.json -WhatIf

.EXAMPLE
    .\CARO-ServiceAccount-Setup.ps1 -Mode Rollback
#>
#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateSet('Plan', 'Apply', 'Rollback')]
    [string]$Mode,

    [string]$ConfigPath = '',

    [string]$ResultPath = ''
)

$ErrorActionPreference = 'Stop'
$script:CaroRoot = $PSScriptRoot
if (-not $script:CaroRoot) { $script:CaroRoot = (Get-Location).Path }

#region CARO-LIBS (in die Einzeldatei eingebettet, erzeugt von scripts/build_single_file.py)
# Eingebettete Attributliste (Vorlage fuer CARO-AD-Attributes.json)
$script:CaroEmbeddedAttributesJson = @'
{
  "Beschreibung": "Attributliste fuer die AD-Delegation 'Nur Attributliste (Property-specific)'. Diese Datei darf bearbeitet werden. Das Skript liest sie bei jedem Plan neu ein und zeigt die Liste vor der Vergabe an.",
  "Quelle": "examples/cts.manage.nativeActiveDirectoryStandardUser.json (CAROs eigene Aufgabe 'Create new user')",
  "Hinweis": "Das Kennwort wird nicht als Attribut geschrieben, sondern ueber das Recht 'Reset Password' gesetzt. Die Pflichtattribute unten werden vom Skript automatisch ergaenzt, wenn die zugehoerige CARO-Funktion gewaehlt wird.",
  "Attribute": [
    "givenName",
    "sn",
    "sAMAccountName",
    "userPrincipalName",
    "cn",
    "displayName",
    "company",
    "division",
    "department",
    "manager",
    "title",
    "homeDirectory",
    "homeDrive",
    "initials",
    "description",
    "physicalDeliveryOfficeName",
    "telephoneNumber",
    "info",
    "carLicense",
    "mail",
    "wWWHomePage",
    "employeeID",
    "employeeNumber",
    "streetAddress",
    "st",
    "postalCode",
    "l",
    "c",
    "co",
    "countryCode",
    "codePage",
    "extensionAttribute1",
    "extensionAttribute2",
    "extensionAttribute3",
    "extensionAttribute4",
    "extensionAttribute5",
    "extensionAttribute6",
    "extensionAttribute7",
    "extensionAttribute8",
    "extensionAttribute9",
    "extensionAttribute10",
    "extensionAttribute11",
    "extensionAttribute12",
    "extensionAttribute13",
    "extensionAttribute14",
    "extensionAttribute15"
  ],
  "Pflichtattribute": {
    "userAccountControl": "Konto aktivieren und deaktivieren",
    "lockoutTime": "Konto entsperren",
    "accountExpires": "Ablaufdatum des Kontos aendern",
    "pwdLastSet": "Kennwortaenderung bei naechster Anmeldung erzwingen"
  }
}
'@

# ===== 01-Logging.ps1 =====
# 01-Logging.ps1
# Protokollierung: Das Laufzeit-Log wird ab der ersten Zeile des Laufs geschrieben,
# auch bei Abbruch oder Fehler. Ausserdem: Pfade und Schreibfunktionen fuer alle Ausgabedateien.

$script:CaroLogPath = $null

# Ordner des Skripts (src). Wird vom Hauptskript gesetzt, damit die Ausgaben nie vom
# aktuellen Arbeitsverzeichnis abhaengen.
function Get-CaroRoot {
    if ($script:CaroRoot) { return $script:CaroRoot }
    return (Get-Location).Path
}

# Log-Verzeichnis neben dem Skript. Wird bei Bedarf angelegt.
function Get-CaroLogFolder {
    $folder = Join-Path (Get-CaroRoot) 'CARO-ServiceAccount-Setup-Logs'
    # .NET statt New-Item: -WhatIf darf das Anlegen des Log-Ordners nicht verhindern.
    if (-not (Test-Path -LiteralPath $folder)) {
        [void][System.IO.Directory]::CreateDirectory($folder)
    }
    return $folder
}

# Dateiname nach dem Schema <Zeitstempel>-CARO-SA-<Typ>.<Endung>
function New-CaroOutputPath {
    param(
        [Parameter(Mandatory = $true)][string]$Type,
        [Parameter(Mandatory = $true)][string]$Extension
    )
    # Gibt es die Datei in dieser Sekunde schon, wird der Zeitstempel um eine Sekunde erhoeht,
    # damit nie eine vorhandene Datei ueberschrieben wird.
    $folder = Get-CaroLogFolder
    $time = Get-Date
    while ($true) {
        $name = '{0}-CARO-SA-{1}.{2}' -f $time.ToString('yyyy-MM-dd-HHmmss'), $Type, $Extension
        $path = Join-Path $folder $name
        if (-not (Test-Path -LiteralPath $path)) { return $path }
        $time = $time.AddSeconds(1)
    }
}

# Textdatei als UTF-8 ohne BOM schreiben (einheitlich fuer JSON und Markdown).
function Write-CaroTextFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text
    )
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Text, $enc)
}

# Liest eine UTF-8-Textdatei vollstaendig.
function Read-CaroTextFile {
    param([Parameter(Mandatory = $true)][string]$Path)
    return [System.IO.File]::ReadAllText($Path, (New-Object System.Text.UTF8Encoding($false)))
}

# Legt die Log-Datei des Laufs an und schreibt die erste Zeile.
function Initialize-CaroLog {
    param([Parameter(Mandatory = $true)][string]$Mode)
    $script:CaroLogPath = New-CaroOutputPath -Type $Mode -Extension 'log'
    Write-CaroTextFile -Path $script:CaroLogPath -Text ''
    Write-CaroLog -Level 'INFO' -Message ('Lauf gestartet. Modus={0}, Rechner={1}, Benutzer={2}, PowerShell={3}' -f $Mode, [System.Environment]::MachineName, [System.Environment]::UserName, $PSVersionTable.PSVersion)
    return $script:CaroLogPath
}

# Eine Zeile ins Log schreiben: Zeit | Stufe | Meldung | Objekt | Ergebnis
function Write-CaroLog {
    param(
        [ValidateSet('INFO', 'WARN', 'ERROR', 'AKTION')][string]$Level = 'INFO',
        [Parameter(Mandatory = $true)][string]$Message,
        [string]$Object = '',
        [string]$Result = ''
    )
    if (-not $script:CaroLogPath) { return }
    try {
        $clean = $Message -replace '\r?\n', ' / '
        $line = '{0} | {1,-6} | {2} | {3} | {4}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff'), $Level, $clean, $Object, $Result
        $enc = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::AppendAllText($script:CaroLogPath, $line + [Environment]::NewLine, $enc)
    }
    catch {
        # Ein Log-Fehler darf den Lauf nicht beenden, wird aber einmalig sichtbar gemacht.
        Write-Host ('WARNUNG: Log konnte nicht geschrieben werden: ' + $_.Exception.Message) -ForegroundColor Yellow
        $script:CaroLogPath = $null
    }
}

# Meldung auf der Konsole ausgeben und gleichzeitig ins Log schreiben.
function Write-CaroMessage {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Message,
        [ValidateSet('INFO', 'OK', 'WARN', 'ERROR', 'TITLE')][string]$Level = 'INFO'
    )
    $color = switch ($Level) {
        'OK' { 'Green' }
        'WARN' { 'Yellow' }
        'ERROR' { 'Red' }
        'TITLE' { 'Cyan' }
        default { 'Gray' }
    }
    Write-Host $Message -ForegroundColor $color
    if ($Message.Trim().Length -gt 0) {
        $logLevel = switch ($Level) {
            'WARN' { 'WARN' }
            'ERROR' { 'ERROR' }
            default { 'INFO' }
        }
        Write-CaroLog -Level $logLevel -Message $Message
    }
}

# ===== 02-Ui.ps1 =====
# 02-Ui.ps1
# Interaktive Eingaben. Alle Funktionen fragen bei ungueltiger Eingabe erneut nach.
# Es wird nie stillschweigend auf einen Standardwert zurueckgefallen.

# Einzige Stelle, die Read-Host aufruft (Passwoerter ausgenommen). Die Antwort wird protokolliert.
function Read-CaroInput {
    param([Parameter(Mandatory = $true)][string]$Prompt)
    $answer = Read-Host -Prompt $Prompt
    if ($null -eq $answer) { $answer = '' }
    Write-CaroLog -Level 'INFO' -Message ('Eingabe: {0} => {1}' -f ($Prompt -replace '\r?\n', ' '), $answer)
    return $answer
}

# Auswahl aus nummerierten Optionen. Options: Objekte mit Key, Label, Explain (optional).
function Read-CaroChoice {
    param(
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][object[]]$Options,
        [string]$Default = ''
    )
    while ($true) {
        Write-Host ''
        Write-CaroMessage -Message $Title -Level 'TITLE'
        foreach ($o in $Options) {
            Write-Host ('  [{0}] {1}' -f $o.Key, $o.Label) -ForegroundColor White
            if ($o.Explain) {
                foreach ($line in ($o.Explain -split "`n")) {
                    Write-Host ('      ' + $line) -ForegroundColor Gray
                }
            }
        }
        $suffix = ''
        if ($Default) { $suffix = ' (Standard: {0})' -f $Default }
        $answer = (Read-CaroInput -Prompt ('Auswahl' + $suffix)).Trim()
        if (-not $answer -and $Default) { return $Default }
        foreach ($o in $Options) {
            if ($o.Key -ieq $answer) { return [string]$o.Key }
        }
        $valid = ($Options | ForEach-Object { $_.Key }) -join ', '
        Write-CaroMessage -Message ("Ungueltige Eingabe '{0}'. Bitte eine dieser Optionen waehlen: {1}" -f $answer, $valid) -Level 'WARN'
    }
}

# Ja/Nein-Frage. Akzeptiert j, ja, y, yes, n, nein.
function Read-CaroYesNo {
    param(
        [Parameter(Mandatory = $true)][string]$Prompt,
        [bool]$Default = $true
    )
    $hint = 'J/n'
    if (-not $Default) { $hint = 'j/N' }
    while ($true) {
        $answer = (Read-CaroInput -Prompt ('{0} [{1}]' -f $Prompt, $hint)).Trim().ToLowerInvariant()
        if (-not $answer) { return $Default }
        if ($answer -in @('j', 'ja', 'y', 'yes')) { return $true }
        if ($answer -in @('n', 'nein', 'no')) { return $false }
        Write-CaroMessage -Message "Bitte mit 'j' oder 'n' antworten." -Level 'WARN'
    }
}

# Freitext mit optionaler Pruefung. Der Validator liefert $null bei Erfolg, sonst einen Fehlertext.
function Read-CaroText {
    param(
        [Parameter(Mandatory = $true)][string]$Prompt,
        [string]$Default = '',
        [scriptblock]$Validator = $null,
        [switch]$AllowEmpty
    )
    while ($true) {
        $label = $Prompt
        if ($Default) { $label = '{0} [{1}]' -f $Prompt, $Default }
        $answer = (Read-CaroInput -Prompt $label).Trim()
        if (-not $answer -and $Default) { $answer = $Default }
        if (-not $answer) {
            if ($AllowEmpty) { return '' }
            Write-CaroMessage -Message 'Eine Eingabe ist erforderlich.' -Level 'WARN'
            continue
        }
        if ($Validator) {
            $err = & $Validator $answer
            if ($err) {
                Write-CaroMessage -Message ([string]$err) -Level 'WARN'
                continue
            }
        }
        return $answer
    }
}

# Ausdrueckliche Bestaetigung: Es muss genau das Wort eingegeben werden.
function Read-CaroConfirmWord {
    param(
        [Parameter(Mandatory = $true)][string]$Prompt,
        [string]$Word = 'JA'
    )
    $answer = (Read-CaroInput -Prompt ("{0} (zum Bestaetigen '{1}' eingeben)" -f $Prompt, $Word)).Trim()
    return ($answer -ceq $Word)
}

# SecureString in Klartext wandeln (nur kurzzeitig fuer Vergleich oder Anzeige verwenden).
function ConvertFrom-CaroSecureString {
    param([Parameter(Mandatory = $true)][System.Security.SecureString]$Secure)
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try { return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

# Kennwort zweimal verdeckt abfragen. Der Wert wird nie protokolliert.
function Read-CaroPasswordTwice {
    while ($true) {
        $p1 = Read-Host -Prompt 'Kennwort fuer den Service-Account' -AsSecureString
        $p2 = Read-Host -Prompt 'Kennwort wiederholen' -AsSecureString
        $plain1 = ConvertFrom-CaroSecureString -Secure $p1
        $plain2 = ConvertFrom-CaroSecureString -Secure $p2
        if ($plain1.Length -lt 8) {
            Write-CaroMessage -Message 'Das Kennwort ist zu kurz (mindestens 8 Zeichen, die AD-Richtlinie kann mehr verlangen).' -Level 'WARN'
            continue
        }
        if ($plain1 -cne $plain2) {
            Write-CaroMessage -Message 'Die beiden Eingaben stimmen nicht ueberein.' -Level 'WARN'
            continue
        }
        Write-CaroLog -Level 'INFO' -Message 'Kennwort manuell eingegeben (Wert wird nicht protokolliert).'
        return $p1
    }
}

# Zufallszahl 0..(Max-1) aus dem kryptografischen Zufallsgenerator.
function Get-CaroRandomInt {
    param([Parameter(Mandatory = $true)][int]$Max)
    $rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
    try {
        $bytes = New-Object byte[] 4
        $rng.GetBytes($bytes)
        return [int]([BitConverter]::ToUInt32($bytes, 0) % [uint32]$Max)
    }
    finally { $rng.Dispose() }
}

# Starkes Zufallskennwort: je mindestens ein Zeichen aus vier Klassen, ohne verwechselbare Zeichen.
function New-CaroPassword {
    param([int]$Length = 24)
    $sets = @(
        'ABCDEFGHJKLMNPQRSTUVWXYZ',
        'abcdefghijkmnopqrstuvwxyz',
        '23456789',
        '!#%&*+-=?@_'
    )
    $all = ($sets -join '')
    $chars = New-Object System.Collections.ArrayList
    foreach ($s in $sets) { [void]$chars.Add($s[(Get-CaroRandomInt -Max $s.Length)]) }
    while ($chars.Count -lt $Length) { [void]$chars.Add($all[(Get-CaroRandomInt -Max $all.Length)]) }
    for ($i = $chars.Count - 1; $i -gt 0; $i--) {
        $j = Get-CaroRandomInt -Max ($i + 1)
        $tmp = $chars[$i]; $chars[$i] = $chars[$j]; $chars[$j] = $tmp
    }
    return (-join $chars)
}

# Ueberschrift mit Trennlinie.
function Write-CaroHeading {
    param([Parameter(Mandatory = $true)][string]$Text)
    Write-Host ''
    Write-Host ('=' * 78) -ForegroundColor Cyan
    Write-CaroMessage -Message $Text -Level 'TITLE'
    Write-Host ('=' * 78) -ForegroundColor Cyan
}

# ===== 03-Catalog.ps1 =====
# 03-Catalog.ps1
# Katalog: AD-Rollen, CARO-Funktionen und die dafuer noetigen Rechte.
# Dies ist die EINZIGE Stelle, an der festgelegt wird, welche Funktion welche Rechte braucht.
# Wenn sich beim Test am Zielsystem herausstellt, dass Rechte angepasst werden muessen,
# wird nur diese Datei geaendert.
#
# Rechte-Bausteine ("Specs"):
#   ClassCreate    Objekte einer Klasse anlegen       (Create <Klasse> objects)
#   ClassDelete    Objekte einer Klasse loeschen       (Delete <Klasse> objects)
#   Props          Eigenschaften lesen/schreiben      (je nach Attribut-Strategie: alle oder Liste)
#   PropsAll       Alle Eigenschaften lesen/schreiben (Read/Write All Properties)
#   PropsList      Bestimmte Eigenschaften lesen/schreiben (Property-specific)
#   ExtendedRight  Erweitertes Recht, z. B. Reset Password

$script:CaroSid = @{
    Administrators  = 'S-1-5-32-544'
    BackupOperators = 'S-1-5-32-551'
    PrintOperators  = 'S-1-5-32-550'
}

# Exchange-Rollengruppen werden ueber ihren Namen angesprochen (keine festen SIDs).
$script:CaroExchangeRoleGroup = @{
    Management = 'Organization Management'
    ReadOnly   = 'View-Only Organization Management'
}

function New-CaroFunction {
    param(
        [string]$Key,
        [string]$Title,
        [string]$Explain,
        [object[]]$Specs
    )
    return [pscustomobject]@{ Key = $Key; Title = $Title; Explain = $Explain; Specs = @($Specs) }
}

# Die vier AD-Bereiche (intern "Rollen") mit ihren Funktionen.
function Get-CaroRoleCatalog {
    $roles = @()

    $roles += [pscustomobject]@{
        Key        = 'UserOU'
        Title      = 'Benutzerkonten'
        Purpose    = 'CARO legt Benutzerkonten an, loescht sie und aendert sie.'
        Ask        = 'Soll CARO Benutzerkonten in Active Directory verwalten duerfen (mit den oben genannten Rechten)?'
        Question   = 'In welcher OU (oder welchen OUs) liegen die Benutzerkonten, die CARO verwalten soll bzw. in denen neue Benutzer angelegt werden?'
        BaseSuffix = 'Benutzer'
        Functions  = @(
            (New-CaroFunction -Key 'CreateUser' -Title 'Benutzer anlegen' `
                -Explain 'CARO darf in dieser OU neue Benutzerkonten anlegen (Recht: Create User objects).' `
                -Specs @(@{ Kind = 'ClassCreate'; Class = 'user' })),
            (New-CaroFunction -Key 'DeleteUser' -Title 'Benutzer loeschen' `
                -Explain 'CARO darf Benutzerkonten in dieser OU loeschen (Recht: Delete User objects). Geloeschte Konten lassen sich nur mit Aufwand wiederherstellen.' `
                -Specs @(@{ Kind = 'ClassDelete'; Class = 'user' })),
            (New-CaroFunction -Key 'UserAttributes' -Title 'Benutzerattribute bearbeiten' `
                -Explain 'CARO darf Attribute von Benutzern aendern (Name, Telefon, Abteilung, Manager, Erweiterungsattribute u. a.). Der Umfang richtet sich nach Ihrer spaeteren Wahl: alle Eigenschaften oder nur die Attributliste.' `
                -Specs @(@{ Kind = 'Props'; Class = 'user'; Attrs = @('@LIST') })),
            (New-CaroFunction -Key 'ResetPassword' -Title 'Kennwort zuruecksetzen' `
                -Explain 'CARO darf Kennwoerter zuruecksetzen und die Aenderung bei der naechsten Anmeldung erzwingen (Recht: Reset Password, Schreiben von pwdLastSet).' `
                -Specs @(@{ Kind = 'ExtendedRight'; Class = 'user'; ExtendedRight = 'User-Force-Change-Password' }, @{ Kind = 'Props'; Class = 'user'; Attrs = @('pwdLastSet') })),
            (New-CaroFunction -Key 'DisableUser' -Title 'Konto deaktivieren und aktivieren' `
                -Explain 'CARO darf Konten deaktivieren und aktivieren (Schreiben von userAccountControl).' `
                -Specs @(@{ Kind = 'Props'; Class = 'user'; Attrs = @('userAccountControl') })),
            (New-CaroFunction -Key 'UnlockUser' -Title 'Konto entsperren' `
                -Explain 'CARO darf gesperrte Konten entsperren (Schreiben von lockoutTime).' `
                -Specs @(@{ Kind = 'Props'; Class = 'user'; Attrs = @('lockoutTime') })),
            (New-CaroFunction -Key 'SetExpires' -Title 'Ablaufdatum des Kontos bearbeiten' `
                -Explain 'CARO darf das Ablaufdatum eines Kontos aendern (Schreiben von accountExpires).' `
                -Specs @(@{ Kind = 'Props'; Class = 'user'; Attrs = @('accountExpires') })),
            (New-CaroFunction -Key 'MoveUser' -Title 'Benutzer verschieben' `
                -Explain 'CARO darf Benutzer aus dieser OU in andere OUs verschieben, z. B. in die OU fuer deaktivierte Benutzer (Rechte: Loeschen hier, Anlegen im Ziel). Das Ziel muss selbst eine angegebene OU sein.' `
                -Specs @(@{ Kind = 'ClassDelete'; Class = 'user' }, @{ Kind = 'ClassCreate'; Class = 'user' }))
        )
    }

    $roles += [pscustomobject]@{
        Key        = 'GroupOU'
        Title      = 'Gruppen'
        Purpose    = 'CARO legt Gruppen an, z. B. Berechtigungsgruppen fuer Fileserver, und aendert deren Mitglieder. Das geschieht auch automatisch ueber Smart Permissions.'
        Ask        = 'Soll CARO Gruppen in Active Directory verwalten duerfen (mit den oben genannten Rechten)?'
        Question   = 'In welcher OU (oder welchen OUs) liegen bzw. entstehen die Gruppen?'
        BaseSuffix = 'Gruppen'
        Functions  = @(
            (New-CaroFunction -Key 'CreateGroup' -Title 'Gruppen anlegen, umbenennen und aendern' `
                -Explain 'CARO darf Gruppen anlegen, umbenennen und deren Eigenschaften setzen (Rechte: Create Group objects, Read/Write All Properties auf Gruppen).' `
                -Specs @(@{ Kind = 'ClassCreate'; Class = 'group' }, @{ Kind = 'PropsAll'; Class = 'group' })),
            (New-CaroFunction -Key 'DeleteGroup' -Title 'Gruppen loeschen' `
                -Explain 'CARO darf Gruppen in dieser OU loeschen (Recht: Delete Group objects).' `
                -Specs @(@{ Kind = 'ClassDelete'; Class = 'group' })),
            (New-CaroFunction -Key 'GroupMembers' -Title 'Gruppenmitglieder aendern' `
                -Explain 'CARO darf Mitglieder zu Gruppen hinzufuegen und entfernen (Recht: Write Members).' `
                -Specs @(@{ Kind = 'PropsList'; Class = 'group'; Attrs = @('member') })),
            (New-CaroFunction -Key 'SubOus' -Title 'Unter-OUs anlegen (Smart Permissions)' `
                -Explain 'CARO darf in dieser OU weitere OUs anlegen und loeschen, z. B. eine Unter-OU je Fileserver (Rechte: Create/Delete OU objects).' `
                -Specs @(@{ Kind = 'ClassCreate'; Class = 'organizationalUnit' }, @{ Kind = 'ClassDelete'; Class = 'organizationalUnit' }))
        )
    }

    $roles += [pscustomobject]@{
        Key        = 'DisabledUserOU'
        Title      = 'Bereinigung inaktiver Benutzer'
        Purpose    = 'Der CARO-Baustein zur Bereinigung verschiebt Benutzer, die sich x Tage nicht angemeldet haben, in eine eigene OU und loescht sie dort nach weiteren x Tagen.'
        Ask        = 'Nutzen Sie diese Bereinigung (CARO bekommt dafuer die oben genannten Rechte)?'
        Question   = 'Welche OU nimmt die verschobenen Benutzer auf?'
        BaseSuffix = 'Deaktivierte Benutzer'
        Functions  = @(
            (New-CaroFunction -Key 'ReceiveUsers' -Title 'Benutzer aufnehmen (Verschieben hierher)' `
                -Explain 'CARO darf Benutzer in diese OU verschieben. Technisch ist dafuer dasselbe Recht noetig wie zum Anlegen (Create User objects). CARO koennte hier also auch Benutzer neu anlegen. Das laesst sich in AD nicht trennen.' `
                -Specs @(@{ Kind = 'ClassCreate'; Class = 'user' })),
            (New-CaroFunction -Key 'DeleteUser' -Title 'Benutzer loeschen' `
                -Explain 'CARO darf dort Benutzer loeschen (Baustein "Deaktivierte Benutzer in einer OU loeschen").' `
                -Specs @(@{ Kind = 'ClassDelete'; Class = 'user' })),
            (New-CaroFunction -Key 'DisableUser' -Title 'Konto deaktivieren' `
                -Explain 'CARO darf dort Konten deaktivieren (Schreiben von userAccountControl).' `
                -Specs @(@{ Kind = 'Props'; Class = 'user'; Attrs = @('userAccountControl') }))
        )
    }

    $roles += [pscustomobject]@{
        Key        = 'MembershipOU'
        Title      = 'Weitere Gruppen fuer neue Benutzer'
        Purpose    = 'Optional: Gruppen ausserhalb der oben genannten Gruppen-OU, in die CARO neue Benutzer beim Anlegen automatisch eintraegt. Dort darf CARO nur Mitglieder aendern.'
        Ask        = ''
        Question   = 'In welcher OU (oder welchen OUs) liegen diese Gruppen?'
        BaseSuffix = ''
        Functions  = @(
            (New-CaroFunction -Key 'GroupMembers' -Title 'Gruppenmitglieder aendern' `
                -Explain 'CARO darf nur Mitglieder hinzufuegen und entfernen (Recht: Write Members). Kein Anlegen oder Loeschen von Gruppen.' `
                -Specs @(@{ Kind = 'PropsList'; Class = 'group'; Attrs = @('member') }))
        )
    }

    return $roles
}

function Get-CaroRole {
    param([Parameter(Mandatory = $true)][string]$Key)
    return (Get-CaroRoleCatalog | Where-Object { $_.Key -eq $Key } | Select-Object -First 1)
}

# Alle Funktionsschluessel einer Rolle; SubOus nur auf Wunsch.
function Get-CaroDefaultFunctionKeys {
    param(
        [Parameter(Mandatory = $true)][string]$RoleKey,
        [bool]$IncludeSubOus = $false
    )
    $keys = @()
    foreach ($f in (Get-CaroRole -Key $RoleKey).Functions) {
        if ($f.Key -eq 'SubOus' -and -not $IncludeSubOus) { continue }
        $keys += $f.Key
    }
    return $keys
}

# Anzeigename einer AD-Klasse.
function Get-CaroClassLabel {
    param([string]$Class)
    switch ($Class) {
        'user' { return 'Benutzer' }
        'group' { return 'Gruppen' }
        'organizationalUnit' { return 'OUs' }
        default { return $Class }
    }
}

# Rohe Bausteine einer Rolle zu konkreten Bausteinen zusammenfuehren.
#  - 'Props' wird je nach Attribut-Strategie zu PropsAll oder PropsList.
#  - PropsAll einer Klasse ersetzt alle PropsList derselben Klasse.
#  - PropsList derselben Klasse werden vereinigt.
#  - Jeder konkrete Baustein merkt sich, welche CARO-Funktionen ihn brauchen.
function Get-CaroRoleSpecs {
    param(
        [Parameter(Mandatory = $true)][string]$RoleKey,
        [Parameter(Mandatory = $true)][string[]]$FunctionKeys,
        [Parameter(Mandatory = $true)][ValidateSet('All', 'List')][string]$AttributeMode,
        [string[]]$FileAttributes = @()
    )

    $role = Get-CaroRole -Key $RoleKey
    $simple = New-Object System.Collections.ArrayList     # ClassCreate, ClassDelete, ExtendedRight
    $allProps = @{}                                       # Klasse -> Liste der Funktionstitel
    $listProps = @{}                                      # Klasse -> @{ Attrs = ArrayList; Titles = ArrayList }

    foreach ($f in $role.Functions) {
        if ($FunctionKeys -notcontains $f.Key) { continue }
        foreach ($s in $f.Specs) {
            $kind = $s.Kind
            $class = $s.Class
            $attrs = @()
            if ($s.Attrs) {
                foreach ($a in $s.Attrs) {
                    if ($a -eq '@LIST') { $attrs += $FileAttributes } else { $attrs += $a }
                }
            }
            if ($kind -eq 'Props') {
                if ($AttributeMode -eq 'All') { $kind = 'PropsAll' } else { $kind = 'PropsList' }
            }
            switch ($kind) {
                'PropsAll' {
                    if (-not $allProps.ContainsKey($class)) { $allProps[$class] = New-Object System.Collections.ArrayList }
                    if ($allProps[$class] -notcontains $f.Title) { [void]$allProps[$class].Add($f.Title) }
                }
                'PropsList' {
                    if (-not $listProps.ContainsKey($class)) {
                        $listProps[$class] = @{ Attrs = (New-Object System.Collections.ArrayList); Titles = (New-Object System.Collections.ArrayList) }
                    }
                    foreach ($a in $attrs) {
                        if ($listProps[$class].Attrs -notcontains $a) { [void]$listProps[$class].Attrs.Add($a) }
                    }
                    if ($listProps[$class].Titles -notcontains $f.Title) { [void]$listProps[$class].Titles.Add($f.Title) }
                }
                default {
                    $ext = ''
                    if ($s.ExtendedRight) { $ext = $s.ExtendedRight }
                    $existing = $simple | Where-Object { $_.Kind -eq $kind -and $_.Class -eq $class -and $_.ExtendedRight -eq $ext } | Select-Object -First 1
                    if ($existing) {
                        if ($existing.Functions -notcontains $f.Title) { $existing.Functions += $f.Title }
                    }
                    else {
                        [void]$simple.Add([pscustomobject]@{ Kind = $kind; Class = $class; Attributes = @(); ExtendedRight = $ext; Functions = @($f.Title) })
                    }
                }
            }
        }
    }

    $result = New-Object System.Collections.ArrayList
    foreach ($s in $simple) { [void]$result.Add($s) }
    foreach ($class in @($allProps.Keys | Sort-Object)) {
        $titles = New-Object System.Collections.ArrayList
        foreach ($t in $allProps[$class]) { [void]$titles.Add($t) }
        if ($listProps.ContainsKey($class)) {
            foreach ($t in $listProps[$class].Titles) { if ($titles -notcontains $t) { [void]$titles.Add($t) } }
        }
        [void]$result.Add([pscustomobject]@{ Kind = 'PropsAll'; Class = $class; Attributes = @(); ExtendedRight = ''; Functions = @($titles) })
    }
    foreach ($class in @($listProps.Keys | Sort-Object)) {
        if ($allProps.ContainsKey($class)) { continue }
        [void]$result.Add([pscustomobject]@{
                Kind = 'PropsList'; Class = $class; Attributes = @($listProps[$class].Attrs); ExtendedRight = ''; Functions = @($listProps[$class].Titles)
            })
    }
    return @($result)
}

# Lesbare Beschreibung eines konkreten Bausteins.
function Get-CaroSpecTitle {
    param([Parameter(Mandatory = $true)]$Spec)
    $label = Get-CaroClassLabel -Class $Spec.Class
    switch ($Spec.Kind) {
        'ClassCreate' { return ('Anlegen von {0}-Objekten (Create {1} objects)' -f $label, $Spec.Class) }
        'ClassDelete' { return ('Loeschen von {0}-Objekten (Delete {1} objects)' -f $label, $Spec.Class) }
        'PropsAll' { return ('Alle Eigenschaften von {0} lesen und schreiben (Read/Write All Properties)' -f $label) }
        'PropsList' {
            $attrs = @($Spec.Attributes)
            $shown = ($attrs | Select-Object -First 6) -join ', '
            if ($attrs.Count -gt 6) { $shown += ', ... (insgesamt {0})' -f $attrs.Count }
            return ('Bestimmte Eigenschaften von {0} lesen und schreiben (Property-specific): {1}' -f $label, $shown)
        }
        'ExtendedRight' {
            if ($Spec.ExtendedRight -eq 'User-Force-Change-Password') { return 'Kennwort von Benutzern zuruecksetzen (Reset Password)' }
            return ('Erweitertes Recht {0} auf {1}' -f $Spec.ExtendedRight, $label)
        }
        default { return ('{0} auf {1}' -f $Spec.Kind, $label) }
    }
}

# Orte der Attributliste:
#  1. Skriptordner:  CARO-AD-Attributes.json neben dem Skript (z. B. mitgeliefert oder von Hand abgelegt)
#  2. Log-Unterordner: CARO-AD-Attributes.json in CARO-ServiceAccount-Setup-Logs (dort legt das Skript die Vorlage ab)
#  3. eingebettete Liste im Skript (Rueckfallebene)
function Get-CaroAttributeFilePath {
    return (Join-Path (Get-CaroRoot) 'CARO-AD-Attributes.json')
}

function Get-CaroGeneratedAttributeFilePath {
    return (Join-Path (Get-CaroLogFolder) 'CARO-AD-Attributes.json')
}

# Liest die Attributliste in der Reihenfolge der drei Orte oben.
function Read-CaroAttributeFile {
    $scriptPath = Get-CaroAttributeFilePath
    $generatedPath = Get-CaroGeneratedAttributeFilePath
    $embedded = $false
    if (Test-Path -LiteralPath $scriptPath) {
        $text = Read-CaroTextFile -Path $scriptPath
        $source = $scriptPath
    }
    elseif (Test-Path -LiteralPath $generatedPath) {
        $text = Read-CaroTextFile -Path $generatedPath
        $source = $generatedPath
    }
    elseif ($script:CaroEmbeddedAttributesJson) {
        $text = $script:CaroEmbeddedAttributesJson
        $source = '(im Skript eingebettet)'
        $embedded = $true
    }
    else {
        throw ("Die Attributliste wurde nicht gefunden. Sie muss neben dem Skript ({0}) oder im Ordner {1} liegen." -f $scriptPath, (Split-Path -Parent $generatedPath))
    }
    $json = $text | ConvertFrom-Json
    $required = @()
    if ($json.Pflichtattribute) { $required = @($json.Pflichtattribute.PSObject.Properties | ForEach-Object { $_.Name }) }
    return [pscustomobject]@{
        Path          = $source
        FilePath      = $generatedPath
        Embedded      = $embedded
        Text          = $text
        Attributes    = @($json.Attribute)
        RequiredAttrs = $required
    }
}

# ===== 04-Actions.ps1 =====
# 04-Actions.ps1
# Aus den Entscheidungen des Ausfuehrenden (Settings) wird die Aktionsliste erzeugt.
# Diese Funktionen greifen NICHT auf AD, Exchange oder Fileserver zu und sind daher ohne
# Zielumgebung testbar. Jede Aktion beschreibt: Was, Wo, Warum.

# Ein einzelner AD-Zugriffseintrag (ACE) in Textform; die GUIDs werden erst beim Apply aus dem Schema gelesen.
function New-CaroAceDescriptor {
    param(
        [string]$Rights,
        [string]$ObjectKind,
        [string]$ObjectName,
        [string]$Inheritance,
        [string]$InheritedClass
    )
    return [pscustomobject]@{
        Rights         = $Rights
        ObjectKind     = $ObjectKind
        ObjectName     = $ObjectName
        Inheritance    = $Inheritance
        InheritedClass = $InheritedClass
    }
}

# Rechte-Baustein in die einzelnen AD-Zugriffseintraege zerlegen.
function Expand-CaroAceSpec {
    param([Parameter(Mandatory = $true)]$Spec)
    $out = @()
    switch ($Spec.Kind) {
        'ClassCreate' {
            $out += New-CaroAceDescriptor -Rights 'CreateChild' -ObjectKind 'Class' -ObjectName $Spec.Class -Inheritance 'All' -InheritedClass ''
        }
        'ClassDelete' {
            $out += New-CaroAceDescriptor -Rights 'DeleteChild' -ObjectKind 'Class' -ObjectName $Spec.Class -Inheritance 'All' -InheritedClass ''
            $out += New-CaroAceDescriptor -Rights 'Delete' -ObjectKind 'None' -ObjectName '' -Inheritance 'Descendents' -InheritedClass $Spec.Class
        }
        'PropsAll' {
            $out += New-CaroAceDescriptor -Rights 'ReadProperty, WriteProperty' -ObjectKind 'None' -ObjectName '' -Inheritance 'Descendents' -InheritedClass $Spec.Class
        }
        'PropsList' {
            foreach ($a in @($Spec.Attributes)) {
                $out += New-CaroAceDescriptor -Rights 'ReadProperty, WriteProperty' -ObjectKind 'Attribute' -ObjectName $a -Inheritance 'Descendents' -InheritedClass $Spec.Class
            }
        }
        'ExtendedRight' {
            $out += New-CaroAceDescriptor -Rights 'ExtendedRight' -ObjectKind 'ExtendedRight' -ObjectName $Spec.ExtendedRight -Inheritance 'Descendents' -InheritedClass $Spec.Class
        }
        default { throw ("Unbekannter Rechte-Baustein: {0}" -f $Spec.Kind) }
    }
    return $out
}

# Rolleneinstellungen lesen, egal ob Settings ein Hashtable ist (Plan) oder aus JSON geladen wurde (Apply).
function Get-CaroRoleSettings {
    param(
        [Parameter(Mandatory = $true)]$Settings,
        [Parameter(Mandatory = $true)][string]$Key
    )
    if ($null -eq $Settings.Roles) { return $null }
    if ($Settings.Roles -is [System.Collections.IDictionary]) {
        if ($Settings.Roles.Contains($Key)) { return $Settings.Roles[$Key] }
        return $null
    }
    $prop = $Settings.Roles.PSObject.Properties[$Key]
    if ($prop) { return $prop.Value }
    return $null
}

function New-CaroAction {
    param(
        [string]$Type,
        [string]$Area,
        [string]$What,
        [string]$Where,
        [string]$Why,
        [hashtable]$Params
    )
    return [pscustomobject]@{
        Id        = ''
        Type      = $Type
        Area      = $Area
        What      = $What
        Where     = $Where
        Why       = $Why
        Params    = $Params
        PlanState = 'Unbekannt'
    }
}

# Erzeugt die komplette, geordnete Aktionsliste.
# Reihenfolge: Account, lokale Gruppen (CARO-Server), Fileserver, Exchange, AD-Delegationen.
function New-CaroActionList {
    param([Parameter(Mandatory = $true)][hashtable]$Settings)

    $acc = $Settings.Account
    $sam = $acc.Sam
    $actions = New-Object System.Collections.ArrayList

    # 1) Account
    if ($acc.Adopt) {
        $what = "Vorhandenen Account '$sam' uebernehmen (Passwort und Attribute bleiben unveraendert)"
    }
    else {
        $what = "Service-Account '$sam' anlegen"
    }
    [void]$actions.Add((New-CaroAction -Type 'CreateAccount' -Area 'Konto' `
                -What $what -Where $acc.TargetOu `
                -Why 'CARO fuehrt alle Lese- und Schreiboperationen mit einem hinterlegten Zugangskonto aus; ein eigenes Service-Konto wird empfohlen.' `
                -Params @{
                Sam                  = $sam
                DisplayName          = $acc.DisplayName
                Description          = $acc.Description
                TargetOu             = $acc.TargetOu
                Adopt                = [bool]$acc.Adopt
                PasswordMode         = $acc.PasswordMode
                PasswordNeverExpires = [bool]$acc.PasswordNeverExpires
            }))

    # 2) Lokale Administratoren des CARO-Servers (immer)
    [void]$actions.Add((New-CaroAction -Type 'AddLocalGroupMember' -Area 'CARO-Server' `
                -What "Account '$sam' in die lokalen Administratoren eintragen (S-1-5-32-544)" `
                -Where ('CARO-Server ' + [System.Environment]::MachineName) `
                -Why 'Grundvoraussetzung fuer alle CARO-Funktionen: der Account muss lokaler Administrator auf dem CARO-Server sein.' `
                -Params @{ Computer = '.'; ComputerLabel = [System.Environment]::MachineName; GroupSid = $script:CaroSid.Administrators; GroupLabel = 'Administrators'; Sam = $sam }))

    # 3) Fileserver
    $fs = $Settings.Fileserver
    if ($fs -and $fs.Mode -ne 'None') {
        foreach ($server in @($fs.Servers)) {
            $groups = @(
                @{ Sid = $script:CaroSid.BackupOperators; Label = 'Backup Operators'; Why = 'Berechtigungen auf dem Fileserver auslesen.' },
                @{ Sid = $script:CaroSid.PrintOperators; Label = 'Print Operators'; Why = 'Freigabeberechtigungen (Share-Permissions) auslesen.' }
            )
            if ($fs.Mode -eq 'Manage') {
                $groups += @{ Sid = $script:CaroSid.Administrators; Label = 'Administrators'; Why = 'Berechtigungen schreiben: Ordner anlegen und loeschen, Besitzer aendern, Vererbung schalten, Zugriffsrechte aendern. Einzelrechte pro Ordner reichen dafuer nicht aus.' }
            }
            foreach ($g in $groups) {
                [void]$actions.Add((New-CaroAction -Type 'AddLocalGroupMember' -Area 'Fileserver' `
                            -What ("Account '{0}' in die lokale Gruppe '{1}' ({2}) eintragen" -f $sam, $g.Label, $g.Sid) `
                            -Where ('Fileserver ' + $server) `
                            -Why $g.Why `
                            -Params @{ Computer = $server; ComputerLabel = $server; GroupSid = $g.Sid; GroupLabel = $g.Label; Sam = $sam }))
            }
        }
    }

    # 4) Exchange
    if ($Settings.Exchange -and $Settings.Exchange -ne 'None') {
        $roleGroup = $script:CaroExchangeRoleGroup[$Settings.Exchange]
        if ($Settings.Exchange -eq 'Management') {
            $why = 'Exchange-Verwaltung durch CARO: Postfaecher aktivieren oder erstellen, Abwesenheitsnotizen, Vollzugriff, Senden-als, Limits, SMTP-Adressen.'
        }
        else {
            $why = 'Nur Lesezugriff auf Exchange (Analysen). Verwaltungsaufgaben in Exchange funktionieren damit nicht.'
        }
        [void]$actions.Add((New-CaroAction -Type 'AddExchangeRoleGroupMember' -Area 'Exchange' `
                    -What ("Account '{0}' in die Exchange-Rollengruppe '{1}' eintragen" -f $sam, $roleGroup) `
                    -Where 'Exchange (On-Premises)' `
                    -Why $why `
                    -Params @{ RoleGroup = $roleGroup; Sam = $sam }))
    }

    # 5) AD-Delegationen je Rolle und OU
    foreach ($role in (Get-CaroRoleCatalog)) {
        $rs = Get-CaroRoleSettings -Settings $Settings -Key $role.Key
        if (-not $rs -or -not $rs.Enabled) { continue }
        $specs = Get-CaroRoleSpecs -RoleKey $role.Key -FunctionKeys @($rs.Functions) -AttributeMode $Settings.AttributeMode -FileAttributes @($Settings.FileAttributes)
        foreach ($target in @($rs.Targets)) {
            foreach ($spec in $specs) {
                $specParam = @{
                    Kind          = $spec.Kind
                    Class         = $spec.Class
                    Attributes    = @($spec.Attributes)
                    ExtendedRight = $spec.ExtendedRight
                }
                [void]$actions.Add((New-CaroAction -Type 'GrantAd' -Area 'Active Directory' `
                            -What ('Recht vergeben: ' + (Get-CaroSpecTitle -Spec $spec)) `
                            -Where ($target + ' (inklusive aller Unter-OUs)') `
                            -Why ('Bereich "{0}". Benoetigt fuer: {1}.' -f $role.Title, (@($spec.Functions) -join ', ')) `
                            -Params @{ TargetDn = $target; Role = $role.Key; Spec = $specParam }))
            }
        }
    }

    $list = @($actions)
    for ($i = 0; $i -lt $list.Count; $i++) { $list[$i].Id = 'A{0:000}' -f ($i + 1) }
    return $list
}

# Warnung fuer Zielrechner, die Domaenencontroller sind. Dort sind die "lokalen" Gruppen Domaenengruppen (Container Builtin).
# Das Skript arbeitet trotzdem weiter, es weist nur ausdruecklich darauf hin.
function Get-CaroDomainControllerWarnings {
    param(
        [Parameter(Mandatory = $true)][object[]]$Actions,
        [string[]]$DomainControllers = @()
    )
    $consequence = @{
        'S-1-5-32-544' = 'Administrators (damit hat der Account praktisch Domaenenadministrator-Rechte)'
        'S-1-5-32-551' = 'Backup Operators (darf Dateien und Registrierung der Domaenencontroller sichern und wiederherstellen)'
        'S-1-5-32-550' = 'Print Operators (darf auf Domaenencontrollern Druckertreiber laden)'
    }
    $warnings = @()
    foreach ($dc in $DomainControllers) {
        $sids = @()
        foreach ($a in $Actions) {
            if ($a.Type -eq 'AddLocalGroupMember' -and $a.Params.ComputerLabel -ieq $dc -and $sids -notcontains $a.Params.GroupSid) { $sids += $a.Params.GroupSid }
        }
        if ($sids.Count -eq 0) { continue }
        $groups = @($sids | ForEach-Object { if ($consequence.ContainsKey($_)) { $consequence[$_] } else { $_ } })
        $warnings += ("{0} ist ein Domaenencontroller. Dort sind die 'lokalen' Gruppen Domaenengruppen (Container Builtin) und gelten fuer die ganze Domaene. Der Account wird Mitglied von: {1}. In der Praxis sollten CARO-Server und Fileserver keine Domaenencontroller sein. Das Skript arbeitet trotzdem weiter." -f $dc, ($groups -join '; '))
    }
    return $warnings
}

# Rechte-Zusammenfassung je Rolle fuer Uebersicht und Report.
function New-CaroConfig {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Settings,
        [Parameter(Mandatory = $true)][object[]]$Actions,
        [string[]]$Warnings = @()
    )
    $now = Get-Date
    return [ordered]@{
        SchemaVersion   = 1
        ConfigurationId = 'cfg-{0}-{1}' -f $now.ToString('yyyyMMddHHmmss'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
        PlanId          = $now.ToString('o')
        ExecutionId     = $null
        CreatedAt       = $now.ToString('o')
        ComputerName    = [System.Environment]::MachineName
        CreatedBy       = ('{0}\{1}' -f [System.Environment]::UserDomainName, [System.Environment]::UserName)
        Settings        = $Settings
        Warnings        = @($Warnings)
        Actions         = @($Actions)
    }
}

$script:CaroActionTypes = @('CreateAccount', 'AddLocalGroupMember', 'AddExchangeRoleGroupMember', 'GrantAd')

# Prueft eine geladene Config-Datei. Liefert eine Liste von Fehlertexten (leer = in Ordnung).
function Test-CaroConfig {
    param([Parameter(Mandatory = $true)]$Config)
    $errors = @()
    if ($Config.SchemaVersion -ne 1) { $errors += 'SchemaVersion ist nicht 1. Die Datei stammt nicht von dieser Skriptversion.' }
    if (-not $Config.ConfigurationId) { $errors += 'ConfigurationId fehlt.' }
    if (-not $Config.Settings -or -not $Config.Settings.Account -or -not $Config.Settings.Account.Sam) {
        $errors += 'Settings.Account.Sam fehlt.'
    }
    $actions = @($Config.Actions)
    if ($actions.Count -eq 0) { $errors += 'Die Config enthaelt keine Aktionen.' }
    foreach ($a in $actions) {
        if ($script:CaroActionTypes -notcontains $a.Type) { $errors += ("Aktion {0}: unbekannter Typ '{1}'." -f $a.Id, $a.Type); continue }
        if (-not $a.Params) { $errors += ("Aktion {0}: Params fehlen." -f $a.Id); continue }
        if ($a.Type -eq 'GrantAd') {
            if (-not $a.Params.TargetDn) { $errors += ("Aktion {0}: TargetDn fehlt." -f $a.Id) }
            if (-not $a.Params.Spec -or -not $a.Params.Spec.Kind) { $errors += ("Aktion {0}: Spec fehlt." -f $a.Id) }
        }
    }
    return $errors
}

# Markdown-Report fuer Review und Freigabe.
function ConvertTo-CaroReportMarkdown {
    param([Parameter(Mandatory = $true)]$Config)
    $s = $Config.Settings
    $sb = New-Object System.Text.StringBuilder
    $nl = [Environment]::NewLine
    [void]$sb.AppendLine('# CARO Service-Account: Plan')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine(('- Konfiguration: `{0}`' -f $Config.ConfigurationId))
    [void]$sb.AppendLine(('- Plan erstellt: {0} auf CARO-Server `{1}` durch `{2}`' -f $Config.PlanId, $Config.ComputerName, $Config.CreatedBy))
    [void]$sb.AppendLine('- Dieser Plan hat **nichts geaendert**. Aenderungen erfolgen erst mit `-Mode Apply`.')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## Zusammenfassung')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine(('- Account: `{0}` in `{1}`' -f $s.Account.Sam, $s.Account.TargetOu))
    if ($s.Account.Adopt) { [void]$sb.AppendLine('- Der Account existiert bereits und wird uebernommen.') }
    [void]$sb.AppendLine(('- Profil: {0}' -f $s.Profile))
    foreach ($role in (Get-CaroRoleCatalog)) {
        $rs = Get-CaroRoleSettings -Settings $s -Key $role.Key
        if (-not $rs -or -not $rs.Enabled) { continue }
        $titles = @()
        foreach ($f in $role.Functions) { if (@($rs.Functions) -contains $f.Key) { $titles += $f.Title } }
        [void]$sb.AppendLine(('- {0}: {1}' -f $role.Title, (@($rs.Targets) -join '; ')))
        [void]$sb.AppendLine(('  - Funktionen: {0}' -f ($titles -join ', ')))
    }
    if ($s.AttributeMode) {
        if ($s.AttributeMode -eq 'All') { $am = 'Alle Eigenschaften (Write All Properties)' } else { $am = 'Nur Attributliste (Property-specific)' }
        [void]$sb.AppendLine(('- Benutzerattribute: {0}' -f $am))
    }
    [void]$sb.AppendLine(('- Exchange: {0}' -f $s.Exchange))
    if ($s.Fileserver -and $s.Fileserver.Mode -ne 'None') {
        [void]$sb.AppendLine(('- Fileserver ({0}): {1}' -f $s.Fileserver.Mode, (@($s.Fileserver.Servers) -join ', ')))
    }
    else {
        [void]$sb.AppendLine('- Fileserver: Nein')
    }
    [void]$sb.AppendLine('')
    if (@($Config.Warnings).Count -gt 0) {
        [void]$sb.AppendLine('## Warnungen')
        [void]$sb.AppendLine('')
        foreach ($w in @($Config.Warnings)) { [void]$sb.AppendLine(('- {0}' -f $w)) }
        [void]$sb.AppendLine('')
    }
    [void]$sb.AppendLine('## Aktionen')
    [void]$sb.AppendLine('')
    foreach ($a in @($Config.Actions)) {
        [void]$sb.AppendLine(('### {0}: {1}' -f $a.Id, $a.What))
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine(('- **Wo:** {0}' -f $a.Where))
        [void]$sb.AppendLine(('- **Warum:** {0}' -f $a.Why))
        [void]$sb.AppendLine(('- **Zustand bei Plan:** {0}' -f $a.PlanState))
        if ($a.Type -eq 'GrantAd' -and $a.Params.Spec.Kind -eq 'PropsList') {
            [void]$sb.AppendLine(('- **Attribute:** {0}' -f (@($a.Params.Spec.Attributes) -join ', ')))
        }
        [void]$sb.AppendLine('')
    }
    [void]$sb.AppendLine('## Hinweise')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('- Exchange Online und Entra ID werden in CARO ueber die App-Registrierung "CARO-Suite M365 Connector" angebunden, nicht ueber dieses Skript.')
    [void]$sb.AppendLine('- Der Observer (Ueberwachung von AD-Security-Events) braucht eigene Voraussetzungen auf den Domaenencontrollern und ist nicht Teil dieses Skripts.')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## Naechster Schritt')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('`.\CARO-ServiceAccount-Setup.ps1 -Mode Apply -ConfigPath <Pfad zur Config.json>`')
    return $sb.ToString()
}

# ===== 05-Environment.ps1 =====
# 05-Environment.ps1
# Pruefung der Umgebung (Voraussetzungen) und lesende Zugriffe auf AD, lokale Gruppen und Exchange.
# Das Skript bricht ab, wenn eine Voraussetzung fehlt. Es simuliert nichts stillschweigend.

$script:CaroDomain = $null

function New-CaroCheck {
    param(
        [string]$Name,
        [bool]$Ok,
        [string]$Detail
    )
    return [pscustomobject]@{ Name = $Name; Ok = $Ok; Detail = $Detail }
}

# Prueft die Voraussetzungen. Areas: 'Exchange' bei Exchange-Auswahl. FileServers: Liste der Fileserver.
function Test-CaroPrerequisites {
    param(
        [string[]]$Areas = @(),
        [string[]]$FileServers = @()
    )
    $r = @()

    $v = $PSVersionTable.PSVersion
    $r += New-CaroCheck -Name 'PowerShell 5.1 oder neuer' -Ok ($v -ge [version]'5.1') -Detail ('gefunden: {0}' -f $v)

    $elevated = $false
    try {
        $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $elevated = ([System.Security.Principal.WindowsPrincipal]$id).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch { $elevated = $false }
    $r += New-CaroCheck -Name 'Skript laeuft als Administrator (erhoeht)' -Ok $elevated -Detail 'Noetig fuer die lokale Gruppenaenderung auf dem CARO-Server. PowerShell mit "Als Administrator ausfuehren" starten.'

    $domainMember = $false
    try { $domainMember = [bool](Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop).PartOfDomain } catch { $domainMember = $false }
    $r += New-CaroCheck -Name 'Rechner ist Mitglied einer Domaene' -Ok $domainMember -Detail 'Der CARO-Server muss in der Domaene des Service-Accounts sein.'

    $adModule = $false
    try {
        if (Get-Module -ListAvailable -Name ActiveDirectory) {
            Import-Module ActiveDirectory -ErrorAction Stop
            $adModule = $true
        }
    }
    catch { $adModule = $false }
    $r += New-CaroCheck -Name 'PowerShell-Modul ActiveDirectory (RSAT)' -Ok $adModule -Detail 'Installation: Windows-Feature "RSAT: Active Directory-Modul fuer Windows PowerShell".'

    if ($adModule) {
        $domainOk = $false
        $detail = ''
        try {
            $d = Get-ADDomain -ErrorAction Stop
            $domainOk = $true
            $detail = 'Domaene: {0}' -f $d.DNSRoot
        }
        catch { $detail = 'Domaene nicht erreichbar: ' + $_.Exception.Message }
        $r += New-CaroCheck -Name 'Active Directory erreichbar' -Ok $domainOk -Detail $detail
    }

    if ($Areas -contains 'Exchange') {
        $hasCmd = [bool](Get-Command -Name 'Add-RoleGroupMember' -ErrorAction SilentlyContinue)
        if (-not $hasCmd) {
            try { Add-PSSnapin -Name 'Microsoft.Exchange.Management.PowerShell.SnapIn' -ErrorAction Stop } catch { }
            $hasCmd = [bool](Get-Command -Name 'Add-RoleGroupMember' -ErrorAction SilentlyContinue)
        }
        $r += New-CaroCheck -Name 'Exchange-Verwaltungstools (Add-RoleGroupMember)' -Ok $hasCmd -Detail 'Die Exchange Management Tools bzw. Management Shell muessen auf dem CARO-Server verfuegbar sein.'
    }

    foreach ($server in $FileServers) {
        $reachable = $false
        $detail = ''
        try {
            $null = Test-WSMan -ComputerName $server -ErrorAction Stop
            $reachable = $true
            $detail = 'WinRM erreichbar'
        }
        catch { $detail = 'WinRM nicht erreichbar: ' + $_.Exception.Message }
        $r += New-CaroCheck -Name ('Fileserver {0} erreichbar' -f $server) -Ok $reachable -Detail $detail
    }
    return $r
}

# Zeigt das Ergebnis der Pruefung an. Liefert $true, wenn alles in Ordnung ist.
function Show-CaroPrerequisites {
    param([Parameter(Mandatory = $true)][object[]]$Results)
    $allOk = $true
    foreach ($c in $Results) {
        if ($c.Ok) {
            Write-CaroMessage -Message ('  [OK]    {0}' -f $c.Name) -Level 'OK'
        }
        else {
            $allOk = $false
            Write-CaroMessage -Message ('  [FEHLT] {0}' -f $c.Name) -Level 'ERROR'
            Write-CaroMessage -Message ('          {0}' -f $c.Detail) -Level 'ERROR'
        }
    }
    return $allOk
}

# Domaeneninformationen (einmal lesen und merken).
function Get-CaroDomainInfo {
    if ($script:CaroDomain) { return $script:CaroDomain }
    $d = Get-ADDomain -ErrorAction Stop
    $root = Get-ADRootDSE -ErrorAction Stop
    $script:CaroDomain = [pscustomobject]@{
        DnsRoot  = $d.DNSRoot
        NetBios  = $d.NetBIOSName
        Dn       = $d.DistinguishedName
        SchemaNc = $root.schemaNamingContext
        ConfigNc = $root.configurationNamingContext
    }
    return $script:CaroDomain
}

# Prueft, ob die Eingabe wie ein Distinguished Name aussieht.
function Test-CaroDnFormat {
    param([string]$Dn)
    return ($Dn -match '^(OU|CN|DC)=[^,]+(,(OU|CN|DC)=[^,]+)*$')
}

# Ergaenzt den Domaenenteil: "OU=Service,OU=Accounts" wird zu "OU=Service,OU=Accounts,DC=firma,DC=de".
# Wer den Domaenenteil schon mit angibt (DC=...), dessen Eingabe bleibt unveraendert.
function ConvertTo-CaroOuDn {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$DomainDn
    )
    $t = ($Text.Trim() -replace '\s*,\s*', ',')
    if ($t -match '(^|,)DC=') { return $t }
    return ('{0},{1}' -f $t, $DomainDn)
}

# Kuerzt einen Distinguished Name um den Domaenenteil (fuer die Anzeige als Vorschlag).
function ConvertTo-CaroShortOu {
    param(
        [Parameter(Mandatory = $true)][string]$Dn,
        [Parameter(Mandatory = $true)][string]$DomainDn
    )
    $suffix = ',' + $DomainDn
    if ($Dn.EndsWith($suffix, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $Dn.Substring(0, $Dn.Length - $suffix.Length)
    }
    return $Dn
}

# Liefert den Distinguished Name einer vorhandenen OU (oder eines Containers bzw. der Domaene), sonst $null.
function Get-CaroOuDn {
    param([Parameter(Mandatory = $true)][string]$Dn)
    try {
        $o = Get-ADObject -Identity $Dn -Properties objectClass -ErrorAction Stop
        if (@('organizationalUnit', 'container', 'domainDNS') -contains $o.objectClass) { return [string]$o.DistinguishedName }
        return $null
    }
    catch { return $null }
}

# Ist der Rechner ein Domaenencontroller? Frage an AD, daher ohne Remoting auch fuer Fileserver moeglich.
function Test-CaroDomainController {
    param([Parameter(Mandatory = $true)][string]$Computer)
    $name = $Computer
    if ($Computer -eq '.') { $name = [System.Environment]::MachineName }
    try { $null = Get-ADDomainController -Identity $name -ErrorAction Stop; return $true }
    catch { return $false }
}

# Welche der Zielrechner (CARO-Server, Fileserver) sind Domaenencontroller?
function Find-CaroDomainControllers {
    param([Parameter(Mandatory = $true)][object[]]$Actions)
    $names = @($Actions | Where-Object { $_.Type -eq 'AddLocalGroupMember' } | ForEach-Object { $_.Params.ComputerLabel } | Select-Object -Unique)
    $found = @()
    foreach ($n in $names) {
        if (Test-CaroDomainController -Computer $n) { $found += $n }
    }
    return $found
}

# Sucht einen vorhandenen Account ueber den SamAccountName.
function Get-CaroExistingAccount {
    param([Parameter(Mandatory = $true)][string]$Sam)
    return (Get-ADUser -Filter ("SamAccountName -eq '{0}'" -f $Sam) -Properties Enabled, Description, MemberOf -ErrorAction SilentlyContinue)
}

# Wird lokal oder per WinRM auf dem Zielserver ausgefuehrt. Arbeitet mit der SID, nicht mit dem Gruppennamen,
# damit es auf deutschen und englischen Systemen gleich funktioniert.
# Operation 'Exists' prueft nur, ob die Gruppe vorhanden ist. Sie listet die Mitglieder NICHT auf, denn Windows
# protokolliert jede Auflistung als eigenes Sicherheitsereignis (4799).
$script:CaroLocalGroupScript = {
    param([string]$GroupSid, [string]$MemberPath, [string]$Operation)
    $result = @{ Status = ''; Message = '' }
    $group = $null
    try {
        $sidObj = New-Object System.Security.Principal.SecurityIdentifier($GroupSid)
        $groupName = $sidObj.Translate([System.Security.Principal.NTAccount]).Value.Split('\')[-1]
        $group = [ADSI]("WinNT://./{0},group" -f $groupName)
        $null = $group.Name
    }
    catch {
        $result.Status = 'GroupMissing'
        $result.Message = 'Die lokale Gruppe mit der SID {0} ist auf diesem Server nicht vorhanden oder nicht lesbar: {1}' -f $GroupSid, $_.Exception.Message
        return $result
    }
    if ($Operation -eq 'Exists') {
        $result.Status = 'Exists'
        return $result
    }
    $isMember = $false
    try {
        foreach ($m in @($group.Invoke('Members'))) {
            $path = $m.GetType().InvokeMember('AdsPath', 'GetProperty', $null, $m, $null)
            if ($path -ieq $MemberPath) { $isMember = $true }
        }
    }
    catch {
        $result.Status = 'Error'
        $result.Message = 'Die Mitglieder der Gruppe konnten nicht gelesen werden: ' + $_.Exception.Message
        return $result
    }
    try {
        switch ($Operation) {
            'Test' {
                if ($isMember) { $result.Status = 'IsMember' } else { $result.Status = 'NotMember' }
            }
            'Add' {
                if ($isMember) { $result.Status = 'AlreadyMember' }
                else { $group.Add($MemberPath); $result.Status = 'Added' }
            }
            'Remove' {
                if ($isMember) { $group.Remove($MemberPath); $result.Status = 'Removed' }
                else { $result.Status = 'NotMember' }
            }
        }
    }
    catch {
        $result.Status = 'Error'
        $result.Message = $_.Exception.Message
    }
    return $result
}

# Lokale Gruppenmitgliedschaft pruefen, hinzufuegen oder entfernen (lokal oder auf einem Fileserver).
function Invoke-CaroLocalGroup {
    param(
        [Parameter(Mandatory = $true)][string]$Computer,
        [Parameter(Mandatory = $true)][string]$GroupSid,
        [Parameter(Mandatory = $true)][string]$Sam,
        [Parameter(Mandatory = $true)][ValidateSet('Exists', 'Test', 'Add', 'Remove')][string]$Operation
    )
    $dom = Get-CaroDomainInfo
    $path = 'WinNT://{0}/{1}' -f $dom.NetBios, $Sam
    if ($Computer -eq '.' -or $Computer -ieq [System.Environment]::MachineName) {
        return (& $script:CaroLocalGroupScript $GroupSid $path $Operation)
    }
    return (Invoke-Command -ComputerName $Computer -ScriptBlock $script:CaroLocalGroupScript -ArgumentList $GroupSid, $path, $Operation -ErrorAction Stop)
}

# Existiert die Exchange-Rollengruppe?
function Test-CaroExchangeRoleGroup {
    param([Parameter(Mandatory = $true)][string]$RoleGroup)
    try { $null = Get-RoleGroup -Identity $RoleGroup -ErrorAction Stop; return $true }
    catch { return $false }
}

# Exchange-Rollengruppe: Mitgliedschaft pruefen, hinzufuegen oder entfernen.
function Invoke-CaroExchangeMember {
    param(
        [Parameter(Mandatory = $true)][string]$RoleGroup,
        [Parameter(Mandatory = $true)][string]$Sam,
        [Parameter(Mandatory = $true)][ValidateSet('Test', 'Add', 'Remove')][string]$Operation
    )
    $members = @(Get-RoleGroupMember -Identity $RoleGroup -ErrorAction Stop)
    $isMember = $false
    foreach ($m in $members) {
        if ($m.SamAccountName -ieq $Sam -or $m.Name -ieq $Sam) { $isMember = $true }
    }
    switch ($Operation) {
        'Test' { if ($isMember) { return 'IsMember' } else { return 'NotMember' } }
        'Add' {
            if ($isMember) { return 'AlreadyMember' }
            Add-RoleGroupMember -Identity $RoleGroup -Member $Sam -Confirm:$false -ErrorAction Stop
            return 'Added'
        }
        'Remove' {
            if (-not $isMember) { return 'NotMember' }
            Remove-RoleGroupMember -Identity $RoleGroup -Member $Sam -Confirm:$false -ErrorAction Stop
            return 'Removed'
        }
    }
}

# ===== 06-AdAcl.ps1 =====
# 06-AdAcl.ps1
# AD-Delegationen: Schema-GUIDs zur Laufzeit lesen, Zugriffseintraege (ACEs) bauen, pruefen, setzen, entfernen.
# GUIDs fuer Klassen, Attribute und erweiterte Rechte stehen NICHT fest im Code, sondern kommen aus dem AD-Schema.

$script:CaroGuidCache = @{}

# SID aus Text erzeugen (eigene Funktion, damit sie in Tests ersetzbar ist).
function ConvertTo-CaroSid {
    param([Parameter(Mandatory = $true)][string]$Value)
    return (New-Object System.Security.Principal.SecurityIdentifier($Value))
}

function Resolve-CaroSchemaGuid {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('None', 'Class', 'Attribute', 'ExtendedRight')][string]$Kind,
        [string]$Name
    )
    if ($Kind -eq 'None' -or -not $Name) { return [guid]::Empty }
    $key = '{0}|{1}' -f $Kind, $Name
    if ($script:CaroGuidCache.ContainsKey($key)) { return $script:CaroGuidCache[$key] }

    $dom = Get-CaroDomainInfo
    if ($Kind -eq 'ExtendedRight') {
        $o = Get-ADObject -SearchBase ('CN=Extended-Rights,' + $dom.ConfigNc) `
            -LDAPFilter ('(&(objectClass=controlAccessRight)(name={0}))' -f $Name) -Properties rightsGuid -ErrorAction Stop |
            Select-Object -First 1
        if (-not $o) { throw ("Erweitertes Recht '{0}' wurde im AD nicht gefunden." -f $Name) }
        $guid = [guid]([string]$o.rightsGuid)
    }
    else {
        if ($Kind -eq 'Class') { $oc = 'classSchema' } else { $oc = 'attributeSchema' }
        $o = Get-ADObject -SearchBase $dom.SchemaNc `
            -LDAPFilter ('(&(objectClass={0})(lDAPDisplayName={1}))' -f $oc, $Name) -Properties schemaIDGUID -ErrorAction Stop |
            Select-Object -First 1
        if (-not $o) { throw ("{0} '{1}' wurde im AD-Schema nicht gefunden." -f $Kind, $Name) }
        $guid = New-Object System.Guid (, ([byte[]]$o.schemaIDGUID))
    }
    $script:CaroGuidCache[$key] = $guid
    return $guid
}

# Baut aus einem Zugriffseintrag in Textform das AD-Zugriffsobjekt.
function New-CaroAdRule {
    param(
        [Parameter(Mandatory = $true)][System.Security.Principal.SecurityIdentifier]$Sid,
        [Parameter(Mandatory = $true)]$Descriptor
    )
    try { Add-Type -AssemblyName System.DirectoryServices -ErrorAction SilentlyContinue } catch { }
    $rights = [System.DirectoryServices.ActiveDirectoryRights]$Descriptor.Rights
    $objGuid = Resolve-CaroSchemaGuid -Kind $Descriptor.ObjectKind -Name $Descriptor.ObjectName
    $inhGuid = [guid]::Empty
    if ($Descriptor.InheritedClass) { $inhGuid = Resolve-CaroSchemaGuid -Kind 'Class' -Name $Descriptor.InheritedClass }
    $inh = [System.DirectoryServices.ActiveDirectorySecurityInheritance]$Descriptor.Inheritance
    return (New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
            $Sid, $rights, [System.Security.AccessControl.AccessControlType]::Allow, $objGuid, $inh, $inhGuid))
}

# Ist genau dieser Zugriffseintrag schon ausdruecklich (nicht geerbt) gesetzt?
function Test-CaroAclContainsRule {
    param(
        [Parameter(Mandatory = $true)]$Acl,
        [Parameter(Mandatory = $true)]$Rule
    )
    foreach ($r in $Acl.GetAccessRules($true, $false, [System.Security.Principal.SecurityIdentifier])) {
        if ($r.IdentityReference.Value -eq $Rule.IdentityReference.Value -and
            $r.ActiveDirectoryRights -eq $Rule.ActiveDirectoryRights -and
            $r.AccessControlType -eq $Rule.AccessControlType -and
            $r.ObjectType -eq $Rule.ObjectType -and
            $r.InheritanceType -eq $Rule.InheritanceType -and
            $r.InheritedObjectType -eq $Rule.InheritedObjectType) { return $true }
    }
    return $false
}

# Zugriffseintrag in eine JSON-taugliche Form bringen (fuer Result.json und Rollback).
function ConvertTo-CaroRuleInfo {
    param(
        [Parameter(Mandatory = $true)][string]$TargetDn,
        [Parameter(Mandatory = $true)]$Rule
    )
    return [ordered]@{
        TargetDn            = $TargetDn
        Sid                 = $Rule.IdentityReference.Value
        Rights              = $Rule.ActiveDirectoryRights.ToString()
        ObjectType          = $Rule.ObjectType.ToString()
        Inheritance         = $Rule.InheritanceType.ToString()
        InheritedObjectType = $Rule.InheritedObjectType.ToString()
    }
}

function ConvertFrom-CaroRuleInfo {
    param([Parameter(Mandatory = $true)]$Info)
    try { Add-Type -AssemblyName System.DirectoryServices -ErrorAction SilentlyContinue } catch { }
    $sid = ConvertTo-CaroSid -Value ([string]$Info.Sid)
    return (New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
            $sid,
            [System.DirectoryServices.ActiveDirectoryRights]([string]$Info.Rights),
            [System.Security.AccessControl.AccessControlType]::Allow,
            [guid]([string]$Info.ObjectType),
            [System.DirectoryServices.ActiveDirectorySecurityInheritance]([string]$Info.Inheritance),
            [guid]([string]$Info.InheritedObjectType)))
}

# Welche Zugriffseintraege einer GrantAd-Aktion fehlen noch? Liefert die Regeln (nur lesend).
function Get-CaroMissingRules {
    param(
        [Parameter(Mandatory = $true)]$Action,
        [Parameter(Mandatory = $true)]$Sid
    )
    $p = $Action.Params
    $acl = Get-Acl -Path ('AD:' + $p.TargetDn)
    $missing = @()
    $total = 0
    foreach ($d in (Expand-CaroAceSpec -Spec $p.Spec)) {
        $total++
        $rule = New-CaroAdRule -Sid $Sid -Descriptor $d
        if (-not (Test-CaroAclContainsRule -Acl $acl -Rule $rule)) { $missing += $rule }
    }
    return [pscustomobject]@{ Acl = $acl; Missing = $missing; Total = $total }
}

# Zustand einer GrantAd-Aktion fuer die Plan-Phase: Neu, Teilweise vorhanden oder Vorhanden.
function Get-CaroAdActionState {
    param(
        [Parameter(Mandatory = $true)]$Action,
        [Parameter(Mandatory = $true)]$Sid
    )
    $m = Get-CaroMissingRules -Action $Action -Sid $Sid
    if ($m.Missing.Count -eq 0) { return 'Vorhanden' }
    if ($m.Missing.Count -eq $m.Total) { return 'Neu' }
    return 'Teilweise vorhanden'
}

# Setzt die fehlenden Zugriffseintraege. Liefert die tatsaechlich neu gesetzten Eintraege (fuer den Rollback).
function Invoke-CaroGrantAd {
    param(
        [Parameter(Mandatory = $true)]$Action,
        [Parameter(Mandatory = $true)]$Sid
    )
    $p = $Action.Params
    $m = Get-CaroMissingRules -Action $Action -Sid $Sid
    $created = @()
    if ($m.Missing.Count -gt 0) {
        foreach ($rule in $m.Missing) {
            $m.Acl.AddAccessRule($rule)
            $created += (ConvertTo-CaroRuleInfo -TargetDn $p.TargetDn -Rule $rule)
        }
        Set-Acl -Path ('AD:' + $p.TargetDn) -AclObject $m.Acl -ErrorAction Stop
    }
    return [pscustomobject]@{ Created = $created; Total = $m.Total }
}

# Entfernt einen zuvor gesetzten Zugriffseintrag wieder. Liefert 'Removed' oder 'NotFound'.
function Invoke-CaroRevokeRule {
    param([Parameter(Mandatory = $true)]$Info)
    $rule = ConvertFrom-CaroRuleInfo -Info $Info
    $path = 'AD:' + [string]$Info.TargetDn
    $acl = Get-Acl -Path $path
    if (-not (Test-CaroAclContainsRule -Acl $acl -Rule $rule)) { return 'NotFound' }
    [void]$acl.RemoveAccessRuleSpecific($rule)
    Set-Acl -Path $path -AclObject $acl -ErrorAction Stop
    return 'Removed'
}

# ===== 07-Plan.ps1 =====
# 07-Plan.ps1
# Der Plan-Modus: fuehrt interaktiv durch alle Entscheidungen, prueft die Umgebung nur lesend
# und erzeugt Config.json und Report.md. Es werden KEINE Aenderungen vorgenommen.

$script:CaroVersion = '1.0.0'

# Startbanner. Sagt deutlich, dass das Skript auf dem CARO-Server laufen muss, und holt die Bestaetigung ein.
function Show-CaroBanner {
    param([Parameter(Mandatory = $true)][string]$Mode)
    Write-Host ''
    Write-Host ('=' * 78) -ForegroundColor Cyan
    Write-CaroMessage -Message ('CARO Service-Account Setup, Version {0}' -f $script:CaroVersion) -Level 'TITLE'
    Write-Host ('=' * 78) -ForegroundColor Cyan
    switch ($Mode) {
        'Plan' { Write-CaroMessage -Message 'Modus PLAN: Fragen stellen und die Umgebung pruefen. Es wird NICHTS geaendert.' -Level 'INFO' }
        'Apply' { Write-CaroMessage -Message 'Modus APPLY: Die geplanten Aenderungen werden durchgefuehrt, nachdem Sie bestaetigt haben.' -Level 'INFO' }
        'Rollback' { Write-CaroMessage -Message 'Modus ROLLBACK: Nur das, was dieses Skript angelegt hat, wird wieder entfernt.' -Level 'INFO' }
    }
    Write-Host ''
    Write-CaroMessage -Message 'WICHTIG: Dieses Skript muss auf dem CARO-SERVER ausgefuehrt werden.' -Level 'WARN'
    Write-CaroMessage -Message ('Erkannter Rechner: {0}' -f [System.Environment]::MachineName) -Level 'WARN'
    Write-CaroMessage -Message 'Der Service-Account wird in die lokalen Administratoren DIESES Rechners eingetragen.' -Level 'INFO'
    Write-Host ''
    return (Read-CaroYesNo -Prompt ('Ist {0} der CARO-Server?' -f [System.Environment]::MachineName) -Default $false)
}

# Waehlt den Modus, wenn er nicht per Parameter uebergeben wurde.
function Select-CaroMode {
    $options = @(
        [pscustomobject]@{ Key = '1'; Label = 'Plan'; Explain = "Fragen stellen, Umgebung pruefen, Config und Report erzeugen.`nAendert nichts." },
        [pscustomobject]@{ Key = '2'; Label = 'Apply'; Explain = "Eine vorhandene Config ausfuehren (mit Zusammenfassung und Bestaetigung)." },
        [pscustomobject]@{ Key = '3'; Label = 'Rollback'; Explain = "Zurueckbauen, was ein frueherer Apply-Lauf angelegt hat." }
    )
    $c = Read-CaroChoice -Title 'Welchen Modus moechten Sie starten?' -Options $options -Default '1'
    switch ($c) { '1' { return 'Plan' } '2' { return 'Apply' } default { return 'Rollback' } }
}

# Uebersicht: Was kommt auf den Ausfuehrenden zu? Wird aus dem Katalog erzeugt und ist daher immer aktuell.
function Show-CaroOverview {
    Write-CaroHeading -Text 'WAS KOMMT AUF SIE ZU'
    Write-CaroMessage -Message 'Dieses Skript legt einen Service-Account fuer CARO an und vergibt die Rechte, die CARO fuer den vollen Funktionsumfang braucht.' -Level 'INFO'
    Write-CaroMessage -Message 'Rechte in Active Directory gelten nur in den OUs, die Sie angeben, inklusive aller Unter-OUs.' -Level 'INFO'
    Write-Host ''
    Write-CaroMessage -Message '1) Active Directory: Je Bereich geben Sie die OU(s) an, in denen CARO arbeiten darf.' -Level 'TITLE'
    foreach ($role in (Get-CaroRoleCatalog)) {
        Write-Host ''
        Write-Host ('   {0}' -f $role.Title) -ForegroundColor White
        Write-Host ('   {0}' -f $role.Purpose) -ForegroundColor Gray
        foreach ($f in $role.Functions) {
            if ($f.Key -eq 'SubOus') { continue }
            Write-Host ('     - {0}' -f $f.Title) -ForegroundColor Gray
        }
    }
    Write-Host ''
    Write-CaroMessage -Message '2) Exchange (optional, On-Premises): Rollengruppe "Organization Management" (Verwalten) oder "View-Only Organization Management" (nur Analysen).' -Level 'INFO'
    Write-CaroMessage -Message '3) Fileserver (optional): lokale Gruppen "Backup Operators" und "Print Operators" (Lesen), zusaetzlich "Administrators" (Verwalten).' -Level 'INFO'
    Write-CaroMessage -Message '4) Immer: Der Account wird lokaler Administrator auf diesem CARO-Server.' -Level 'INFO'
    Write-CaroMessage -Message '5) Kennwort: wird generiert und einmal angezeigt oder von Ihnen eingegeben. Es wird nie gespeichert oder protokolliert.' -Level 'INFO'
    Write-Host ''
    Write-CaroMessage -Message 'Am Ende sehen Sie eine Zusammenfassung aller Aktionen (Was, Wo, Warum). Erst dann entscheiden Sie ueber Apply.' -Level 'INFO'
    Write-CaroMessage -Message 'Nicht Teil dieses Skripts: Observer-Voraussetzungen auf den Domaenencontrollern, Entra ID und Exchange Online (App-Registrierung).' -Level 'INFO'
}

# Zeigt eine Aktionsliste mit Was, Wo, Warum.
function Show-CaroActionSummary {
    param([Parameter(Mandatory = $true)][object[]]$Actions)
    foreach ($a in $Actions) {
        Write-Host ''
        Write-CaroMessage -Message ('[{0}] {1}' -f $a.Id, $a.What) -Level 'TITLE'
        Write-CaroMessage -Message ('       Wo:     {0}' -f $a.Where) -Level 'INFO'
        Write-CaroMessage -Message ('       Warum:  {0}' -f $a.Why) -Level 'INFO'
        if ($a.PlanState -and $a.PlanState -ne 'Unbekannt') {
            Write-CaroMessage -Message ('       Stand:  {0}' -f $a.PlanState) -Level 'INFO'
        }
    }
}

# Uebergeordnetes Objekt eines Distinguished Name (fuer uebernommene Accounts).
function Get-CaroParentDn {
    param([Parameter(Mandatory = $true)][string]$Dn)
    if ($Dn -match '^(?:\\.|[^,\\])+,(.*)$') { return $Matches[1] }
    return ''
}

# Fragt eine OU (oder mehrere) ab. Eingabe OHNE Domaenenteil, von der tiefsten OU nach oben, z. B. OU=Service,OU=Accounts.
# Die Domaene wird automatisch ergaenzt. Liefert die geprueften, vollstaendigen Distinguished Names.
function Read-CaroOuInput {
    param(
        [Parameter(Mandatory = $true)][string]$Prompt,
        [string]$DefaultDn = '',
        [switch]$Multiple,
        [switch]$AllowEmpty
    )
    $dom = Get-CaroDomainInfo
    Write-CaroMessage -Message ('Eingabe ohne Domaenenteil, von der tiefsten OU nach oben, z. B. OU=Service,OU=Accounts. Die Domaene {0} ({1}) wird automatisch ergaenzt.' -f $dom.DnsRoot, $dom.Dn) -Level 'INFO'
    if ($Multiple) { Write-CaroMessage -Message 'Mehrere OUs koennen mit Semikolon getrennt eingegeben werden.' -Level 'INFO' }
    $default = ''
    if ($DefaultDn) { $default = ConvertTo-CaroShortOu -Dn $DefaultDn -DomainDn $dom.Dn }
    $validator = {
        param($v)
        $parts = @($v -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        if (-not $Multiple -and $parts.Count -gt 1) { return 'Bitte nur eine OU angeben.' }
        foreach ($part in $parts) {
            $full = ConvertTo-CaroOuDn -Text $part -DomainDn $dom.Dn
            if (-not (Test-CaroDnFormat -Dn $full)) { return ("'{0}' ist keine gueltige OU-Angabe. Beispiel: OU=Service,OU=Accounts (ohne DC-Teil)" -f $part) }
            if (-not (Get-CaroOuDn -Dn $full)) { return ("Die OU '{0}' wurde im AD nicht gefunden." -f $full) }
        }
        return $null
    }
    $answer = Read-CaroText -Prompt $Prompt -Default $default -Validator $validator -AllowEmpty:$AllowEmpty
    $result = @()
    foreach ($part in ($answer -split ';')) {
        $t = $part.Trim()
        if (-not $t) { continue }
        $canon = Get-CaroOuDn -Dn (ConvertTo-CaroOuDn -Text $t -DomainDn $dom.Dn)
        if ($result -notcontains $canon) { $result += $canon }
    }
    return $result
}

# Account-Daten abfragen, einschliesslich Umgang mit einem bereits vorhandenen Account.
function Read-CaroAccountSettings {
    Write-CaroHeading -Text 'SERVICE-ACCOUNT'
    $samValidator = {
        param($v)
        if ($v -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,19}$') {
            return 'Ungueltig. Erlaubt sind Buchstaben, Ziffern, Punkt, Unterstrich und Bindestrich, hoechstens 20 Zeichen.'
        }
        return $null
    }
    $sam = Read-CaroText -Prompt 'SamAccountName des Service-Accounts' -Default 'sa-service-caro' -Validator $samValidator

    $adopt = $false
    $existing = $null
    while ($true) {
        $existing = Get-CaroExistingAccount -Sam $sam
        if (-not $existing) { break }
        Write-Host ''
        Write-CaroMessage -Message ("Der Account '{0}' existiert bereits." -f $sam) -Level 'WARN'
        Write-CaroMessage -Message ('  DN:           {0}' -f $existing.DistinguishedName) -Level 'INFO'
        Write-CaroMessage -Message ('  Aktiv:        {0}' -f $existing.Enabled) -Level 'INFO'
        Write-CaroMessage -Message ('  Beschreibung: {0}' -f $existing.Description) -Level 'INFO'
        Write-CaroMessage -Message ('  Gruppen:      {0} Mitgliedschaften' -f @($existing.MemberOf).Count) -Level 'INFO'
        Write-CaroMessage -Message 'Uebernehmen heisst: Es werden nur fehlende Rechte ergaenzt. Kennwort und Attribute bleiben unveraendert. Ein Rollback loescht den Account NICHT.' -Level 'INFO'
        if (Read-CaroYesNo -Prompt 'Vorhandenen Account uebernehmen?' -Default $false) { $adopt = $true; break }
        $sam = Read-CaroText -Prompt 'Anderer SamAccountName' -Validator $samValidator
    }

    $result = @{
        Sam                  = $sam
        DisplayName          = $sam
        Description          = ''
        TargetOu             = ''
        Adopt                = $adopt
        PasswordMode         = 'Ask'
        PasswordNeverExpires = $false
    }

    if ($adopt) {
        $result.DisplayName = [string]$existing.Name
        $result.Description = [string]$existing.Description
        $result.TargetOu = Get-CaroParentDn -Dn $existing.DistinguishedName
        return $result
    }

    $result.DisplayName = Read-CaroText -Prompt 'Anzeigename' -Default $sam
    $result.Description = Read-CaroText -Prompt 'Beschreibung' -Default 'Service-Account fuer CARO-Suite'
    $result.TargetOu = @(Read-CaroOuInput -Prompt 'OU, in der der Account angelegt wird')[0]

    $pwOptions = @(
        [pscustomobject]@{ Key = '1'; Label = 'Kennwort generieren'; Explain = "Ein starkes Zufallskennwort wird erzeugt und genau EINMAL am Bildschirm angezeigt.`nSie tragen es danach in CARO bzw. Ihren Passwort-Tresor ein." },
        [pscustomobject]@{ Key = '2'; Label = 'Kennwort selbst eingeben'; Explain = "Sie geben das Kennwort verdeckt ein und wiederholen es zur Kontrolle." }
    )
    $pw = Read-CaroChoice -Title 'Wie soll das Kennwort des Service-Accounts entstehen? (Es wird nie gespeichert oder protokolliert.)' -Options $pwOptions -Default '1'
    if ($pw -eq '1') { $result.PasswordMode = 'Generate' } else { $result.PasswordMode = 'Manual' }

    Write-Host ''
    Write-CaroMessage -Message 'Laeuft das Kennwort nie ab, bricht CARO nicht ploetzlich weg, wenn die Kennwortgueltigkeit endet. Dafuer muss das Kennwort bewusst von Ihnen gewechselt werden.' -Level 'INFO'
    $result.PasswordNeverExpires = Read-CaroYesNo -Prompt 'Kennwort laeuft nie ab?' -Default $true
    return $result
}

# Basis-OU fuer Vorschlaege (optional).
function Read-CaroBaseOu {
    Write-Host ''
    Write-CaroMessage -Message 'Optional: Wenn alle CARO-OUs unter einer gemeinsamen OU liegen (z. B. OU=CARO), schlage ich die Unter-OUs "Benutzer", "Gruppen" und "Deaktivierte Benutzer" vor.' -Level 'INFO'
    $base = @(Read-CaroOuInput -Prompt 'Basis-OU (Enter = keine)' -AllowEmpty)
    if ($base.Count -eq 0) { return '' }
    return $base[0]
}

# Zeigt die Funktionen eines Bereichs mit Erklaerung und dem dafuer vergebenen Recht.
function Show-CaroFunctionList {
    param(
        [Parameter(Mandatory = $true)][object[]]$Functions,
        [switch]$Numbered
    )
    $i = 0
    foreach ($f in $Functions) {
        $i++
        if ($Numbered) { $mark = '[{0}]' -f $i } else { $mark = '-' }
        Write-Host ('  {0} {1}' -f $mark, $f.Title) -ForegroundColor White
        Write-Host ('      {0}' -f $f.Explain) -ForegroundColor Gray
    }
}

# Nummernauswahl aus einer zuvor angezeigten, nummerierten Liste (Anpassen-Profil). Liefert die gewaehlten Schluessel.
function Read-CaroFunctionSelection {
    param(
        [Parameter(Mandatory = $true)][object[]]$Functions
    )
    while ($true) {
        $answer = (Read-CaroInput -Prompt 'Nummern der gewuenschten Funktionen, getrennt durch Komma (Enter = alle)').Trim()
        if (-not $answer) { return @($Functions | ForEach-Object { $_.Key }) }
        $keys = @()
        $bad = $false
        foreach ($part in ($answer -split '[,; ]+')) {
            if (-not $part) { continue }
            $n = 0
            if ([int]::TryParse($part, [ref]$n) -and $n -ge 1 -and $n -le $Functions.Count) {
                $k = $Functions[$n - 1].Key
                if ($keys -notcontains $k) { $keys += $k }
            }
            else { $bad = $true }
        }
        if ($bad -or $keys.Count -eq 0) {
            Write-CaroMessage -Message ('Ungueltige Eingabe. Bitte Nummern von 1 bis {0} angeben.' -f $Functions.Count) -Level 'WARN'
            continue
        }
        return $keys
    }
}

# OUs fuer eine Rolle abfragen: bestimmte OUs (mit Schleife) oder die ganze Domaene.
function Read-CaroOuTargets {
    param(
        [Parameter(Mandatory = $true)]$Role,
        [string]$BaseOu = '',
        [bool]$Dangerous = $false
    )
    $options = @(
        [pscustomobject]@{ Key = '1'; Label = 'Bestimmte OUs'; Explain = "Die Rechte gelten nur in den OUs, die Sie angeben, und allen darunterliegenden Objekten." },
        [pscustomobject]@{ Key = '2'; Label = 'Ganze Domaene'; Explain = "ACHTUNG: Die Rechte gelten fuer ALLE passenden Objekte der gesamten Domaene." }
    )
    $dom = Get-CaroDomainInfo
    while ($true) {
        $scope = Read-CaroChoice -Title ('{0}: Wo darf CARO arbeiten?' -f $role.Title) -Options $options -Default '1'
        if ($scope -eq '2') {
            Write-CaroMessage -Message ('Sie waehlen die ganze Domaene ({0}).' -f $dom.Dn) -Level 'WARN'
            $ok = Read-CaroYesNo -Prompt 'Wirklich fuer die ganze Domaene?' -Default $false
            if ($ok -and $Dangerous) {
                Write-CaroMessage -Message 'Dieser Bereich enthaelt Anlegen, Loeschen oder Verschieben von Benutzern. Domaenenweit kann CARO dann jedes Benutzerkonto der Domaene loeschen.' -Level 'WARN'
                $ok = Read-CaroYesNo -Prompt 'Das gilt wirklich fuer die gesamte Domaene?' -Default $false
            }
            if (-not $ok) { continue }
            return @{ Targets = @($dom.Dn); DomainWide = $true }
        }
        break
    }

    $targets = @()
    $default = ''
    if ($BaseOu -and $role.BaseSuffix) {
        $cand = 'OU={0},{1}' -f $role.BaseSuffix, $BaseOu
        if (Get-CaroOuDn -Dn $cand) { $default = $cand }
    }
    Write-CaroMessage -Message $role.Question -Level 'INFO'
    while ($true) {
        foreach ($dn in @(Read-CaroOuInput -Prompt 'OU' -DefaultDn $default -Multiple)) {
            if ($targets -notcontains $dn) { $targets += $dn }
        }
        $default = ''
        Write-CaroMessage -Message ('Bisher fuer {0}: {1}' -f $role.Title, ($targets -join '; ')) -Level 'INFO'
        if (-not (Read-CaroYesNo -Prompt 'Weitere OU hinzufuegen?' -Default $false)) { break }
    }
    return @{ Targets = @($targets); DomainWide = $false }
}

# Fragt alle AD-Rollen ab.
function Read-CaroRoleSettings {
    param([Parameter(Mandatory = $true)][string]$Profile)
    Write-CaroHeading -Text 'ACTIVE DIRECTORY: WO DARF CARO ARBEITEN?'
    $baseOu = Read-CaroBaseOu
    $roles = @{}
    $subOus = $false

    foreach ($role in (Get-CaroRoleCatalog)) {
        Write-Host ''
        Write-Host ('-' * 78) -ForegroundColor DarkCyan
        Write-CaroMessage -Message $role.Title.ToUpper() -Level 'TITLE'
        Write-CaroMessage -Message $role.Purpose -Level 'INFO'

        if ($role.Key -eq 'MembershipOU') {
            $uo = $roles['UserOU']
            if (-not $uo -or -not $uo.Enabled -or (@($uo.Functions) -notcontains 'CreateUser')) { continue }
        }

        # Erst zeigen, was CARO dafuer bekommt, danach fragen: Die Zuordnung steht direkt vor der Frage.
        $selectable = @($role.Functions | Where-Object { $_.Key -ne 'SubOus' })
        Write-Host ''
        Write-CaroMessage -Message 'Dafuer bekommt der Service-Account diese Rechte:' -Level 'INFO'
        Show-CaroFunctionList -Functions $selectable -Numbered:($Profile -eq 'Custom')
        Write-Host ''

        if ($role.Key -eq 'MembershipOU') {
            $ask = 'Sollen neue Benutzer beim Anlegen automatisch in Gruppen eingetragen werden, die AUSSERHALB der Gruppen-OU liegen (mit den oben genannten Rechten)?'
            $use = Read-CaroYesNo -Prompt $ask -Default $false
        }
        else {
            $use = Read-CaroYesNo -Prompt $role.Ask -Default $true
        }
        if (-not $use) {
            $roles[$role.Key] = @{ Enabled = $false; Targets = @(); DomainWide = $false; Functions = @() }
            continue
        }

        if ($Profile -eq 'Custom') {
            $keys = @(Read-CaroFunctionSelection -Functions $selectable)
        }
        else {
            $keys = @($selectable | ForEach-Object { $_.Key })
        }

        if ($role.Key -eq 'GroupOU' -and ($keys -contains 'CreateGroup')) {
            Write-Host ''
            Write-CaroMessage -Message 'Smart Permissions kann pro Fileserver eine eigene Unter-OU in der Gruppen-OU anlegen (Einstellung "Unter-OU mit dem Server-Namen"). Dafuer braucht der Account zusaetzlich das Recht, OUs anzulegen und zu loeschen.' -Level 'INFO'
            if (Read-CaroYesNo -Prompt 'Legt CARO Unter-OUs in der Gruppen-OU an?' -Default $false) {
                $keys += 'SubOus'
                $subOus = $true
            }
        }

        $dangerous = $false
        foreach ($k in $keys) { if ($k -in @('CreateUser', 'DeleteUser', 'MoveUser', 'ReceiveUsers')) { $dangerous = $true } }
        $t = Read-CaroOuTargets -Role $role -BaseOu $baseOu -Dangerous $dangerous
        $roles[$role.Key] = @{ Enabled = $true; Targets = @($t.Targets); DomainWide = [bool]$t.DomainWide; Functions = @($keys) }
    }
    return @{ Roles = $roles; SubOus = $subOus }
}

# Braucht irgendeine gewaehlte Funktion Benutzer-Eigenschaften (dann ist die Attribut-Strategie zu waehlen)?
function Test-CaroNeedsAttributeChoice {
    param([Parameter(Mandatory = $true)]$Roles)
    foreach ($role in (Get-CaroRoleCatalog)) {
        $rs = $null
        if ($Roles -is [System.Collections.IDictionary]) { if ($Roles.Contains($role.Key)) { $rs = $Roles[$role.Key] } }
        if (-not $rs -or -not $rs.Enabled) { continue }
        foreach ($f in $role.Functions) {
            if (@($rs.Functions) -notcontains $f.Key) { continue }
            foreach ($s in $f.Specs) { if ($s.Kind -eq 'Props' -and $s.Class -eq 'user') { return $true } }
        }
    }
    return $false
}

# Attribut-Strategie: wird IMMER ausdruecklich gefragt, ohne Standard.
# Liefert $null, wenn der Ausfuehrende die Attributliste erst anpassen moechte.
function Read-CaroAttributeStrategy {
    Write-CaroHeading -Text 'BENUTZERATTRIBUTE'
    Write-CaroMessage -Message 'Fuer das Aendern von Benutzer-Eigenschaften gibt es zwei Wege. Bitte entscheiden Sie bewusst.' -Level 'INFO'
    $options = @(
        [pscustomobject]@{ Key = '1'; Label = 'Alle Eigenschaften (Write All Properties)'; Explain = "CARO kann jede Eigenschaft der Benutzer aendern. Volle Funktionalitaet.`nAUCH sicherheitsrelevante Eigenschaften (z. B. userAccountControl, Gruppenzugehoerigkeit ueber primaryGroupID) sind dann beschreibbar." },
        [pscustomobject]@{ Key = '2'; Label = 'Nur die Attributliste (Property-specific)'; Explain = "Nur die Eigenschaften aus der Attributliste (CARO-AD-Attributes.json bzw. eingebettete Liste) sind beschreibbar. Weniger Rechte.`nACHTUNG: Je nach Auswahl koennen einige CARO-Funktionen NICHT funktionieren, wenn ein von CARO benoetigtes Attribut in der Liste fehlt." }
    )
    $c = Read-CaroChoice -Title 'Wie sollen Benutzer-Eigenschaften freigegeben werden?' -Options $options
    if ($c -eq '1') {
        Write-CaroMessage -Message 'Gewaehlt: Alle Eigenschaften. Die Rechte gelten fuer alle Benutzer in den angegebenen OUs.' -Level 'WARN'
        return @{ Mode = 'All'; FileAttributes = @() }
    }
    $file = Read-CaroAttributeFile
    Write-Host ''
    Write-CaroMessage -Message 'ACHTUNG: Je nach Auswahl koennen einige CARO-Funktionen nicht funktionieren, wenn ein benoetigtes Attribut fehlt.' -Level 'WARN'
    Write-CaroMessage -Message ('Attributliste ({0} Attribute) aus: {1}' -f $file.Attributes.Count, $file.Path) -Level 'INFO'
    Write-CaroMessage -Message ('  ' + ($file.Attributes -join ', ')) -Level 'INFO'
    Write-CaroMessage -Message ('Zusaetzlich fuegt das Skript fuer die gewaehlten Funktionen automatisch hinzu: {0}' -f ($file.RequiredAttrs -join ', ')) -Level 'INFO'
    if (-not (Read-CaroYesNo -Prompt 'Mit dieser Liste fortfahren?' -Default $true)) {
        if ($file.Embedded) {
            try {
                Write-CaroTextFile -Path $file.FilePath -Text $file.Text
                Write-CaroMessage -Message ('Die eingebettete Liste wurde als Vorlage abgelegt: {0}' -f $file.FilePath) -Level 'INFO'
                Write-CaroMessage -Message 'Bitte diese Datei anpassen und den Plan danach neu starten. Sie hat Vorrang vor der eingebetteten Liste.' -Level 'WARN'
            }
            catch {
                Write-CaroMessage -Message ('Die Vorlage konnte nicht geschrieben werden: {0}' -f $_.Exception.Message) -Level 'WARN'
            }
        }
        else {
            Write-CaroMessage -Message ('Bitte diese Datei anpassen und den Plan danach neu starten: {0}' -f $file.Path) -Level 'WARN'
        }
        return $null
    }
    return @{ Mode = 'List'; FileAttributes = @($file.Attributes) }
}

# Exchange-Auswahl (On-Premises).
function Read-CaroExchangeChoice {
    param([Parameter(Mandatory = $true)][string]$Profile)
    Write-CaroHeading -Text 'EXCHANGE (ON-PREMISES)'
    Write-CaroMessage -Message 'Hinweis: Exchange Online und Entra ID werden in CARO ueber die App-Registrierung "CARO-Suite M365 Connector" angebunden, nicht ueber dieses Skript.' -Level 'INFO'
    $default = '2'
    if ($Profile -eq 'Custom') { $default = '1' }
    $options = @(
        [pscustomobject]@{ Key = '1'; Label = 'Kein Exchange'; Explain = 'Es wird nichts in Exchange geaendert.' },
        [pscustomobject]@{ Key = '2'; Label = "Management (Rollengruppe 'Organization Management')"; Explain = "CARO kann Exchange verwalten: Postfaecher aktivieren oder erstellen, Abwesenheitsnotizen,`nVollzugriff, Senden-als, Limits, SMTP-Adressen. Der Account wird Mitglied der Rollengruppe." },
        [pscustomobject]@{ Key = '3'; Label = "Read-Only (Rollengruppe 'View-Only Organization Management')"; Explain = "Nur Lesen: CARO kann Exchange analysieren, aber NICHT verwalten.`nOb Read-Only fuer alle CARO-Analysen reicht, ist nicht belegt." }
    )
    while ($true) {
        $c = Read-CaroChoice -Title 'Soll der Account in Exchange berechtigt werden?' -Options $options -Default $default
        if ($c -eq '1') { return 'None' }
        $mode = 'Management'
        if ($c -eq '3') { $mode = 'ReadOnly' }
        $checks = Test-CaroPrerequisites -Areas @('Exchange') | Where-Object { $_.Name -like 'Exchange*' }
        if (-not (Show-CaroPrerequisites -Results @($checks))) {
            Write-CaroMessage -Message 'Exchange kann nicht eingerichtet werden. Bitte waehlen Sie "Kein Exchange" oder stellen Sie die Voraussetzung her und starten Sie den Plan neu.' -Level 'ERROR'
            continue
        }
        $roleGroup = $script:CaroExchangeRoleGroup[$mode]
        if (-not (Test-CaroExchangeRoleGroup -RoleGroup $roleGroup)) {
            Write-CaroMessage -Message ("Die Rollengruppe '{0}' existiert in dieser Exchange-Umgebung nicht. Bitte eine andere Option waehlen." -f $roleGroup) -Level 'ERROR'
            continue
        }
        return $mode
    }
}

# Fileserver-Auswahl.
function Read-CaroFileserverChoice {
    param([Parameter(Mandatory = $true)][string]$Profile)
    Write-CaroHeading -Text 'FILESERVER'
    $default = '3'
    if ($Profile -eq 'Custom') { $default = '1' }
    $options = @(
        [pscustomobject]@{ Key = '1'; Label = 'Kein Fileserver'; Explain = 'Es wird auf keinem Fileserver etwas geaendert.' },
        [pscustomobject]@{ Key = '2'; Label = 'Lesen'; Explain = "Der Account wird in 'Backup Operators' und 'Print Operators' des Fileservers aufgenommen.`nCARO kann Berechtigungen und Freigaben (Share-Permissions) auslesen." },
        [pscustomobject]@{ Key = '3'; Label = 'Verwalten (Lesen und Schreiben)'; Explain = "Zusaetzlich lokale 'Administrators' des Fileservers. Damit kann CARO Ordner anlegen und loeschen,`nBesitzer aendern, Vererbung schalten und Zugriffsrechte aendern. Einzelrechte pro Ordner reichen dafuer nicht aus." }
    )
    $c = Read-CaroChoice -Title 'Soll der Account auf Fileservern berechtigt werden?' -Options $options -Default $default
    if ($c -eq '1') { return @{ Mode = 'None'; Servers = @() } }
    $mode = 'Read'
    if ($c -eq '3') { $mode = 'Manage' }

    $validator = {
        param($v)
        $names = @($v -split '[,; ]+' | Where-Object { $_ })
        if ($names.Count -eq 0) { return 'Bitte mindestens einen Server angeben.' }
        foreach ($n in $names) {
            if ($n -notmatch '^[A-Za-z0-9._-]+$') { return ("'{0}' ist kein gueltiger Servername." -f $n) }
            $chk = Test-CaroPrerequisites -FileServers @($n) | Where-Object { $_.Name -like 'Fileserver*' }
            if (-not $chk.Ok) { return ("Server '{0}' ist nicht erreichbar: {1}" -f $n, $chk.Detail) }
        }
        return $null
    }
    $answer = Read-CaroText -Prompt 'Fileserver (Namen durch Komma oder Leerzeichen trennen)' -Validator $validator
    $servers = @($answer -split '[,; ]+' | Where-Object { $_ } | Select-Object -Unique)
    return @{ Mode = $mode; Servers = $servers }
}

# Ermittelt fuer jede Aktion, ob sie schon besteht (nur lesend), und sammelt Warnungen.
function Add-CaroPlanState {
    param(
        [Parameter(Mandatory = $true)][object[]]$Actions,
        [Parameter(Mandatory = $true)][hashtable]$Settings
    )
    $warnings = New-Object System.Collections.ArrayList
    $sam = $Settings.Account.Sam
    $existing = Get-CaroExistingAccount -Sam $sam
    $sid = $null
    if ($existing) { $sid = ConvertTo-CaroSid -Value $existing.SID.Value }

    foreach ($a in $Actions) {
        try {
            switch ($a.Type) {
                'CreateAccount' {
                    if ($existing) { $a.PlanState = 'Vorhanden' } else { $a.PlanState = 'Neu' }
                }
                'AddLocalGroupMember' {
                    # Neuer Account: kann noch in keiner Gruppe sein, deshalb nur die Gruppe pruefen und die Mitglieder
                    # nicht auflisten (Windows protokolliert jede Auflistung als Sicherheitsereignis).
                    $op = 'Test'
                    if (-not $existing) { $op = 'Exists' }
                    $r = Invoke-CaroLocalGroup -Computer $a.Params.Computer -GroupSid $a.Params.GroupSid -Sam $sam -Operation $op
                    switch ($r.Status) {
                        'IsMember' { $a.PlanState = 'Vorhanden' }
                        'NotMember' { $a.PlanState = 'Neu' }
                        'Exists' { $a.PlanState = 'Neu' }
                        'GroupMissing' {
                            $a.PlanState = 'Gruppe fehlt'
                            [void]$warnings.Add(('{0}: {1}' -f $a.Where, $r.Message))
                        }
                        default { $a.PlanState = 'Unbekannt'; [void]$warnings.Add(('{0}: {1}' -f $a.Where, $r.Message)) }
                    }
                }
                'AddExchangeRoleGroupMember' {
                    $s = Invoke-CaroExchangeMember -RoleGroup $a.Params.RoleGroup -Sam $sam -Operation 'Test'
                    if ($s -eq 'IsMember') { $a.PlanState = 'Vorhanden' } else { $a.PlanState = 'Neu' }
                    foreach ($other in $script:CaroExchangeRoleGroup.Values) {
                        if ($other -ne $a.Params.RoleGroup) {
                            $o = Invoke-CaroExchangeMember -RoleGroup $other -Sam $sam -Operation 'Test'
                            if ($o -eq 'IsMember') { [void]$warnings.Add(("Der Account ist bereits Mitglied der Exchange-Rollengruppe '{0}'. Das Skript entfernt nichts." -f $other)) }
                        }
                    }
                }
                'GrantAd' {
                    if ($sid) { $a.PlanState = Get-CaroAdActionState -Action $a -Sid $sid } else { $a.PlanState = 'Neu' }
                }
            }
        }
        catch {
            $a.PlanState = 'Unbekannt'
            [void]$warnings.Add(('{0}: Zustand konnte nicht geprueft werden: {1}' -f $a.Id, $_.Exception.Message))
        }
    }
    return @($warnings)
}

# Der komplette Plan. Liefert den Pfad der Config-Datei oder $null bei Abbruch.
function Invoke-CaroPlan {
    $checks = Test-CaroPrerequisites
    Write-CaroHeading -Text 'VORAUSSETZUNGEN'
    if (-not (Show-CaroPrerequisites -Results $checks)) {
        Write-CaroMessage -Message 'Der Plan wird abgebrochen, weil Voraussetzungen fehlen. Es wurde nichts geaendert.' -Level 'ERROR'
        return $null
    }

    Show-CaroOverview

    $profileOptions = @(
        [pscustomobject]@{ Key = '1'; Label = 'Voller CARO-Umfang (empfohlen)'; Explain = "Alle Funktionen der oben gezeigten Bereiche. Die Rechte gelten nur in den OUs, die Sie angeben." },
        [pscustomobject]@{ Key = '2'; Label = 'Anpassen'; Explain = "Sie waehlen je Bereich einzelne Funktionen. Fuer Fortgeschrittene." }
    )
    $p = Read-CaroChoice -Title 'Welches Profil moechten Sie verwenden?' -Options $profileOptions -Default '1'
    if ($p -eq '1') { $profileName = 'Full' } else { $profileName = 'Custom' }
    Write-CaroLog -Level 'INFO' -Message ('Profil: {0}' -f $profileName)

    $account = Read-CaroAccountSettings

    $rs = Read-CaroRoleSettings -Profile $profileName
    $attrMode = ''
    $fileAttrs = @()
    if (Test-CaroNeedsAttributeChoice -Roles $rs.Roles) {
        $strategy = Read-CaroAttributeStrategy
        if (-not $strategy) { return $null }
        $attrMode = $strategy.Mode
        $fileAttrs = @($strategy.FileAttributes)
    }

    $exchange = Read-CaroExchangeChoice -Profile $profileName
    $fs = Read-CaroFileserverChoice -Profile $profileName

    $enabledRoles = @($rs.Roles.Values | Where-Object { $_.Enabled })
    if ($enabledRoles.Count -eq 0 -and $exchange -eq 'None' -and $fs.Mode -eq 'None') {
        Write-CaroMessage -Message 'Es wurde keine Funktion gewaehlt. Es gibt nichts zu planen.' -Level 'ERROR'
        return $null
    }

    $settings = @{
        Profile        = $profileName
        Account        = $account
        AttributeMode  = $attrMode
        FileAttributes = $fileAttrs
        Roles          = $rs.Roles
        SubOus         = [bool]$rs.SubOus
        Exchange       = $exchange
        Fileserver     = $fs
    }
    if (-not $settings.AttributeMode) { $settings.AttributeMode = 'List' }

    Write-CaroHeading -Text 'ZUSTAND PRUEFEN (nur lesend)'
    $actions = New-CaroActionList -Settings $settings
    $warnings = @(Add-CaroPlanState -Actions $actions -Settings $settings)
    try {
        $dcs = @(Find-CaroDomainControllers -Actions $actions)
        $warnings += @(Get-CaroDomainControllerWarnings -Actions $actions -DomainControllers $dcs)
    }
    catch {
        Write-CaroLog -Level 'WARN' -Message ('Domaenencontroller-Pruefung nicht moeglich: {0}' -f $_.Exception.Message)
    }
    $config = New-CaroConfig -Settings $settings -Actions $actions -Warnings $warnings

    Write-CaroHeading -Text 'ZUSAMMENFASSUNG DES PLANS'
    Show-CaroActionSummary -Actions $actions
    if ($warnings.Count -gt 0) {
        Write-Host ''
        foreach ($w in $warnings) { Write-CaroMessage -Message ('WARNUNG: {0}' -f $w) -Level 'WARN' }
    }

    $configPath = New-CaroOutputPath -Type 'Config' -Extension 'json'
    Write-CaroTextFile -Path $configPath -Text (ConvertTo-Json -InputObject $config -Depth 12)
    $reportPath = New-CaroOutputPath -Type 'Report' -Extension 'md'
    Write-CaroTextFile -Path $reportPath -Text (ConvertTo-CaroReportMarkdown -Config ([pscustomobject]$config))
    Write-CaroLog -Level 'AKTION' -Message 'Plan erzeugt' -Object $configPath -Result 'OK'

    Write-Host ''
    Write-CaroMessage -Message 'Plan abgeschlossen. Es wurde nichts geaendert.' -Level 'OK'
    Write-CaroMessage -Message ('Config: {0}' -f $configPath) -Level 'OK'
    Write-CaroMessage -Message ('Report: {0}' -f $reportPath) -Level 'OK'
    return $configPath
}

# ===== 08-Apply.ps1 =====
# 08-Apply.ps1
# Der Apply-Modus: Config einlesen, Zusammenfassung zeigen, ausdruecklich bestaetigen lassen,
# Aktionen der Reihe nach ausfuehren und das Ergebnis in Result.json festhalten.
# Bei einem Fehler stoppt Apply sofort. Was bis dahin erledigt wurde, steht in der Result-Datei
# und kann mit -Mode Rollback zurueckgebaut werden.

# Laesst den Ausfuehrenden eine der juengsten Dateien eines Typs waehlen (oder einen Pfad eingeben).
function Select-CaroInputFile {
    param(
        [Parameter(Mandatory = $true)][string]$Pattern,
        [Parameter(Mandatory = $true)][string]$Title
    )
    $files = @(Get-ChildItem -LiteralPath (Get-CaroLogFolder) -Filter $Pattern -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 5)
    $options = @()
    $i = 0
    foreach ($f in $files) {
        $i++
        $options += [pscustomobject]@{ Key = [string]$i; Label = $f.Name; Explain = ('geaendert: {0}' -f $f.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')) }
    }
    $options += [pscustomobject]@{ Key = 'P'; Label = 'Anderen Pfad eingeben'; Explain = '' }
    $default = ''
    if ($files.Count -gt 0) { $default = '1' }
    $c = Read-CaroChoice -Title $Title -Options $options -Default $default
    if ($c -eq 'P') {
        $path = Read-CaroText -Prompt 'Pfad der Datei' -Validator { param($v) if (-not (Test-Path -LiteralPath $v)) { 'Die Datei wurde nicht gefunden.' } else { $null } }
        return $path
    }
    return $files[[int]$c - 1].FullName
}

# Fragt das Kennwort des neuen Accounts ab bzw. erzeugt es. Der Klartext wird nie gespeichert oder protokolliert.
function Get-CaroAccountPassword {
    param([Parameter(Mandatory = $true)][string]$Mode)
    if ($Mode -eq 'Ask') {
        $options = @(
            [pscustomobject]@{ Key = '1'; Label = 'Kennwort generieren'; Explain = 'Wird einmal angezeigt.' },
            [pscustomobject]@{ Key = '2'; Label = 'Kennwort selbst eingeben'; Explain = '' }
        )
        $c = Read-CaroChoice -Title 'Wie soll das Kennwort des neuen Accounts entstehen?' -Options $options -Default '1'
        if ($c -eq '1') { $Mode = 'Generate' } else { $Mode = 'Manual' }
    }
    if ($Mode -eq 'Manual') { return (Read-CaroPasswordTwice) }

    $plain = New-CaroPassword -Length 24
    Write-Host ''
    Write-Host ('*' * 78) -ForegroundColor Yellow
    Write-Host 'GENERIERTES KENNWORT (wird nur jetzt EINMAL angezeigt, nicht gespeichert, nicht protokolliert):' -ForegroundColor Yellow
    Write-Host ''
    Write-Host ('    ' + $plain) -ForegroundColor White
    Write-Host ''
    Write-Host ('*' * 78) -ForegroundColor Yellow
    Write-CaroLog -Level 'INFO' -Message 'Kennwort generiert und angezeigt (Wert wird nicht protokolliert).'
    $null = Read-CaroInput -Prompt 'Bitte notieren Sie das Kennwort jetzt. Mit Enter wird die Anzeige geloescht'
    $secure = ConvertTo-SecureString -String $plain -AsPlainText -Force
    $plain = $null
    Clear-Host
    return $secure
}

function New-CaroEntry {
    param($Action, [string]$Status, [string]$Message, $Rollback = $null)
    return [ordered]@{
        ActionId = $Action.Id
        Type     = $Action.Type
        What     = $Action.What
        Where    = $Action.Where
        Status   = $Status
        Message  = $Message
        Rollback = $Rollback
    }
}

# Fuehrt eine einzelne Aktion aus. Fehler werden als Status 'Error' zurueckgegeben, nie geworfen.
function Invoke-CaroApplyAction {
    param(
        [Parameter(Mandatory = $true)]$Action,
        [Parameter(Mandatory = $true)][hashtable]$Context,
        [bool]$DryRun = $false
    )
    try {
        $p = $Action.Params
        if ($DryRun) {
            return (New-CaroEntry -Action $Action -Status 'WhatIf' -Message 'WhatIf: Es wurde nichts geaendert.')
        }
        switch ($Action.Type) {
            'CreateAccount' {
                $existing = Get-CaroExistingAccount -Sam $p.Sam
                if ($existing) {
                    if (-not $p.Adopt) {
                        throw ("Der Account '{0}' existiert bereits, ist im Plan aber als neu vorgesehen. Bitte einen neuen Plan erstellen." -f $p.Sam)
                    }
                    $Context.Sid = ConvertTo-CaroSid -Value $existing.SID.Value
                    return (New-CaroEntry -Action $Action -Status 'AlreadyPresent' -Message 'Vorhandener Account uebernommen, nichts geaendert.')
                }
                $dom = Get-CaroDomainInfo
                $secure = Get-CaroAccountPassword -Mode $p.PasswordMode
                $params = @{
                    Name                 = $p.DisplayName
                    SamAccountName       = $p.Sam
                    UserPrincipalName    = ('{0}@{1}' -f $p.Sam, $dom.DnsRoot)
                    DisplayName          = $p.DisplayName
                    Description          = $p.Description
                    Path                 = $p.TargetOu
                    AccountPassword      = $secure
                    Enabled              = $true
                    PasswordNeverExpires = [bool]$p.PasswordNeverExpires
                    ChangePasswordAtLogon = $false
                }
                New-ADUser @params -ErrorAction Stop
                $u = Get-ADUser -Identity $p.Sam -ErrorAction Stop
                $Context.Sid = ConvertTo-CaroSid -Value $u.SID.Value
                return (New-CaroEntry -Action $Action -Status 'Created' -Message ('Account angelegt: ' + $u.DistinguishedName) `
                        -Rollback ([ordered]@{ Dn = $u.DistinguishedName; Sid = $u.SID.Value; Sam = $p.Sam }))
            }
            'AddLocalGroupMember' {
                $r = Invoke-CaroLocalGroup -Computer $p.Computer -GroupSid $p.GroupSid -Sam $p.Sam -Operation 'Add'
                switch ($r.Status) {
                    'Added' {
                        return (New-CaroEntry -Action $Action -Status 'Created' -Message ("In '{0}' auf {1} eingetragen." -f $p.GroupLabel, $p.ComputerLabel) `
                                -Rollback ([ordered]@{ Computer = $p.Computer; GroupSid = $p.GroupSid; GroupLabel = $p.GroupLabel; Sam = $p.Sam }))
                    }
                    'AlreadyMember' { return (New-CaroEntry -Action $Action -Status 'AlreadyPresent' -Message 'War bereits Mitglied, nichts geaendert.') }
                    default { throw ("{0}: {1}" -f $r.Status, $r.Message) }
                }
            }
            'AddExchangeRoleGroupMember' {
                $s = Invoke-CaroExchangeMember -RoleGroup $p.RoleGroup -Sam $p.Sam -Operation 'Add'
                if ($s -eq 'Added') {
                    return (New-CaroEntry -Action $Action -Status 'Created' -Message ("In die Rollengruppe '{0}' eingetragen." -f $p.RoleGroup) `
                            -Rollback ([ordered]@{ RoleGroup = $p.RoleGroup; Sam = $p.Sam }))
                }
                return (New-CaroEntry -Action $Action -Status 'AlreadyPresent' -Message 'War bereits Mitglied, nichts geaendert.')
            }
            'GrantAd' {
                if (-not $Context.Sid) {
                    $acc = Get-CaroExistingAccount -Sam $Context.Sam
                    if (-not $acc) { throw ("Der Account '{0}' wurde nicht gefunden." -f $Context.Sam) }
                    $Context.Sid = ConvertTo-CaroSid -Value $acc.SID.Value
                }
                $g = Invoke-CaroGrantAd -Action $Action -Sid $Context.Sid
                if (@($g.Created).Count -gt 0) {
                    return (New-CaroEntry -Action $Action -Status 'Created' -Message ('{0} von {1} Zugriffseintraegen neu gesetzt.' -f @($g.Created).Count, $g.Total) `
                            -Rollback ([ordered]@{ Rules = @($g.Created) }))
                }
                return (New-CaroEntry -Action $Action -Status 'AlreadyPresent' -Message ('Alle {0} Zugriffseintraege waren schon vorhanden.' -f $g.Total))
            }
            default { throw ("Unbekannter Aktionstyp '{0}'." -f $Action.Type) }
        }
    }
    catch {
        return (New-CaroEntry -Action $Action -Status 'Error' -Message $_.Exception.Message)
    }
}

# Der komplette Apply-Lauf. Liefert $true bei vollstaendigem Erfolg.
function Invoke-CaroApply {
    param(
        [string]$ConfigPath = '',
        [bool]$DryRun = $false
    )
    if (-not $ConfigPath) {
        $ConfigPath = Select-CaroInputFile -Pattern '*-CARO-SA-Config.json' -Title 'Welche Config soll ausgefuehrt werden?'
    }
    if (-not (Test-Path -LiteralPath $ConfigPath)) { throw ("Die Config-Datei wurde nicht gefunden: {0}" -f $ConfigPath) }
    Write-CaroLog -Level 'INFO' -Message 'Config geladen' -Object $ConfigPath

    $config = (Read-CaroTextFile -Path $ConfigPath) | ConvertFrom-Json
    $errors = @(Test-CaroConfig -Config $config)
    if ($errors.Count -gt 0) {
        foreach ($e in $errors) { Write-CaroMessage -Message ('Config ungueltig: {0}' -f $e) -Level 'ERROR' }
        return $false
    }

    Write-CaroHeading -Text 'CONFIG'
    Write-CaroMessage -Message ('Konfiguration: {0}' -f $config.ConfigurationId) -Level 'INFO'
    Write-CaroMessage -Message ('Plan erstellt: {0} auf {1} durch {2}' -f $config.PlanId, $config.ComputerName, $config.CreatedBy) -Level 'INFO'
    if ($config.ComputerName -and $config.ComputerName -ne [System.Environment]::MachineName) {
        Write-CaroMessage -Message ('WARNUNG: Der Plan wurde auf {0} erstellt, Sie fuehren Apply auf {1} aus.' -f $config.ComputerName, [System.Environment]::MachineName) -Level 'WARN'
    }
    $sam = $config.Settings.Account.Sam

    $actions = @($config.Actions)
    $areas = @()
    if (@($actions | Where-Object { $_.Type -eq 'AddExchangeRoleGroupMember' }).Count -gt 0) { $areas += 'Exchange' }
    $servers = @($actions | Where-Object { $_.Area -eq 'Fileserver' } | ForEach-Object { $_.Params.Computer } | Select-Object -Unique)
    Write-CaroHeading -Text 'VORAUSSETZUNGEN'
    if (-not (Show-CaroPrerequisites -Results (Test-CaroPrerequisites -Areas $areas -FileServers $servers))) {
        Write-CaroMessage -Message 'Apply wird abgebrochen, weil Voraussetzungen fehlen. Es wurde nichts geaendert.' -Level 'ERROR'
        return $false
    }

    Write-CaroHeading -Text 'ZUSAMMENFASSUNG: DAS WIRD GEAENDERT'
    Show-CaroActionSummary -Actions $actions
    if (@($config.Warnings).Count -gt 0) {
        Write-Host ''
        foreach ($w in @($config.Warnings)) { Write-CaroMessage -Message ('WARNUNG: {0}' -f $w) -Level 'WARN' }
    }
    Write-Host ''
    if ($DryRun) {
        Write-CaroMessage -Message 'WhatIf ist aktiv: Es wird nichts geaendert. Die Result-Datei zeigt, was ausgefuehrt wuerde.' -Level 'WARN'
    }
    else {
        Write-CaroMessage -Message ("Diese {0} Aktionen werden jetzt auf diesem System ausgefuehrt." -f $actions.Count) -Level 'WARN'
        if (-not (Read-CaroConfirmWord -Prompt 'Aenderungen jetzt ausfuehren?' -Word 'JA')) {
            Write-CaroMessage -Message 'Nicht bestaetigt. Es wurde nichts geaendert.' -Level 'WARN'
            return $false
        }
    }

    $executionId = (Get-Date).ToString('o')
    $startedAt = $executionId
    $entries = New-Object System.Collections.ArrayList
    $ctx = @{ Sam = $sam; Sid = $null }
    $failed = $false
    try {
        foreach ($a in $actions) {
            Write-CaroMessage -Message ('[{0}] {1}' -f $a.Id, $a.What) -Level 'TITLE'
            $entry = Invoke-CaroApplyAction -Action $a -Context $ctx -DryRun $DryRun
            [void]$entries.Add($entry)
            switch ($entry.Status) {
                'Created' { Write-CaroMessage -Message ('       OK: {0}' -f $entry.Message) -Level 'OK' }
                'AlreadyPresent' { Write-CaroMessage -Message ('       Bereits vorhanden: {0}' -f $entry.Message) -Level 'INFO' }
                'WhatIf' { Write-CaroMessage -Message ('       {0}' -f $entry.Message) -Level 'INFO' }
                'Error' {
                    Write-CaroMessage -Message ('       FEHLER: {0}' -f $entry.Message) -Level 'ERROR'
                    $failed = $true
                }
            }
            Write-CaroLog -Level 'AKTION' -Message $a.What -Object $a.Where -Result ('{0}: {1}' -f $entry.Status, $entry.Message)
            if ($failed) { break }
        }
    }
    finally {
        $counts = @{ Created = 0; AlreadyPresent = 0; Error = 0; WhatIf = 0; NotExecuted = 0 }
        foreach ($e in $entries) { $counts[$e.Status]++ }
        $counts.NotExecuted = $actions.Count - $entries.Count
        $result = [ordered]@{
            SchemaVersion   = 1
            ExecutionId     = $executionId
            ConfigurationId = $config.ConfigurationId
            PlanId          = $config.PlanId
            ConfigPath      = $ConfigPath
            ComputerName    = [System.Environment]::MachineName
            ExecutedBy      = ('{0}\{1}' -f [System.Environment]::UserDomainName, [System.Environment]::UserName)
            StartedAt       = $startedAt
            FinishedAt      = (Get-Date).ToString('o')
            DryRun          = $DryRun
            Summary         = $counts
            Entries         = @($entries)
        }
        $resultPath = New-CaroOutputPath -Type 'Result' -Extension 'json'
        Write-CaroTextFile -Path $resultPath -Text (ConvertTo-Json -InputObject $result -Depth 12)
        Write-CaroLog -Level 'INFO' -Message 'Result geschrieben' -Object $resultPath
        Write-Host ''
        Write-CaroMessage -Message ('Result: {0}' -f $resultPath) -Level 'INFO'
    }

    Write-CaroMessage -Message ('Neu: {0}, bereits vorhanden: {1}, Fehler: {2}, nicht ausgefuehrt: {3}' -f $counts.Created, $counts.AlreadyPresent, $counts.Error, $counts.NotExecuted) -Level 'INFO'
    if ($failed) {
        Write-CaroMessage -Message 'Apply wurde wegen eines Fehlers beendet. Bereits Erledigtes steht in der Result-Datei und kann mit -Mode Rollback zurueckgebaut werden.' -Level 'ERROR'
        return $false
    }
    if ($DryRun) { Write-CaroMessage -Message 'WhatIf abgeschlossen. Es wurde nichts geaendert.' -Level 'OK' }
    else { Write-CaroMessage -Message 'Apply erfolgreich abgeschlossen.' -Level 'OK' }
    return $true
}

# ===== 09-Rollback.ps1 =====
# 09-Rollback.ps1
# Der Rollback-Modus: baut ausschliesslich zurueck, was ein frueherer Apply-Lauf NEU angelegt hat
# (Status 'Created' in der Result-Datei). Vorhandenes, das nur uebernommen wurde, bleibt unangetastet.
# Reihenfolge: umgekehrt zum Apply. Der Account selbst wird zuletzt geloescht.

function Get-CaroRollbackDescription {
    param([Parameter(Mandatory = $true)]$Entry)
    switch ($Entry.Type) {
        'GrantAd' { return ('{0} Zugriffseintrag/-eintraege entfernen auf {1}' -f @($Entry.Rollback.Rules).Count, $Entry.Where) }
        'AddLocalGroupMember' { return ("Account aus lokaler Gruppe '{0}' entfernen auf {1}" -f $Entry.Rollback.GroupLabel, $Entry.Where) }
        'AddExchangeRoleGroupMember' { return ("Account aus Exchange-Rollengruppe '{0}' entfernen" -f $Entry.Rollback.RoleGroup) }
        'CreateAccount' { return ("Account '{0}' LOESCHEN ({1})" -f $Entry.Rollback.Sam, $Entry.Rollback.Dn) }
        default { return $Entry.What }
    }
}

# Fuehrt den Rueckbau einer einzelnen Result-Eintragung aus. Fehler werden als Status 'Error' zurueckgegeben.
function Invoke-CaroRollbackEntry {
    param(
        [Parameter(Mandatory = $true)]$Entry,
        [bool]$DryRun = $false
    )
    $out = [ordered]@{ ActionId = $Entry.ActionId; Type = $Entry.Type; What = (Get-CaroRollbackDescription -Entry $Entry); Status = ''; Message = '' }
    try {
        if ($DryRun) { $out.Status = 'WhatIf'; $out.Message = 'WhatIf: Es wurde nichts geaendert.'; return $out }
        $rb = $Entry.Rollback
        switch ($Entry.Type) {
            'GrantAd' {
                $removed = 0
                $notFound = 0
                foreach ($rule in @($rb.Rules)) {
                    $s = Invoke-CaroRevokeRule -Info $rule
                    if ($s -eq 'Removed') { $removed++ } else { $notFound++ }
                }
                $out.Status = 'RolledBack'
                $out.Message = '{0} entfernt, {1} waren nicht mehr vorhanden.' -f $removed, $notFound
            }
            'AddLocalGroupMember' {
                $r = Invoke-CaroLocalGroup -Computer $rb.Computer -GroupSid $rb.GroupSid -Sam $rb.Sam -Operation 'Remove'
                switch ($r.Status) {
                    'Removed' { $out.Status = 'RolledBack'; $out.Message = 'Aus der Gruppe entfernt.' }
                    'NotMember' { $out.Status = 'NotFound'; $out.Message = 'War nicht mehr Mitglied.' }
                    default { throw ('{0}: {1}' -f $r.Status, $r.Message) }
                }
            }
            'AddExchangeRoleGroupMember' {
                $s = Invoke-CaroExchangeMember -RoleGroup $rb.RoleGroup -Sam $rb.Sam -Operation 'Remove'
                if ($s -eq 'Removed') { $out.Status = 'RolledBack'; $out.Message = 'Aus der Rollengruppe entfernt.' }
                else { $out.Status = 'NotFound'; $out.Message = 'War nicht mehr Mitglied.' }
            }
            'CreateAccount' {
                $u = $null
                try { $u = Get-ADUser -Identity ([string]$rb.Sid) -ErrorAction Stop } catch { $u = $null }
                if (-not $u) { $out.Status = 'NotFound'; $out.Message = 'Der Account existiert nicht mehr.' }
                elseif ($u.SamAccountName -ine [string]$rb.Sam) {
                    throw ("Die SID gehoert zu '{0}', nicht zu '{1}'. Der Account wird aus Sicherheitsgruenden nicht geloescht." -f $u.SamAccountName, $rb.Sam)
                }
                else {
                    Remove-ADUser -Identity $u.DistinguishedName -Confirm:$false -ErrorAction Stop
                    $out.Status = 'RolledBack'
                    $out.Message = 'Account geloescht.'
                }
            }
            default { throw ("Unbekannter Typ '{0}'." -f $Entry.Type) }
        }
    }
    catch {
        $out.Status = 'Error'
        $out.Message = $_.Exception.Message
    }
    return $out
}

# Der komplette Rollback-Lauf. Liefert $true bei vollstaendigem Erfolg.
function Invoke-CaroRollback {
    param(
        [string]$ResultPath = '',
        [bool]$DryRun = $false
    )
    if (-not $ResultPath) {
        $ResultPath = Select-CaroInputFile -Pattern '*-CARO-SA-Result.json' -Title 'Welcher Apply-Lauf soll zurueckgebaut werden?'
    }
    if (-not (Test-Path -LiteralPath $ResultPath)) { throw ("Die Result-Datei wurde nicht gefunden: {0}" -f $ResultPath) }
    Write-CaroLog -Level 'INFO' -Message 'Result geladen' -Object $ResultPath
    $result = (Read-CaroTextFile -Path $ResultPath) | ConvertFrom-Json
    if ($result.DryRun) {
        Write-CaroMessage -Message 'Diese Result-Datei stammt aus einem WhatIf-Lauf. Es wurde nichts geaendert, also gibt es nichts zurueckzubauen.' -Level 'WARN'
        return $true
    }

    $todo = @($result.Entries | Where-Object { $_.Status -eq 'Created' -and $_.Rollback })
    [array]::Reverse($todo)
    Write-CaroHeading -Text 'ROLLBACK'
    Write-CaroMessage -Message ('Apply-Lauf: {0} (Konfiguration {1})' -f $result.ExecutionId, $result.ConfigurationId) -Level 'INFO'
    if ($todo.Count -eq 0) {
        Write-CaroMessage -Message 'Dieser Lauf hat nichts neu angelegt. Es gibt nichts zurueckzubauen.' -Level 'OK'
        return $true
    }

    $areas = @()
    if (@($todo | Where-Object { $_.Type -eq 'AddExchangeRoleGroupMember' }).Count -gt 0) { $areas += 'Exchange' }
    $servers = @($todo | Where-Object { $_.Type -eq 'AddLocalGroupMember' -and $_.Rollback.Computer -ne '.' } | ForEach-Object { $_.Rollback.Computer } | Select-Object -Unique)
    Write-CaroHeading -Text 'VORAUSSETZUNGEN'
    if (-not (Show-CaroPrerequisites -Results (Test-CaroPrerequisites -Areas $areas -FileServers $servers))) {
        Write-CaroMessage -Message 'Rollback wird abgebrochen, weil Voraussetzungen fehlen. Es wurde nichts geaendert.' -Level 'ERROR'
        return $false
    }

    Write-Host ''
    Write-CaroMessage -Message 'Das wird zurueckgebaut (in dieser Reihenfolge). Nur Neu-Angelegtes wird entfernt, Uebernommenes bleibt bestehen:' -Level 'WARN'
    foreach ($e in $todo) {
        Write-CaroMessage -Message ('  [{0}] {1}' -f $e.ActionId, (Get-CaroRollbackDescription -Entry $e)) -Level 'INFO'
    }
    Write-Host ''
    if ($DryRun) {
        Write-CaroMessage -Message 'WhatIf ist aktiv: Es wird nichts geaendert.' -Level 'WARN'
    }
    elseif (-not (Read-CaroConfirmWord -Prompt 'Rollback jetzt ausfuehren?' -Word 'JA')) {
        Write-CaroMessage -Message 'Nicht bestaetigt. Es wurde nichts geaendert.' -Level 'WARN'
        return $false
    }

    $entries = New-Object System.Collections.ArrayList
    $failed = $false
    foreach ($e in $todo) {
        $r = Invoke-CaroRollbackEntry -Entry $e -DryRun $DryRun
        [void]$entries.Add($r)
        if ($r.Status -eq 'Error') {
            Write-CaroMessage -Message ('  [{0}] FEHLER: {1}' -f $e.ActionId, $r.Message) -Level 'ERROR'
            $failed = $true
        }
        else {
            Write-CaroMessage -Message ('  [{0}] {1}: {2}' -f $e.ActionId, $r.Status, $r.Message) -Level 'OK'
        }
        Write-CaroLog -Level 'AKTION' -Message $r.What -Object $e.Where -Result ('{0}: {1}' -f $r.Status, $r.Message)
    }

    $out = [ordered]@{
        SchemaVersion        = 1
        RolledBackExecutionId = $result.ExecutionId
        ConfigurationId      = $result.ConfigurationId
        RolledBackAt         = (Get-Date).ToString('o')
        RolledBackBy         = ('{0}\{1}' -f [System.Environment]::UserDomainName, [System.Environment]::UserName)
        ComputerName         = [System.Environment]::MachineName
        DryRun               = $DryRun
        Entries              = @($entries)
    }
    $path = New-CaroOutputPath -Type 'Rollback' -Extension 'json'
    Write-CaroTextFile -Path $path -Text (ConvertTo-Json -InputObject $out -Depth 12)
    Write-CaroLog -Level 'INFO' -Message 'Rollback-Ergebnis geschrieben' -Object $path
    Write-CaroMessage -Message ('Rollback-Ergebnis: {0}' -f $path) -Level 'INFO'
    if ($failed) {
        Write-CaroMessage -Message 'Der Rollback ist mit Fehlern beendet. Bitte pruefen Sie die Meldungen und das Log.' -Level 'ERROR'
        return $false
    }
    Write-CaroMessage -Message 'Rollback abgeschlossen.' -Level 'OK'
    return $true
}

#endregion CARO-LIBS

$dryRun = ($WhatIfPreference -eq $true)
$exitCode = 0

# Modus waehlen, falls nicht per Parameter angegeben. Dieser Schritt ist noch nicht im Log (es gibt noch keinen Modus).
if (-not $Mode) {
    $Mode = Select-CaroMode
}

$logPath = Initialize-CaroLog -Mode $Mode
try {
    Write-CaroLog -Level 'INFO' -Message ('Parameter: Mode={0}, ConfigPath={1}, ResultPath={2}, WhatIf={3}' -f $Mode, $ConfigPath, $ResultPath, $dryRun)

    $isCaroServer = Show-CaroBanner -Mode $Mode
    if (-not $isCaroServer) {
        Write-CaroMessage -Message 'Abbruch: Das Skript muss auf dem CARO-Server ausgefuehrt werden. Es wurde nichts geaendert.' -Level 'ERROR'
        $exitCode = 2
    }
    else {
        switch ($Mode) {
            'Plan' {
                $configFile = @(Invoke-CaroPlan)[-1]
                if (-not $configFile -or -not (Test-Path -LiteralPath ([string]$configFile))) {
                    Write-CaroMessage -Message 'Der Plan wurde ohne Ergebnis beendet.' -Level 'WARN'
                    $exitCode = 2
                }
                elseif (Read-CaroYesNo -Prompt 'Jetzt direkt mit Apply fortfahren?' -Default $false) {
                    $logPath = Initialize-CaroLog -Mode 'Apply'
                    $ok = @(Invoke-CaroApply -ConfigPath ([string]$configFile) -DryRun $dryRun)[-1]
                    if (-not $ok) { $exitCode = 1 }
                }
            }
            'Apply' {
                $ok = @(Invoke-CaroApply -ConfigPath $ConfigPath -DryRun $dryRun)[-1]
                if (-not $ok) { $exitCode = 1 }
            }
            'Rollback' {
                $ok = @(Invoke-CaroRollback -ResultPath $ResultPath -DryRun $dryRun)[-1]
                if (-not $ok) { $exitCode = 1 }
            }
        }
    }
}
catch {
    $exitCode = 1
    Write-CaroMessage -Message ('FEHLER: {0}' -f $_.Exception.Message) -Level 'ERROR'
    Write-CaroLog -Level 'ERROR' -Message ('Details: {0}' -f $_.ScriptStackTrace)
}
finally {
    Write-CaroLog -Level 'INFO' -Message ('Lauf beendet. Exitcode={0}' -f $exitCode)
    if ($logPath) { Write-Host ('Log: {0}' -f $logPath) -ForegroundColor Gray }
}
exit $exitCode
