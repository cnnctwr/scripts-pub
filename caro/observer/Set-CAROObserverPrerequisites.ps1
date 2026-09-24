#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Konfiguriert die technischen Voraussetzungen fuer den CUSATUM CARO-AD-Observer
    auf einem Domaenencontroller (Audit-Richtlinien, SACL, Firewall, Event-Log-Readers-Gruppe).

.DESCRIPTION
    Wirkt AUSSCHLIESSLICH auf den lokalen Server, auf dem es ausgefuehrt wird
    (siehe CARO-Observer-Voraussetzungen-de-DE.pdf, Version 2026.9). Fuer mehrere
    Domaenencontroller muss das Script auf jedem einzeln ausgefuehrt werden - die
    SACL-Einstellung muss dagegen nur auf einem DC gesetzt werden, da sie per
    AD-Replikation automatisch verteilt wird.

    Jede einzelne Aenderung wird vor der Ausfuehrung im Klartext angezeigt:
      - was gemacht wird
      - der exakte Befehl/Mechanismus
      - der aktuelle Wert
      - der Zielwert
    und muss vom Anwender einzeln bestaetigt werden ([J]a/[N]ein/[A]lle/[Q]uit).

    Es werden drei Dateien erzeugt:
      - ein Textlog (Verlauf, Fehler, Warnungen)
      - eine JSON-Datei mit den *Ziel*-Einstellungen (strukturiert, vor Ausfuehrung)
      - eine JSON-Backup-Datei mit Original- und neuem Wert je Einstellung

    Mit -RestoreFrom <Backup-Datei> kann das Script erneut aufgerufen werden, um
    alle als 'Geaendert' protokollierten Einstellungen einzeln (wieder mit
    Bestaetigung) auf den urspruenglichen Wert zurueckzusetzen.

.PARAMETER ServiceAccount
    Domain\Benutzername des CARO-Servicekontos, das der lokalen Gruppe
    "Event Log Readers" hinzugefuegt werden soll. Wird interaktiv abgefragt,
    wenn nicht angegeben; bei leerer Eingabe wird dieser Schritt ausgelassen.

.PARAMETER OutputPath
    Verzeichnis fuer Log-, Backup- und Zieleinstellungsdateien.
    Default: .\CARO-Setup-Logs (relativ zum Scriptverzeichnis)

.PARAMETER RestoreFrom
    Pfad zu einer zuvor erzeugten CARO-Backup-*.json Datei. Aktiviert den
    Rollback-Modus statt des normalen Anwenden-Modus.

.PARAMETER MaxLogSizeKB
    Gewuenschte Mindest-Maximalgroesse (in KB) des Security-Eventlogs.
    Default: 131072 (128 MB), siehe PDF Seite 10.

.PARAMETER DesiredSettingsFile
    Pfad zu einer JSON-Eingabedatei, aus der ServiceAccount, MaxLogSizeKB und/
    oder der Scope (welche Bloecke ueberhaupt angeboten werden) uebernommen
    werden. Ein explizit auf der Kommandozeile gesetzter Parameter hat immer
    Vorrang vor dem Wert aus der Datei. Die fachlich vorgegebenen Zielwerte
    (z.B. 'Erfolg' bei den Audit-Unterkategorien, die sechs SACL-Rechte) sind
    NICHT ueberschreibbar - das sind feste Vorgaben aus der PDF, keine
    Umgebungsentscheidung. Beispiel-Schema:
        {
          "ServiceAccount": "CUSATUM\\sa-caro",
          "MaxLogSizeKB": 262144,
          "Scope": {
            "EventLogReaders": true,
            "ForceSubcategoryPolicy": true,
            "AuditPolicies": true,
            "SecurityLogConfig": true,
            "Sacl": true,
            "Firewall": false
          }
        }

.PARAMETER ReportOnly
    Reiner Lesepass: fragt nichts ab, aendert nichts, liest nur den aktuellen
    Wert jeder Einstellung und schreibt ihn (zusammen mit dem Soll-Wert und ob
    er uebereinstimmt) in die Backup-Datei (Status 'Nur gelesen (Report)').
    Eignet sich als Bestandsaufnahme vor dem ersten Eingriff oder als
    Ausgangspunkt fuer eine eigene -DesiredSettingsFile. Nicht gleichzeitig
    mit -RestoreFrom verwendbar.

.PARAMETER AutoApprove
    Ueberspringt die Einzelbestaetigung (weiterhin vollstaendig protokolliert).
    Nicht empfohlen fuer den ersten Lauf.

.EXAMPLE
    .\Set-CAROObserverPrerequisites.ps1 -ServiceAccount "CUSATUM\sa-caro"

.EXAMPLE
    .\Set-CAROObserverPrerequisites.ps1 -RestoreFrom ".\CARO-Setup-Logs\CARO-Backup_DC01_20260922-101500.json"

.EXAMPLE
    .\Set-CAROObserverPrerequisites.ps1 -ReportOnly

.EXAMPLE
    .\Set-CAROObserverPrerequisites.ps1 -DesiredSettingsFile ".\caro-testlab.json"

.NOTES
    PowerShell 5.1 kompatibel. Benoetigt KEIN GroupPolicy/RSAT-Modul.
    Muss als Administrator (Domaenen-Admin empfohlen) auf dem Domaenencontroller
    laufen, siehe PDF Seite 4 (SeSecurityPrivilege fuer die SACL-Aenderung).
#>
[CmdletBinding()]
param(
    [string]$ServiceAccount,
    [string]$OutputPath = (Join-Path -Path $PSScriptRoot -ChildPath 'CARO-Setup-Logs'),
    [string]$RestoreFrom,
    [ValidateRange(1024, 4194240)]
    [int]$MaxLogSizeKB = 131072,
    [string]$DesiredSettingsFile,
    [switch]$ReportOnly,
    [switch]$AutoApprove
)

if ($ReportOnly -and $RestoreFrom) {
    throw "-ReportOnly und -RestoreFrom koennen nicht gleichzeitig verwendet werden."
}

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.DirectoryServices -ErrorAction SilentlyContinue

#region ---------------------------------------------------------- Privilege-Helper ---
# .NET liest/schreibt die SACL eines AD-Objekts nur, wenn SeSecurityPrivilege im
# Prozess-Token AKTIV ist (nicht nur vorhanden). Domain-Admins besitzen das Recht,
# es muss aber per AdjustTokenPrivileges explizit eingeschaltet werden.
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class CaroPrivilege {
    [DllImport("advapi32.dll", SetLastError=true)]
    static extern bool OpenProcessToken(IntPtr h, int acc, out IntPtr tok);
    [DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Auto)]
    static extern bool LookupPrivilegeValue(string host, string name, out long luid);
    [StructLayout(LayoutKind.Sequential)]
    struct TOKEN_PRIV { public int Count; public long Luid; public int Attr; }
    [DllImport("advapi32.dll", SetLastError=true)]
    static extern bool AdjustTokenPrivileges(IntPtr tok, bool disableAll, ref TOKEN_PRIV newState, int bufLen, IntPtr prev, IntPtr ret);
    [DllImport("kernel32.dll")]
    static extern IntPtr GetCurrentProcess();
    const int TOKEN_ADJUST_PRIVILEGES = 0x0020;
    const int TOKEN_QUERY = 0x0008;
    const int SE_PRIVILEGE_ENABLED = 0x0002;
    public static bool Enable(string privilege) {
        IntPtr tok;
        if (!OpenProcessToken(GetCurrentProcess(), TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, out tok)) return false;
        TOKEN_PRIV tp = new TOKEN_PRIV();
        tp.Count = 1;
        tp.Attr = SE_PRIVILEGE_ENABLED;
        if (!LookupPrivilegeValue(null, privilege, out tp.Luid)) return false;
        return AdjustTokenPrivileges(tok, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
    }
}
'@
#endregion

#region ---------------------------------------------------------- Grundgeruest ---
$scriptStart = Get-Date
$hostName    = $env:COMPUTERNAME

if (-not (Test-Path -Path $OutputPath)) {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
}

$stamp       = $scriptStart.ToString('yyyyMMdd-HHmmss')
$LogFile     = Join-Path $OutputPath "CARO-Setup_${hostName}_$stamp.log"
$BackupFile  = Join-Path $OutputPath "CARO-Backup_${hostName}_$stamp.json"
$DesiredFile = Join-Path $OutputPath "CARO-DesiredSettings_${hostName}_$stamp.json"

$script:BackupEntries = New-Object System.Collections.Generic.List[object]
$script:ApproveAll    = [bool]$AutoApprove
$script:ErrorCount    = 0
$script:WarningCount  = 0
$script:DomainDN      = $null

function Write-Log {
    param(
        [Parameter(Mandatory)] [string]$Message,
        [ValidateSet('INFO','WARN','ERROR','STEP','RESULT')] [string]$Level = 'INFO'
    )
    $line = "[{0:yyyy-MM-dd HH:mm:ss}] [{1,-6}] {2}" -f (Get-Date), $Level, $Message
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
    switch ($Level) {
        'ERROR'  { $script:ErrorCount++;   Write-Host $line -ForegroundColor Red }
        'WARN'   { $script:WarningCount++; Write-Host $line -ForegroundColor Yellow }
        'STEP'   { Write-Host $line -ForegroundColor Cyan }
        'RESULT' { Write-Host $line -ForegroundColor Green }
        default  { Write-Host $line }
    }
}

function Add-BackupEntry {
    param($Id, $Title, $Command, $OriginalValueRaw, $OriginalValueDisplay, $NewValueRaw, $NewValueDisplay, $Status)
    $script:BackupEntries.Add([pscustomobject]@{
        Id                   = $Id
        Title                = $Title
        Timestamp            = (Get-Date).ToString('o')
        Command              = $Command
        OriginalValueRaw     = $OriginalValueRaw
        OriginalValueDisplay = $OriginalValueDisplay
        NewValueRaw          = $NewValueRaw
        NewValueDisplay      = $NewValueDisplay
        Status               = $Status
    })
}

function Save-Backup {
    $script:BackupEntries | ConvertTo-Json -Depth 8 | Set-Content -Path $BackupFile -Encoding UTF8
}
#endregion

#region ---------------------------------------------------------- Bestaetigungs-Engine ---
function Confirm-Step {
    param(
        [Parameter(Mandatory)] [string]$Title,
        [Parameter(Mandatory)] [string]$Description,
        [Parameter(Mandatory)] [string]$Command,
        [Parameter(Mandatory)] [string]$CurrentValue,
        [Parameter(Mandatory)] [string]$DesiredValue,
        [bool]$AlreadyOk = $false
    )

    Write-Host ""
    Write-Host "==================================================================" -ForegroundColor DarkGray
    Write-Host " $Title" -ForegroundColor White
    Write-Host "==================================================================" -ForegroundColor DarkGray
    Write-Host "Was wird gemacht:" -ForegroundColor Gray
    Write-Host "  $Description"
    Write-Host ""
    Write-Host "Befehl / Mechanismus:" -ForegroundColor Gray
    Write-Host "  $Command" -ForegroundColor DarkYellow
    Write-Host ""
    Write-Host "Aktueller Wert : $CurrentValue"
    Write-Host "Zielwert       : $DesiredValue"
    if ($AlreadyOk) {
        Write-Host ""
        Write-Host "Hinweis: Aktueller Wert entspricht bereits dem Zielwert." -ForegroundColor Green
    }
    Write-Log -Level STEP -Message "$Title | aktuell='$CurrentValue' | ziel='$DesiredValue' | befehl='$Command'"

    if ($script:ApproveAll) {
        Write-Host "(AutoApprove aktiv - wird automatisch angewendet)" -ForegroundColor DarkGray
        return 'Yes'
    }

    while ($true) {
        $answer = Read-Host "Anwenden? [J]a / [N]ein (ueberspringen) / [A]lle weiteren automatisch Ja / [Q] Abbrechen"
        switch ($answer.ToUpperInvariant()) {
            'J' { return 'Yes' }
            'A' { $script:ApproveAll = $true; return 'Yes' }
            'N' { return 'No' }
            'Q' { return 'Quit' }
            default { Write-Host "Bitte J, N, A oder Q eingeben." -ForegroundColor Yellow }
        }
    }
}

function Invoke-CaroSetting {
    <#
      Generischer Motor: liest den aktuellen Wert (Def.Get), zeigt ihn zusammen
      mit dem Zielwert im Klartext an, fragt den Anwender, wendet bei Zustimmung
      Def.Set an, verifiziert per erneutem Def.Get und protokolliert Original-
      und neuen Wert in $script:BackupEntries (Grundlage fuer -RestoreFrom).
    #>
    param(
        [Parameter(Mandatory)] [hashtable]$Def,
        [Parameter(Mandatory)] $TargetValue,
        [Parameter(Mandatory)] [ValidateSet('Apply','Restore','Report')] [string]$Mode
    )

    $current = $null
    $readError = $null
    try { $current = & $Def.Get $Def } catch { $readError = $_.Exception.Message }

    if ($readError) {
        Write-Log -Level ERROR -Message "[$($Def.Id)] Fehler beim Lesen des aktuellen Werts: $readError"
        # $cmd wird trotz Lesefehler berechnet (haengt nur vom bekannten
        # Zielwert ab, nicht vom fehlgeschlagenen Ist-Wert) - sonst fehlen
        # z.B. bei EventLogReaders spaeter Angaben wie der Kontoname im
        # Backup, was die automatische Konto-Erkennung bei -RestoreFrom
        # verhindert.
        $targetDisplay = & $Def.Format $TargetValue
        $cmd = $Def.CommandTemplate -f $targetDisplay
        Add-BackupEntry -Id $Def.Id -Title $Def.Title -Command $cmd `
            -OriginalValueRaw $null -OriginalValueDisplay "FEHLER: $readError" `
            -NewValueRaw $null -NewValueDisplay '' -Status 'Fehler beim Lesen'
        return 'Error'
    }

    $currentDisplay = & $Def.Format $current
    $targetDisplay  = & $Def.Format $TargetValue
    $alreadyOk = if ($Def.ContainsKey('Compare')) { & $Def.Compare $current $TargetValue } else { $currentDisplay -eq $targetDisplay }

    $cmd = $Def.CommandTemplate -f $targetDisplay

    if ($Mode -eq 'Report') {
        $status = if ($alreadyOk) { 'Nur gelesen (Report) - entspricht Ziel' } else { 'Nur gelesen (Report) - weicht vom Ziel ab' }
        $level  = if ($alreadyOk) { 'RESULT' } else { 'WARN' }
        Write-Log -Level $level -Message "[$($Def.Id)] $status | aktuell='$currentDisplay' | ziel='$targetDisplay'"
        Add-BackupEntry -Id $Def.Id -Title $Def.Title -Command $cmd `
            -OriginalValueRaw $current -OriginalValueDisplay $currentDisplay `
            -NewValueRaw $current -NewValueDisplay $currentDisplay -Status $status
        return 'Reported'
    }

    $title = if ($Mode -eq 'Restore') { "[ROLLBACK] $($Def.Title)" } else { $Def.Title }

    $choice = Confirm-Step -Title $title -Description $Def.Description -Command $cmd `
                -CurrentValue $currentDisplay -DesiredValue $targetDisplay -AlreadyOk $alreadyOk

    if ($choice -eq 'Quit') { return 'Quit' }

    if ($choice -eq 'No') {
        Write-Log -Level WARN -Message "[$($Def.Id)] Uebersprungen durch Anwender."
        Add-BackupEntry -Id $Def.Id -Title $Def.Title -Command $cmd `
            -OriginalValueRaw $current -OriginalValueDisplay $currentDisplay `
            -NewValueRaw $current -NewValueDisplay $currentDisplay -Status 'Uebersprungen'
        return 'Skipped'
    }

    if ($alreadyOk) {
        Write-Log -Level RESULT -Message "[$($Def.Id)] Bereits korrekt, keine Aenderung noetig."
        Add-BackupEntry -Id $Def.Id -Title $Def.Title -Command $cmd `
            -OriginalValueRaw $current -OriginalValueDisplay $currentDisplay `
            -NewValueRaw $current -NewValueDisplay $currentDisplay -Status 'Bereits korrekt'
        return 'AlreadyOk'
    }

    try {
        & $Def.Set $Def $TargetValue
        Start-Sleep -Milliseconds 200
        $verify = & $Def.Get $Def
        $verifyDisplay = & $Def.Format $verify
        $verifyOk = if ($Def.ContainsKey('Compare')) { & $Def.Compare $verify $TargetValue } else { $verifyDisplay -eq $targetDisplay }
        if ($verifyOk) {
            Write-Log -Level RESULT -Message "[$($Def.Id)] Erfolgreich geaendert: '$currentDisplay' -> '$verifyDisplay'"
            Add-BackupEntry -Id $Def.Id -Title $Def.Title -Command $cmd `
                -OriginalValueRaw $current -OriginalValueDisplay $currentDisplay `
                -NewValueRaw $verify -NewValueDisplay $verifyDisplay -Status 'Geaendert'
            return 'Changed'
        } else {
            Write-Log -Level WARN -Message "[$($Def.Id)] Nach Anwendung abweichender Wert: '$verifyDisplay' (erwartet '$targetDisplay')"
            Add-BackupEntry -Id $Def.Id -Title $Def.Title -Command $cmd `
                -OriginalValueRaw $current -OriginalValueDisplay $currentDisplay `
                -NewValueRaw $verify -NewValueDisplay $verifyDisplay -Status 'Abweichung nach Anwendung'
            return 'Mismatch'
        }
    } catch {
        Write-Log -Level ERROR -Message "[$($Def.Id)] Fehler beim Setzen: $($_.Exception.Message)"
        Add-BackupEntry -Id $Def.Id -Title $Def.Title -Command $cmd `
            -OriginalValueRaw $current -OriginalValueDisplay $currentDisplay `
            -NewValueRaw $null -NewValueDisplay 'FEHLER' -Status "Fehler: $($_.Exception.Message)"
        return 'Error'
    }
}
#endregion

#region ---------------------------------------------------------- Event Log Readers ---
function Get-BareUserName {
    param([string]$Account)
    if ($Account -match '\\') { return ($Account -split '\\')[-1] }
    if ($Account -match '@')  { return ($Account -split '@')[0] }
    return $Account
}

# Well-Known-SID von BUILTIN\Event Log Readers - weltweit auf jedem Windows
# identisch, unabhaengig von Sprache. Name (CN, SamAccountName) kann je nach
# Sprachversion abweichen - bestaetigt: auf einem deutschen System sind CN
# UND SamAccountName "Ereignisprotokollleser", nicht "Event Log Readers".
# Die Gruppe wird deshalb nie ueber einen angenommenen Namen angesprochen,
# sondern immer ueber diese SID aufgeloest.
$script:EventLogReadersSid = 'S-1-5-32-573'

function Get-EventLogReadersGroupIdentity {
    $sid = New-Object System.Security.Principal.SecurityIdentifier($script:EventLogReadersSid)
    $name = ($sid.Translate([System.Security.Principal.NTAccount]).Value -split '\\')[-1]
    $dn = $null
    if ($script:IsDomainController -and $script:DomainDN) {
        if ($script:AdModuleAvailable) {
            try {
                $grp = Get-ADGroup -Filter "SID -eq '$($script:EventLogReadersSid)'" -ErrorAction Stop
                if ($grp) {
                    $dn = $grp.DistinguishedName
                    $name = $grp.SamAccountName
                }
            } catch {
                Write-Log -Level WARN -Message "Get-ADGroup fuer Event Log Readers (SID $($script:EventLogReadersSid)) fehlgeschlagen, falle auf CN-Konstruktion zurueck: $($_.Exception.Message)"
            }
        }
        if (-not $dn) { $dn = "CN=$name,CN=Builtin,$script:DomainDN" }
    }
    return [pscustomobject]@{ Name = $name; DN = $dn }
}

function Resolve-AdAccountDN {
    param([string]$SamAccountName)
    $escaped = $SamAccountName -replace '([\\\*\(\)\x00])', '\$1'
    $searcher = New-Object System.DirectoryServices.DirectorySearcher
    $searcher.SearchRoot = New-Object System.DirectoryServices.DirectoryEntry("LDAP://$script:DomainDN")
    $searcher.Filter = "(sAMAccountName=$escaped)"
    $searcher.PropertiesToLoad.Add('distinguishedName') | Out-Null
    $result = $searcher.FindOne()
    if (-not $result) { throw "Konto '$SamAccountName' wurde per LDAP-Suche (sAMAccountName) in der Domaene nicht gefunden." }
    return [string]$result.Properties['distinguishedname'][0]
}

function Get-EventLogReadersMembersViaLdap {
    param([string]$GroupDN)
    $grp = [ADSI]"LDAP://$GroupDN"
    # .psbase. umgeht PowerShells ADSI-Eigenschaftsadapter, der .Properties
    # abfangen und dadurch unauffindbar machen kann ("Cannot index into a
    # null array").
    $memberProp = $grp.psbase.Properties['member']
    $memberDns = if ($memberProp -and $memberProp.Count -gt 0) { @($memberProp.Value) } else { @() }
    $names = @()
    foreach ($dn in $memberDns) {
        try {
            $memberEntry = [ADSI]"LDAP://$dn"
            $sam = $memberEntry.psbase.Properties['sAMAccountName'].Value
            if ($sam) { $names += [string]$sam }
        } catch {
            Write-Log -Level WARN -Message "Mitglied '$dn' der Gruppe Event Log Readers konnte nicht aufgeloest werden (uebersprungen bei der Pruefung): $($_.Exception.Message)"
        }
    }
    return $names
}

function Get-EventLogReadersMembers {
    $identity = $script:EventLogReadersIdentity
    if ($script:IsDomainController -and $identity.DN) {
        if ($script:AdModuleAvailable) {
            try {
                $members = @(Get-ADGroupMember -Identity $identity.DN -ErrorAction Stop)
                return @($members | ForEach-Object { $_.SamAccountName })
            } catch {
                throw "Gruppenmitglieder von '$($identity.Name)' (AD-Modul, DN $($identity.DN)) konnten nicht gelesen werden: $($_.Exception.Message)"
            }
        }
        try {
            return Get-EventLogReadersMembersViaLdap -GroupDN $identity.DN
        } catch {
            throw "Gruppenmitglieder von '$($identity.Name)' (LDAP-Fallback, DN $($identity.DN)) konnten nicht gelesen werden: $($_.Exception.Message)"
        }
    }
    try {
        $grp = [ADSI]"WinNT://$script:LocalGroupHost/$($identity.Name),group"
        $names = @()
        foreach ($m in $grp.Invoke('Members')) {
            $names += $m.GetType().InvokeMember('Name', 'GetProperty', $null, $m, $null)
        }
        return $names
    } catch {
        throw "Gruppenmitglieder von '$($identity.Name)' konnten nicht gelesen werden (WinNT://$script:LocalGroupHost/...): $($_.Exception.Message)"
    }
}

function Add-EventLogReadersMember {
    param([string]$Account)
    $identity = $script:EventLogReadersIdentity
    $bareUser = Get-BareUserName -Account $Account
    if ($script:IsDomainController -and $identity.DN) {
        if ($script:AdModuleAvailable) {
            try {
                Add-ADGroupMember -Identity $identity.DN -Members $bareUser -ErrorAction Stop
                return
            } catch {
                throw "Hinzufuegen von '$Account' zu '$($identity.Name)' (AD-Modul) fehlgeschlagen: $($_.Exception.Message)"
            }
        }
        try {
            $dn = Resolve-AdAccountDN -SamAccountName $bareUser
            $grp = [ADSI]"LDAP://$($identity.DN)"
            $grp.Add("LDAP://$dn")
            $grp.psbase.CommitChanges()
            return
        } catch {
            throw "Hinzufuegen von '$Account' zu '$($identity.Name)' (LDAP-Fallback) fehlgeschlagen: $($_.Exception.Message)"
        }
    }
    $result = & net localgroup "$($identity.Name)" "$Account" /add 2>&1
    if ($LASTEXITCODE -ne 0) { throw "net localgroup /add fehlgeschlagen (Exit $LASTEXITCODE): $result" }
}

function Remove-EventLogReadersMember {
    param([string]$Account)
    $identity = $script:EventLogReadersIdentity
    $bareUser = Get-BareUserName -Account $Account
    if ($script:IsDomainController -and $identity.DN) {
        if ($script:AdModuleAvailable) {
            try {
                Remove-ADGroupMember -Identity $identity.DN -Members $bareUser -Confirm:$false -ErrorAction Stop
                return
            } catch {
                throw "Entfernen von '$Account' aus '$($identity.Name)' (AD-Modul) fehlgeschlagen: $($_.Exception.Message)"
            }
        }
        try {
            $dn = Resolve-AdAccountDN -SamAccountName $bareUser
            $grp = [ADSI]"LDAP://$($identity.DN)"
            $grp.Remove("LDAP://$dn")
            $grp.psbase.CommitChanges()
            return
        } catch {
            throw "Entfernen von '$Account' aus '$($identity.Name)' (LDAP-Fallback) fehlgeschlagen: $($_.Exception.Message)"
        }
    }
    $result = & net localgroup "$($identity.Name)" "$Account" /delete 2>&1
    if ($LASTEXITCODE -ne 0) { throw "net localgroup /delete fehlgeschlagen (Exit $LASTEXITCODE): $result" }
}
#endregion

#region ---------------------------------------------------------- Audit-Unterkategorien ---
# Locale-unabhaengige, von Microsoft dokumentierte Subcategory-GUIDs. 'Expect' wird
# beim Scriptstart gegen den tatsaechlich auf diesem System aufgeloesten Namen
# geprueft (siehe Validierung weiter unten) - schlaegt der Abgleich fehl, wird die
# betroffene Einstellung sicherheitshalber NICHT angeboten, statt blind die
# vermeintlich richtige Unterkategorie zu setzen.
$script:AuditSubcategoryMap = [ordered]@{
    'AccountMgmt-User'          = @{ Guid = '0CCE9235-69AE-11D9-BED3-505054503030'; Expect = 'ont' }
    'AccountMgmt-Computer'      = @{ Guid = '0CCE9236-69AE-11D9-BED3-505054503030'; Expect = 'Computer' }
    'AccountMgmt-SecurityGroup' = @{ Guid = '0CCE9237-69AE-11D9-BED3-505054503030'; Expect = 'Sicherheitsgruppe' }
    'AccountMgmt-DistGroup'     = @{ Guid = '0CCE9238-69AE-11D9-BED3-505054503030'; Expect = 'Verteilergruppe' }
    'AccountMgmt-AppGroup'      = @{ Guid = '0CCE9239-69AE-11D9-BED3-505054503030'; Expect = 'Anwendungsgruppe' }
    'AccountMgmt-Other'         = @{ Guid = '0CCE923A-69AE-11D9-BED3-505054503030'; Expect = 'Andere' }
    'DSAccess-Access'           = @{ Guid = '0CCE923B-69AE-11D9-BED3-505054503030'; Expect = 'Verzeichnisdienstzugriff' }
    'DSAccess-Changes'          = @{ Guid = '0CCE923C-69AE-11D9-BED3-505054503030'; Expect = 'Verzeichnisdienstän' }
    'PolicyChange-Audit'        = @{ Guid = '0CCE922F-69AE-11D9-BED3-505054503030'; Expect = 'Richtlinienänderung' }
}

$script:AuditCategoryLabel = @{
    'AccountMgmt-User'          = 'Kontoverwaltung: Benutzerkontoverwaltung ueberwachen'
    'AccountMgmt-Computer'      = 'Kontoverwaltung: Computerkontoverwaltung ueberwachen'
    'AccountMgmt-SecurityGroup' = 'Kontoverwaltung: Sicherheitsgruppenverwaltung ueberwachen'
    'AccountMgmt-DistGroup'     = 'Kontoverwaltung: Verteilergruppenverwaltung ueberwachen'
    'AccountMgmt-AppGroup'      = 'Kontoverwaltung: Anwendungsgruppenverwaltung ueberwachen'
    'AccountMgmt-Other'         = 'Kontoverwaltung: Andere Kontoverwaltungsereignisse ueberwachen'
    'DSAccess-Access'           = 'DS-Zugriff: Verzeichnisdienstzugriff ueberwachen'
    'DSAccess-Changes'          = 'DS-Zugriff: Verzeichnisdienstaenderungen ueberwachen'
    'PolicyChange-Audit'        = 'Richtlinienaenderung: Ueberwachungsrichtlinienaenderung ueberwachen'
}

function Get-AuditSubcategoryInfo {
    param([string]$Guid)
    $lines = & auditpol /get /subcategory:"{$Guid}" /r 2>&1
    if ($LASTEXITCODE -ne 0) { throw "auditpol /get fehlgeschlagen fuer {$Guid}: $($lines -join ' ')" }
    $dataLine = $lines | Select-Object -Skip 1 | Where-Object { $_ -match '\S' } | Select-Object -First 1
    if (-not $dataLine) { throw "Keine Daten von auditpol fuer {$Guid} erhalten." }
    $fields = $dataLine -split ',' | ForEach-Object { $_.Trim('"') }
    if ($fields.Count -lt 5) { throw "Unerwartetes auditpol-CSV-Format fuer {$Guid}: $dataLine" }
    [pscustomobject]@{
        Name      = $fields[2]
        Guid      = $fields[3]
        Inclusion = $fields[4]
    }
}

function Set-AuditSubcategory {
    param([string]$Guid, [string]$Value)
    switch ($Value) {
        'Erfolg und Fehler' { & auditpol /set /subcategory:"{$Guid}" /success:enable  /failure:enable  | Out-Null }
        'Erfolg'            { & auditpol /set /subcategory:"{$Guid}" /success:enable  /failure:disable | Out-Null }
        'Fehler'            { & auditpol /set /subcategory:"{$Guid}" /success:disable /failure:enable  | Out-Null }
        'Keine Ueberwachung'{ & auditpol /set /subcategory:"{$Guid}" /success:disable /failure:disable | Out-Null }
        'Keine Überwachung' { & auditpol /set /subcategory:"{$Guid}" /success:disable /failure:disable | Out-Null }
        default             { throw "Unbekannter Zielwert '$Value' fuer Audit-Unterkategorie {$Guid}" }
    }
    if ($LASTEXITCODE -ne 0) { throw "auditpol /set fehlgeschlagen fuer {$Guid} (Exit $LASTEXITCODE)" }
}
#endregion

#region ---------------------------------------------------------- Security-Eventlog ---
function Get-SecurityLogConfig {
    $cfg = Get-WinEvent -ListLog 'Security'
    [pscustomobject]@{
        MaxKB = [int]($cfg.MaximumSizeInBytes / 1KB)
        Mode  = "$($cfg.LogMode)"
    }
}

function Set-SecurityLogConfig {
    param($Value)
    $cfg = Get-WinEvent -ListLog 'Security'
    $cfg.MaximumSizeInBytes = [int64]$Value.MaxKB * 1KB
    $cfg.LogMode = $Value.Mode
    $cfg.SaveChanges()
}
#endregion

#region ---------------------------------------------------------- SACL Domain-Objekt ---
$script:EveryoneSid = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::WorldSid, $null)
$script:RequiredAdRights = [System.DirectoryServices.ActiveDirectoryRights] (
    [int][System.DirectoryServices.ActiveDirectoryRights]::WriteProperty -bor
    [int][System.DirectoryServices.ActiveDirectoryRights]::Delete -bor
    [int][System.DirectoryServices.ActiveDirectoryRights]::DeleteTree -bor
    [int][System.DirectoryServices.ActiveDirectoryRights]::WriteDacl -bor
    [int][System.DirectoryServices.ActiveDirectoryRights]::CreateChild -bor
    [int][System.DirectoryServices.ActiveDirectoryRights]::DeleteChild
)

function Get-DomainSaclEntry {
    $de = New-Object System.DirectoryServices.DirectoryEntry("LDAP://$script:DomainDN")
    # .psbase. umgeht PowerShells eigenen ADSI-Eigenschaftsadapter, der bei
    # DirectoryEntry-Objekten seltener genutzte .NET-Member wie "Options"
    # ueberlagern und dadurch unauffindbar machen kann ("property cannot be
    # found"). SecurityMasks=Sacl ist der Schluessel, damit .NET ueberhaupt
    # die Ueberwachungs-ACEs (statt nur DACL/Owner) liefert; erfordert
    # aktives SeSecurityPrivilege (siehe CaroPrivilege.Enable im Hauptteil).
    $de.psbase.Options.SecurityMasks = [System.DirectoryServices.SecurityMasks]::Sacl
    $sd = $de.psbase.ObjectSecurity
    $rules = $sd.GetAuditRules($true, $true, [System.Security.Principal.SecurityIdentifier])
    foreach ($r in $rules) {
        if ($r.IdentityReference -eq $script:EveryoneSid -and
            $r.AuditFlags -eq [System.Security.AccessControl.AuditFlags]::Success -and
            $r.InheritanceType -eq [System.DirectoryServices.ActiveDirectorySecurityInheritance]::All -and
            (([int]$r.ActiveDirectoryRights -band [int]$script:RequiredAdRights) -eq [int]$script:RequiredAdRights)) {
            return $true
        }
    }
    return $false
}

function Set-DomainSaclEntry {
    param([bool]$Present)
    $de = New-Object System.DirectoryServices.DirectoryEntry("LDAP://$script:DomainDN")
    $de.psbase.Options.SecurityMasks = [System.DirectoryServices.SecurityMasks]::Sacl
    $sd = $de.psbase.ObjectSecurity
    $rule = New-Object System.DirectoryServices.ActiveDirectoryAuditRule(
        $script:EveryoneSid, $script:RequiredAdRights,
        [System.Security.AccessControl.AuditFlags]::Success,
        [System.DirectoryServices.ActiveDirectorySecurityInheritance]::All)
    if ($Present) { $sd.AddAuditRule($rule) } else { $sd.RemoveAuditRuleSpecific($rule) }
    $de.psbase.ObjectSecurity = $sd
    $de.psbase.CommitChanges()
}
#endregion

#region ---------------------------------------------------------- Firewall ---
# Name (im Gegensatz zu DisplayName/DisplayGroup) ist bei vordefinierten
# Firewall-Regeln NICHT lokalisiert und daher auf jedem Sprachstand gueltig.
$script:FirewallRules = @(
    @{ Name = 'RemoteEventLogSvc-In-TCP';      Label = 'Remote-Ereignisprotokollverwaltung (RPC)' }
    @{ Name = 'RemoteEventLogSvc-NP-In-TCP';   Label = 'Remote-Ereignisprotokollverwaltung (NP-eingehend)' }
    @{ Name = 'RemoteEventLogSvc-RPCSS-In-TCP';Label = 'Remote-Ereignisprotokollverwaltung (RPC-EPMAP)' }
)

function Get-CaroFirewallRuleEnabled {
    param([string]$RuleName)
    $r = Get-NetFirewallRule -Name $RuleName -ErrorAction SilentlyContinue
    if (-not $r) { throw "Firewall-Regel '$RuleName' wurde auf diesem Server nicht gefunden." }
    return [bool]($r.Enabled -eq 'True')
}

function Set-CaroFirewallRuleEnabled {
    param([string]$RuleName, [bool]$Value)
    if ($Value) { Enable-NetFirewallRule -Name $RuleName | Out-Null }
    else { Disable-NetFirewallRule -Name $RuleName | Out-Null }
}
#endregion

#region ---------------------------------------------------------- Settings-Katalog ---
function New-CaroSettingDefinitions {
    param(
        [string]$ServiceAccount,
        [int]$MaxLogSizeKB,
        [Parameter(Mandatory)] [pscustomobject]$Scope
    )

    $defs = @()

    if ($Scope.EventLogReaders -and $ServiceAccount) {
        $svcAccountCopy = $ServiceAccount
        $bareUser = Get-BareUserName -Account $svcAccountCopy
        $groupName = $script:EventLogReadersIdentity.Name
        $groupDn = $script:EventLogReadersIdentity.DN
        $cmdTemplate = if ($script:IsDomainController -and $groupDn -and $script:AdModuleAvailable) {
            "Add-ADGroupMember -Identity ""$groupDn"" -Members ""$bareUser""   (Ziel: Mitglied={0})"
        } elseif ($script:IsDomainController -and $groupDn) {
            "[ADSI] LDAP://$groupDn -> Add(""$bareUser"")   (Ziel: Mitglied={0})"
        } else {
            "net localgroup ""$groupName"" ""$svcAccountCopy"" /add   (Ziel: Mitglied={0})"
        }
        $defs += @{
            Id              = 'EventLogReaders'
            Title           = "Servicekonto zur Gruppe ""$groupName"" (Event Log Readers) hinzufuegen"
            Description     = "Das CARO-Servicekonto '$svcAccountCopy' muss lokal Mitglied der Gruppe '$groupName' (BUILTIN\Event Log Readers, SID $script:EventLogReadersSid) sein, damit es das Security-Eventlog auslesen darf (nur noetig, falls das Konto nicht bereits administrative oder Nur-Lese-Rechte besitzt). PDF S.4."
            CommandTemplate = $cmdTemplate
            Account         = $svcAccountCopy
            BareUser        = $bareUser
            Get             = { param($Def) [bool](Get-EventLogReadersMembers | Where-Object { $_ -ieq $Def.BareUser }) }
            Set             = {
                param($Def, $Value)
                if ($Value) { Add-EventLogReadersMember -Account $Def.Account }
                else { Remove-EventLogReadersMember -Account $Def.Account }
            }
            Format          = { param($v) if ($v) { 'Mitglied' } else { 'Kein Mitglied' } }
            Desired         = $true
        }
    } elseif ($Scope.EventLogReaders -and -not $ServiceAccount) {
        Write-Log -Level INFO -Message "Event Log Readers-Schritt uebersprungen: kein ServiceAccount angegeben."
    } elseif (-not $Scope.EventLogReaders) {
        Write-Log -Level INFO -Message "Event Log Readers-Schritt uebersprungen: per Scope deaktiviert."
    }

    if ($Scope.ForceSubcategoryPolicy) {
    $defs += @{
        Id              = 'ForceSubcategoryPolicy'
        Title           = 'Sicherheitsoption: Unterkategorieeinstellungen der Ueberwachungsrichtlinie erzwingen'
        Description     = 'Muss als Erstes aktiviert sein, sonst koennen die weiter unten gesetzten Unterkategorien (Kontoverwaltung, DS-Zugriff, Richtlinienaenderung) von der aelteren, groben Kategorie-Richtlinie ausser Kraft gesetzt werden. PDF S.7, Schritt 4.'
        CommandTemplate = 'Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Lsa" -Name SCENoApplyLegacyAuditPolicy -Type DWord -Value {0}'
        Get             = {
            param($Def)
            $v = (Get-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Lsa' -Name 'SCENoApplyLegacyAuditPolicy' -ErrorAction SilentlyContinue).SCENoApplyLegacyAuditPolicy
            if ($null -eq $v) { 'ABSENT' } else { [string]$v }
        }
        Set             = {
            param($Def, $Value)
            if ($Value -eq 'ABSENT') {
                Remove-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Lsa' -Name 'SCENoApplyLegacyAuditPolicy' -ErrorAction SilentlyContinue
            } else {
                New-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Lsa' -Name 'SCENoApplyLegacyAuditPolicy' -PropertyType DWord -Value ([int]$Value) -Force | Out-Null
            }
        }
        Format          = {
            param($v)
            switch ("$v") {
                '1'      { 'Aktiviert' }
                '0'      { 'Deaktiviert' }
                'ABSENT' { 'Nicht gesetzt (Standard = Deaktiviert)' }
                default  { "Unbekannt ($v)" }
            }
        }
        Desired         = '1'
    }
    }

    if ($Scope.AuditPolicies) {
    foreach ($key in $script:AuditSubcategoryMap.Keys) {
        $info = $script:AuditSubcategoryMap[$key]
        if (-not $info.Validated) { continue }
        $guid  = $info.Guid
        $label = $script:AuditCategoryLabel[$key]
        $defs += @{
            Id              = "Audit-$key"
            Title           = $label
            Description     = "Setzt die Ueberwachungs-Unterkategorie '$($info.ResolvedName)' (GUID {$guid}) auf 'Erfolg ueberwachen', damit die zugehoerigen AD-Aenderungen im Security-Eventlog protokolliert werden. Aenderung wirkt sofort (kein gpupdate noetig, da lokal via auditpol gesetzt)."
            CommandTemplate = "auditpol /set /subcategory:""{{$guid}}"" /success:enable /failure:disable   (Ziel: {0})"
            Guid            = $guid
            Get             = { param($Def) (Get-AuditSubcategoryInfo -Guid $Def.Guid).Inclusion }
            Set             = { param($Def, $Value) Set-AuditSubcategory -Guid $Def.Guid -Value $Value }
            Format          = { param($v) $v }
            Desired         = 'Erfolg'
        }
    }
    }

    if ($Scope.SecurityLogConfig) {
    $defs += @{
        Id              = 'SecurityLogConfig'
        Title           = 'Maximale Groesse und Aufbewahrung des Security-Eventlogs'
        Description     = "Setzt die maximale Groesse des Sicherheitsereignisprotokolls auf mindestens $MaxLogSizeKB KB und aktiviert 'Ereignisse bei Bedarf ueberschreiben (aelteste zuerst)', damit keine Ereignisse verloren gehen, bevor der CARO-AD-Observer sie ausliest. PDF S.10-11."
        CommandTemplate = '$cfg = Get-WinEvent -ListLog Security; $cfg.MaximumSizeInBytes = <KB>*1KB; $cfg.LogMode = "Circular"; $cfg.SaveChanges()   (Ziel: {0})'
        Get             = { param($Def) Get-SecurityLogConfig }
        Set             = { param($Def, $Value) Set-SecurityLogConfig -Value $Value }
        Format          = { param($v) "Max. Groesse: $($v.MaxKB) KB, Modus: $($v.Mode)" }
        Compare         = { param($c, $t) ($c.MaxKB -ge $t.MaxKB) -and ($c.Mode -eq $t.Mode) }
        Desired         = [pscustomobject]@{ MaxKB = $MaxLogSizeKB; Mode = 'Circular' }
    }
    }

    if ($Scope.Sacl -and $script:DomainDN) {
        $defs += @{
            Id              = 'SaclEveryone'
            Title           = 'SACL auf Domain-Objekt setzen (Jeder / Erfolg ueberwachen)'
            Description     = "Fuegt am Domain-Objekt '$script:DomainDN' eine Ueberwachungsregel fuer 'Jeder' hinzu: Typ=Zulassen, Anwenden auf='Dieses und alle untergeordneten Objekte', Rechte=Alle Eigenschaften schreiben/Loeschen/Unterstruktur loeschen/Berechtigungen aendern/Alle untergeordneten Objekte erstellen/Alle untergeordneten Objekte loeschen. Ohne diesen Eintrag erzeugt Windows trotz aktiver Audit-Richtlinien keine AD-Aenderungsereignisse. Muss nur auf EINEM DC gesetzt werden (repliziert automatisch). PDF S.12-17."
            CommandTemplate = '[DirectoryEntry SACL] Jeder / Zulassen / Erfolg / Dieses+untergeordnete Objekte / WriteProperty,Delete,DeleteTree,WriteDacl,CreateChild,DeleteChild -> {0}'
            Get             = { param($Def) [bool](Get-DomainSaclEntry) }
            Set             = { param($Def, $Value) Set-DomainSaclEntry -Present ([bool]$Value) }
            Format          = { param($v) if ($v) { 'ACE vorhanden' } else { 'ACE fehlt' } }
            Desired         = $true
        }
    }

    if ($Scope.Firewall) {
    foreach ($fw in $script:FirewallRules) {
        $ruleName  = $fw.Name
        $ruleLabel = $fw.Label
        $defs += @{
            Id              = "Firewall-$ruleName"
            Title           = "Firewall-Regel aktivieren: $ruleLabel"
            Description     = "Aktiviert die eingehende Windows-Firewall-Regel '$ruleLabel' (interner Name: $ruleName), damit der CARO-Server das Security-Eventlog dieses Domaenencontrollers remote auslesen darf. Muss auf JEDEM zu ueberwachenden DC ausgefuehrt werden. PDF S.17-18."
            CommandTemplate = "Enable-NetFirewallRule -Name '$ruleName'   (Ziel: Aktiviert={0})"
            RuleName        = $ruleName
            Get             = { param($Def) Get-CaroFirewallRuleEnabled -RuleName $Def.RuleName }
            Set             = { param($Def, $Value) Set-CaroFirewallRuleEnabled -RuleName $Def.RuleName -Value ([bool]$Value) }
            Format          = { param($v) if ($v) { 'Aktiviert' } else { 'Deaktiviert' } }
            Desired         = $true
        }
    }
    }

    return $defs
}
#endregion

#region ---------------------------------------------------------- Hauptablauf ---
Write-Host @"
CARO-AD-Observer - Voraussetzungen konfigurieren
Server     : $hostName
Zeitpunkt  : $($scriptStart.ToString('yyyy-MM-dd HH:mm:ss'))
Log        : $LogFile
Backup     : $BackupFile
"@ -ForegroundColor White

Write-Log -Level INFO -Message "Script gestartet auf $hostName. LogFile=$LogFile BackupFile=$BackupFile DesiredFile=$DesiredFile RestoreFrom=$RestoreFrom"

$script:LocalGroupHost = $hostName
$script:IsDomainController = $false
try {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    Write-Log -Level INFO -Message "Betriebssystem: $($os.Caption) ($($os.Version))"
    if ($os.Caption -match '2012 R2') {
        Write-Host "WARNUNG: Windows Server 2012 R2 ist abgekuendigt (ESU endet Okt. 2026). Upgrade dringend empfohlen." -ForegroundColor Red
        Write-Log -Level WARN -Message "DC laeuft auf abgekuendigtem Windows Server 2012 R2 (PDF S.3)."
    } elseif ($os.Caption -match '2016') {
        Write-Host "HINWEIS: Windows Server 2016 - erweiterter Support endet Januar 2027. Migration planen." -ForegroundColor Yellow
        Write-Log -Level WARN -Message "DC laeuft auf Windows Server 2016, erweiterter Support endet Jan. 2027 (PDF S.3)."
    }
    $domainRole = (Get-CimInstance -ClassName Win32_ComputerSystem).DomainRole
    if ($domainRole -notin 4, 5) {
        Write-Host "WARNUNG: Dieser Server scheint kein Domaenencontroller zu sein (DomainRole=$domainRole)." -ForegroundColor Red
        Write-Log -Level WARN -Message "DomainRole=$domainRole - kein (RO-)Domaenencontroller erkannt."
    } else {
        # Auf einem DC gibt es keine eigene lokale SAM-Datenbank - "lokale"
        # Gruppen wie Event Log Readers liegen als Builtin-Gruppe direkt in
        # Active Directory. Details zur Verwaltung (AD-Modul vs. LDAP) folgen
        # weiter unten, nachdem Domain-DN und Modulverfuegbarkeit bekannt sind.
        $script:IsDomainController = $true
        Write-Log -Level INFO -Message "Domaenencontroller erkannt."
    }
} catch {
    Write-Log -Level WARN -Message "Betriebssystem-/Rolleninformation konnte nicht ermittelt werden: $($_.Exception.Message)"
}

if (-not [CaroPrivilege]::Enable('SeSecurityPrivilege')) {
    Write-Log -Level WARN -Message "SeSecurityPrivilege konnte nicht aktiviert werden - der SACL-Schritt wird vermutlich fehlschlagen."
}

try {
    $rootDse = [ADSI]'LDAP://RootDSE'
    $script:DomainDN = [string]$rootDse.defaultNamingContext
    Write-Log -Level INFO -Message "Domain-DN ermittelt: $script:DomainDN"
} catch {
    $script:DomainDN = $null
    Write-Log -Level ERROR -Message "Domain-DN konnte nicht ermittelt werden: $($_.Exception.Message)"
}

$script:AdModuleAvailable = $false
if ($script:IsDomainController) {
    if (Get-Module -ListAvailable -Name ActiveDirectory -ErrorAction SilentlyContinue) {
        try {
            Import-Module ActiveDirectory -ErrorAction Stop
            $script:AdModuleAvailable = $true
            Write-Log -Level INFO -Message "ActiveDirectory-PowerShell-Modul gefunden und geladen - wird fuer 'Event Log Readers' bevorzugt verwendet (robuster als ADSI/net.exe)."
        } catch {
            Write-Log -Level WARN -Message "ActiveDirectory-Modul gefunden, konnte aber nicht geladen werden - falle auf LDAP/ADSI zurueck: $($_.Exception.Message)"
        }
    } else {
        Write-Log -Level INFO -Message "ActiveDirectory-PowerShell-Modul nicht gefunden - 'Event Log Readers' wird ueber LDAP/ADSI verwaltet (weniger robust, siehe README)."
    }
}

$script:EventLogReadersIdentity = Get-EventLogReadersGroupIdentity
Write-Log -Level INFO -Message "Event Log Readers aufgeloest: Name='$($script:EventLogReadersIdentity.Name)' DN='$($script:EventLogReadersIdentity.DN)' (per Well-Known-SID $script:EventLogReadersSid, sprachunabhaengig)."

foreach ($key in @($script:AuditSubcategoryMap.Keys)) {
    $entry = $script:AuditSubcategoryMap[$key]
    try {
        $info = Get-AuditSubcategoryInfo -Guid $entry.Guid
        $entry.ResolvedName = $info.Name
        if ($info.Name -match [regex]::Escape($entry.Expect)) {
            $entry.Validated = $true
        } else {
            $entry.Validated = $false
            Write-Log -Level ERROR -Message "Unterkategorie {$($entry.Guid)}: erwarteter Namensbestandteil '$($entry.Expect)' nicht in tatsaechlichem Namen '$($info.Name)' gefunden - Einstellung '$key' wird sicherheitshalber NICHT angeboten."
        }
    } catch {
        $entry.Validated = $false
        Write-Log -Level ERROR -Message "Unterkategorie {$($entry.Guid)} ('$key') konnte nicht aufgeloest werden: $($_.Exception.Message)"
    }
}

$script:Scope = [pscustomobject]@{
    EventLogReaders        = $true
    ForceSubcategoryPolicy = $true
    AuditPolicies          = $true
    SecurityLogConfig      = $true
    Sacl                   = $true
    Firewall               = $true
}

if ($DesiredSettingsFile) {
    if (-not (Test-Path -Path $DesiredSettingsFile)) {
        Write-Log -Level ERROR -Message "DesiredSettingsFile nicht gefunden: $DesiredSettingsFile"
        throw "DesiredSettingsFile nicht gefunden: $DesiredSettingsFile"
    }
    try {
        $inputCfg = Get-Content -Path $DesiredSettingsFile -Raw | ConvertFrom-Json
        Write-Log -Level INFO -Message "Eingabe-Datei geladen: $DesiredSettingsFile"
    } catch {
        Write-Log -Level ERROR -Message "DesiredSettingsFile konnte nicht als JSON gelesen werden: $($_.Exception.Message)"
        throw
    }

    if (-not $ServiceAccount -and $inputCfg.ServiceAccount) {
        $ServiceAccount = [string]$inputCfg.ServiceAccount
        Write-Log -Level INFO -Message "ServiceAccount aus Eingabe-Datei uebernommen: $ServiceAccount"
    }

    if (-not $PSBoundParameters.ContainsKey('MaxLogSizeKB') -and $inputCfg.MaxLogSizeKB) {
        $fileMaxLogSizeKB = [int]$inputCfg.MaxLogSizeKB
        if ($fileMaxLogSizeKB -lt 1024 -or $fileMaxLogSizeKB -gt 4194240) {
            Write-Log -Level WARN -Message "MaxLogSizeKB aus Eingabe-Datei ($fileMaxLogSizeKB) liegt ausserhalb des gueltigen Bereichs (1024-4194240) - Default $MaxLogSizeKB bleibt bestehen."
        } else {
            $MaxLogSizeKB = $fileMaxLogSizeKB
            Write-Log -Level INFO -Message "MaxLogSizeKB aus Eingabe-Datei uebernommen: $MaxLogSizeKB"
        }
    }

    if ($inputCfg.Scope) {
        foreach ($prop in $inputCfg.Scope.PSObject.Properties) {
            if ($script:Scope.PSObject.Properties.Name -contains $prop.Name) {
                $script:Scope.$($prop.Name) = [bool]$prop.Value
                Write-Log -Level INFO -Message "Scope aus Eingabe-Datei: $($prop.Name) = $([bool]$prop.Value)"
            } else {
                Write-Log -Level WARN -Message "Unbekannter Scope-Schluessel in Eingabe-Datei ignoriert: '$($prop.Name)'"
            }
        }
    }
}

if ($ReportOnly) {
    #region -------------------------------------------------- Report-Modus ---
    $defs = New-CaroSettingDefinitions -ServiceAccount $ServiceAccount -MaxLogSizeKB $MaxLogSizeKB -Scope $script:Scope
    Write-Log -Level INFO -Message "Report-Modus: $($defs.Count) Einstellungen werden nur gelesen, nichts wird geaendert."

    $desiredDump = $defs | ForEach-Object {
        [pscustomobject]@{
            Id           = $_.Id
            Title        = $_.Title
            Description  = $_.Description
            DesiredValue = (& $_.Format $_.Desired)
            Command      = ($_.CommandTemplate -f (& $_.Format $_.Desired))
        }
    }
    $desiredDump | ConvertTo-Json -Depth 8 | Set-Content -Path $DesiredFile -Encoding UTF8
    Write-Log -Level INFO -Message "Zieleinstellungen (Referenz) geschrieben nach $DesiredFile"

    foreach ($def in $defs) {
        Invoke-CaroSetting -Def $def -TargetValue $def.Desired -Mode 'Report' | Out-Null
    }
    Save-Backup
    #endregion
} elseif ($RestoreFrom) {
    #region -------------------------------------------------- Rollback-Modus ---
    if (-not (Test-Path -Path $RestoreFrom)) {
        Write-Log -Level ERROR -Message "Backup-Datei nicht gefunden: $RestoreFrom"
        throw "Backup-Datei nicht gefunden: $RestoreFrom"
    }
    $loaded = @(Get-Content -Path $RestoreFrom -Raw | ConvertFrom-Json)
    Write-Log -Level INFO -Message "Rollback-Modus: $($loaded.Count) Eintraege aus '$RestoreFrom' geladen."

    if (-not $ServiceAccount) {
        $accountEntry = $loaded | Where-Object { $_.Id -eq 'EventLogReaders' } | Select-Object -First 1
        if ($accountEntry -and $accountEntry.Command -match '"([^"]+)"\s*/add') { $ServiceAccount = $Matches[1] }
    }

    $defs = New-CaroSettingDefinitions -ServiceAccount $ServiceAccount -MaxLogSizeKB $MaxLogSizeKB -Scope $script:Scope

    foreach ($entry in $loaded) {
        $def = $defs | Where-Object { $_.Id -eq $entry.Id } | Select-Object -First 1
        if (-not $def) {
            Write-Log -Level WARN -Message "[$($entry.Id)] Keine passende Definition im aktuellen Script gefunden - Rollback uebersprungen."
            continue
        }
        # Auch Eintraege mit einem Setzen-Fehler ("Fehler: ...") sind
        # restaurierbar, WENN dabei ein echter Originalwert gelesen wurde
        # (das Lesen war erfolgreich, nur das anschliessende Setzen nicht -
        # der urspruengliche Wert steht trotzdem korrekt im Backup). Ein
        # reiner Lesefehler ("Fehler beim Lesen", ohne Doppelpunkt) hat
        # dagegen keinen echten Wert und bleibt bewusst ausgeschlossen.
        $isRestorable = ($entry.Status -eq 'Geaendert') -or
                        ($entry.Status -like 'Fehler:*' -and $null -ne $entry.OriginalValueRaw)
        if (-not $isRestorable) {
            Write-Log -Level INFO -Message "[$($entry.Id)] Status war '$($entry.Status)' - kein Rollback noetig."
            continue
        }
        $result = Invoke-CaroSetting -Def $def -TargetValue $entry.OriginalValueRaw -Mode 'Restore'
        Save-Backup
        if ($result -eq 'Quit') {
            Write-Log -Level WARN -Message "Rollback durch Anwender abgebrochen."
            break
        }
    }
    #endregion
} else {
    #region -------------------------------------------------- Anwenden-Modus ---
    if (-not $ServiceAccount) {
        $answer = Read-Host "Domain\Benutzername des CARO-Servicekontos fuer die Gruppe 'Event Log Readers' (Enter = Schritt ueberspringen)"
        if ($answer) { $ServiceAccount = $answer }
    }

    $defs = New-CaroSettingDefinitions -ServiceAccount $ServiceAccount -MaxLogSizeKB $MaxLogSizeKB -Scope $script:Scope

    $desiredDump = $defs | ForEach-Object {
        [pscustomobject]@{
            Id           = $_.Id
            Title        = $_.Title
            Description  = $_.Description
            DesiredValue = (& $_.Format $_.Desired)
            Command      = ($_.CommandTemplate -f (& $_.Format $_.Desired))
        }
    }
    $desiredDump | ConvertTo-Json -Depth 8 | Set-Content -Path $DesiredFile -Encoding UTF8
    Write-Log -Level INFO -Message "Zieleinstellungen ($($defs.Count) Stueck) geschrieben nach $DesiredFile"

    foreach ($def in $defs) {
        $result = Invoke-CaroSetting -Def $def -TargetValue $def.Desired -Mode 'Apply'
        Save-Backup
        if ($result -eq 'Quit') {
            Write-Log -Level WARN -Message "Script durch Anwender abgebrochen."
            break
        }
    }
    #endregion
}

Save-Backup

$summary = $script:BackupEntries | Group-Object Status | Select-Object Name, Count
Write-Host ""
Write-Host "==================== Zusammenfassung ====================" -ForegroundColor White
foreach ($s in $summary) { Write-Host ("  {0,-28}: {1}" -f $s.Name, $s.Count) }
Write-Host ("  {0,-28}: {1}" -f 'Fehler gesamt', $script:ErrorCount)
Write-Host ("  {0,-28}: {1}" -f 'Warnungen gesamt', $script:WarningCount)
Write-Host ""
Write-Host "Log-Datei         : $LogFile"
Write-Host "Backup-Datei       : $BackupFile"
Write-Host "                     (Rollback: .\$(Split-Path -Leaf $PSCommandPath) -RestoreFrom '$BackupFile')"
if (-not $RestoreFrom) { Write-Host "Zieleinstellungen  : $DesiredFile" }

Write-Log -Level INFO -Message "Script beendet. Fehler=$script:ErrorCount Warnungen=$script:WarningCount"

if ($script:ErrorCount -gt 0) { exit 1 } else { exit 0 }
#endregion
