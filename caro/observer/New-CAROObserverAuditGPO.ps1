#Requires -Version 5.1
#Requires -RunAsAdministrator
#Requires -Modules GroupPolicy
<#
.SYNOPSIS
    Erstellt eine neue, dedizierte Gruppenrichtlinie (GPO) fuer die
    CARO-AD-Observer Audit-Voraussetzungen und verknuepft sie mit der
    Domain-Controllers-OU - der GPO-basierte Weg aus dem PDF
    ("Audit-Richtlinien konfigurieren"), als Alternative zum lokalen
    auditpol-Ansatz in Set-CAROObserverPrerequisites.ps1.

.DESCRIPTION
    WICHTIG - anders als Set-CAROObserverPrerequisites.ps1: Dieses Script
    schreibt in GETEILTE, domaenenweite Infrastruktur (eine neue GPO,
    verknuepft mit einer OU), nicht nur auf den lokalen Server. Jede Aktion
    wird einzeln im Klartext angezeigt und muss bestaetigt werden.

    Empfohlen, wenn -GPOCheck im Hauptscript einen Konflikt zwischen den
    lokal gesetzten Audit-Unterkategorien und einer bereits bestehenden GPO
    gemeldet hat (siehe README, Abschnitt "-GPOCheck").

    Die neu angelegte GPO enthaelt AUSSCHLIESSLICH die CARO-Anforderungen
    (Unterkategorien erzwingen + 9 Audit-Unterkategorien auf "Erfolg").
    Bestehender Inhalt anderer GPOs wird nicht veraendert.

    Rueckbau ueber -RemoveGPO: loest die Verknuepfung und loescht die GPO
    vollstaendig - sicher, da die GPO ausschliesslich von diesem Script
    angelegten Inhalt enthaelt, kein fremder Inhalt geht dabei verloren.

    ACHTUNG: Dieses Script wurde mangels Windows/AD-Testumgebung nicht gegen
    eine echte Domaene verifiziert. Unbedingt zuerst in einer isolierten
    Testdomaene ausprobieren und den erzeugten GPO-Inhalt in der
    Gruppenrichtlinienverwaltung (gpmc.msc) gegenpruefen, bevor es in einer
    produktiven Umgebung verwendet wird.

.PARAMETER GpoName
    Name der neu anzulegenden GPO. Default: "CARO-AD-Observer-Audit" (wie im
    PDF als Beispielname vorgeschlagen).

.PARAMETER TargetOU
    Distinguished Name der OU, mit der die GPO verknuepft wird.
    Default: "OU=Domain Controllers,<Domain-DN>" (Standard-Speicherort aller
    Domaenencontroller-Computerkonten).

.PARAMETER GpoLinkOrder
    Link-Prioritaet bei der Verknuepfung (1 = hoechste Prioritaet, gewinnt im
    Zweifel gegenueber anderen mit derselben OU verknuepften GPOs).
    Default: 1. Reine organisatorische Entscheidung, keine technische
    Vorgabe - bei eigenen GPO-Governance-Regeln entsprechend anpassen.

.PARAMETER OutputPath
    Verzeichnis fuer Log- und Backup-Datei.
    Default: .\CARO-Observer-Setup-Logs (dasselbe Verzeichnis wie beim
    Hauptscript Set-CAROObserverPrerequisites.ps1).

.PARAMETER RemoveGPO
    Rueckbau-Modus: entfernt die Verknuepfung und loescht die GPO, die in der
    per -BackupFile angegebenen Datei dokumentiert ist. Erfordert -BackupFile.

.PARAMETER BackupFile
    Pfad zur CARO-Observer-AuditGPO-Backup-*.json Datei eines frueheren,
    erfolgreichen Erstellungslaufs. Erforderlich bei -RemoveGPO.

.PARAMETER AutoApprove
    Ueberspringt die Einzelbestaetigung (weiterhin vollstaendig protokolliert).
    Angesichts der Tragweite (geteilte AD-Infrastruktur) nicht empfohlen.

.PARAMETER Detailed
    Zeigt im Terminal die vollstaendige Log-Ausgabe. Ohne diesen Schalter
    erscheint pro Schritt nur eine Statuszeile (OK / Warnung / Fehler);
    die Details stehen immer vollstaendig in der Log-Datei.

.EXAMPLE
    .\New-CAROObserverAuditGPO.ps1

.EXAMPLE
    .\New-CAROObserverAuditGPO.ps1 -GpoName "CARO-AD-Observer-Audit" -GpoLinkOrder 1

.EXAMPLE
    .\New-CAROObserverAuditGPO.ps1 -RemoveGPO -BackupFile ".\CARO-Observer-Setup-Logs\CARO-Observer-AuditGPO-Backup_DC01_20260929-101500.json"

.NOTES
    Benoetigt das GroupPolicy-PowerShell-Modul (RSAT-GPMC) - anders als das
    Hauptscript, das bewusst ohne dieses Modul auskommt. Installation bei
    Bedarf: Install-WindowsFeature GPMC (Server) bzw. RSAT-Group-Policy-LocalStore
    (Client-Feature).
#>
[CmdletBinding()]
param(
    [string]$GpoName = 'CARO-AD-Observer-Audit',
    [string]$TargetOU,
    [ValidateRange(1, 999)]
    [int]$GpoLinkOrder = 1,
    [string]$OutputPath = (Join-Path -Path $PSScriptRoot -ChildPath 'CARO-Observer-Setup-Logs'),
    [switch]$RemoveGPO,
    [string]$BackupFile,
    [switch]$AutoApprove,
    [switch]$Detailed
)

if ($RemoveGPO -and -not $BackupFile) {
    throw "-RemoveGPO erfordert -BackupFile <Pfad zur CARO-Observer-AuditGPO-Backup-*.json>."
}

$ErrorActionPreference = 'Stop'

if (-not (Get-Module -ListAvailable -Name GroupPolicy)) {
    throw "Das GroupPolicy-PowerShell-Modul (RSAT-GPMC) ist auf diesem Server nicht installiert. Installieren mit: Install-WindowsFeature GPMC"
}
Import-Module GroupPolicy -ErrorAction Stop

#region ---------------------------------------------------------- Grundgeruest ---
$scriptStart = Get-Date
$hostName    = $env:COMPUTERNAME

if (-not (Test-Path -Path $OutputPath)) {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
}

$stamp         = $scriptStart.ToString('yyyyMMdd-HHmmss')
$LogFile       = Join-Path $OutputPath "CARO-Observer-AuditGPO_${hostName}_$stamp.log"
$BackupOutFile = Join-Path $OutputPath "CARO-Observer-AuditGPO-Backup_${hostName}_$stamp.json"

$script:ApproveAll   = [bool]$AutoApprove
$script:ErrorCount   = 0
$script:WarningCount = 0
$script:LastIssue    = ''

function Write-Log {
    param(
        [Parameter(Mandatory)] [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'STEP', 'RESULT')] [string]$Level = 'INFO'
    )
    $line = "[{0:yyyy-MM-dd HH:mm:ss}] [{1,-6}] {2}" -f (Get-Date), $Level, $Message
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
    if ($Level -eq 'ERROR') { $script:ErrorCount++;   $script:LastIssue = $Message }
    if ($Level -eq 'WARN')  { $script:WarningCount++; $script:LastIssue = $Message }

    # Terminal: ohne -Detailed nur Statuszeilen (Write-StatusLine); alles
    # andere steht vollstaendig in der Log-Datei.
    if (-not $Detailed) { return }
    switch ($Level) {
        'ERROR'  { Write-Host $line -ForegroundColor Red }
        'WARN'   { Write-Host $line -ForegroundColor Yellow }
        'STEP'   { Write-Host $line -ForegroundColor Cyan }
        'RESULT' { Write-Host $line -ForegroundColor Green }
        default  { Write-Host $line }
    }
}

function Write-StatusLine {
    param(
        [Parameter(Mandatory)] [string]$Label,
        [Parameter(Mandatory)] [ValidateSet('OK', 'Uebersprungen', 'WARNUNG', 'FEHLER')] [string]$Status,
        [string]$Detail
    )
    $width = 52
    $text = if ($Label.Length -gt ($width - 4)) { $Label.Substring(0, $width - 6) + '..' } else { $Label }
    $dots = '.' * [Math]::Max(2, $width - $text.Length)
    $color = switch ($Status) {
        'OK'            { 'Green' }
        'Uebersprungen' { 'DarkGray' }
        'WARNUNG'       { 'Yellow' }
        'FEHLER'        { 'Red' }
    }
    if ($Detail.Length -gt 90) { $Detail = $Detail.Substring(0, 87) + '...' }
    $suffix = if ($Detail) { "  ($Detail)" } else { '' }
    Write-Host "$text $dots $Status$suffix" -ForegroundColor $color
}

function Confirm-Action {
    param(
        [Parameter(Mandatory)] [string]$Title,
        [Parameter(Mandatory)] [string]$Description,
        [string]$Command
    )
    Write-Host ""
    Write-Host "==================================================================" -ForegroundColor DarkGray
    Write-Host " $Title" -ForegroundColor White
    Write-Host "==================================================================" -ForegroundColor DarkGray
    Write-Host "Was wird gemacht:" -ForegroundColor Gray
    Write-Host "  $Description"
    if ($Command) {
        Write-Host ""
        Write-Host "Befehl / Mechanismus:" -ForegroundColor Gray
        Write-Host "  $Command" -ForegroundColor DarkYellow
    }
    Write-Log -Level STEP -Message "$Title | $Description"

    if ($script:ApproveAll) {
        Write-Host "(AutoApprove aktiv - wird automatisch ausgefuehrt)" -ForegroundColor DarkGray
        return $true
    }
    while ($true) {
        $answer = Read-Host "Ausfuehren? [J]a / [N]ein (abbrechen) / [A]lle weiteren automatisch Ja"
        switch ($answer.ToUpperInvariant()) {
            'J' { return $true }
            'A' { $script:ApproveAll = $true; return $true }
            'N' { return $false }
            default { Write-Host "Bitte J, N oder A eingeben." -ForegroundColor Yellow }
        }
    }
}
#endregion

Write-Host "==================================================================" -ForegroundColor White
Write-Host " CARO-AD-Observer - Audit-GPO $(if ($RemoveGPO) { 'entfernen' } else { 'anlegen' })" -ForegroundColor White
Write-Host "==================================================================" -ForegroundColor White
Write-Host "Server : $hostName"
Write-Host "Log    : $LogFile"
if (-not $RemoveGPO) {
    Write-Host ""
    Write-Host "HINWEIS: Dieses Script schreibt in geteilte AD/SYSVOL-Infrastruktur" -ForegroundColor Yellow
    Write-Host "(neue GPO, Verknuepfung mit einer OU) - nicht nur auf diesen Server." -ForegroundColor Yellow
    Write-Host "Zuerst in einer Testdomaene verifizieren, siehe README." -ForegroundColor Yellow
}
Write-Log -Level INFO -Message "Script gestartet. Modus=$(if ($RemoveGPO) { 'Remove' } else { 'Create' })"

try {
    $rootDse = [ADSI]'LDAP://RootDSE'
    $domainDN = [string]$rootDse.defaultNamingContext
    Write-Log -Level INFO -Message "Domain-DN ermittelt: $domainDN"
} catch {
    Write-Log -Level ERROR -Message "Domain-DN konnte nicht ermittelt werden: $($_.Exception.Message)"
    throw
}

if (-not $TargetOU) { $TargetOU = "OU=Domain Controllers,$domainDN" }

if ($RemoveGPO) {
    #region -------------------------------------------------- Rueckbau ---
    if (-not (Test-Path -Path $BackupFile)) { throw "Backup-Datei nicht gefunden: $BackupFile" }
    $info = Get-Content -Path $BackupFile -Raw | ConvertFrom-Json
    Write-Log -Level INFO -Message "Laut Backup zu entfernen: GPO '$($info.GpoName)' (GUID $($info.GpoGuid)), verknuepft mit '$($info.TargetOU)'."

    $gpo = $null
    try { $gpo = Get-GPO -Guid $info.GpoGuid -ErrorAction Stop } catch {
        Write-Log -Level WARN -Message "GPO mit GUID $($info.GpoGuid) nicht gefunden - moeglicherweise bereits entfernt."
    }

    if ($gpo) {
        $doUnlink = Confirm-Action -Title "Verknuepfung entfernen" `
            -Description "Die Verknuepfung von GPO '$($gpo.DisplayName)' mit '$($info.TargetOU)' wird geloest." `
            -Command "Remove-GPLink -Guid $($info.GpoGuid) -Target '$($info.TargetOU)'"
        if ($doUnlink) {
            try {
                Remove-GPLink -Guid $info.GpoGuid -Target $info.TargetOU -ErrorAction Stop | Out-Null
                Write-Log -Level RESULT -Message "Verknuepfung entfernt."
                Write-StatusLine -Label "Verknuepfung entfernen" -Status OK
            } catch {
                Write-Log -Level WARN -Message "Verknuepfung konnte nicht entfernt werden (evtl. bereits geloest): $($_.Exception.Message)"
                Write-StatusLine -Label "Verknuepfung entfernen" -Status WARNUNG -Detail "evtl. bereits geloest"
            }
        } else {
            Write-StatusLine -Label "Verknuepfung entfernen" -Status Uebersprungen
        }

        $doDelete = Confirm-Action -Title "GPO loeschen" `
            -Description "Die GPO '$($gpo.DisplayName)' (GUID $($info.GpoGuid)) wird vollstaendig geloescht. Da sie ausschliesslich von diesem Script angelegten Inhalt enthaelt, ist das sicher - kein fremder Inhalt geht verloren." `
            -Command "Remove-GPO -Guid $($info.GpoGuid)"
        if ($doDelete) {
            try {
                Remove-GPO -Guid $info.GpoGuid -ErrorAction Stop
                Write-Log -Level RESULT -Message "GPO geloescht."
                Write-StatusLine -Label "GPO loeschen" -Status OK
            } catch {
                Write-Log -Level ERROR -Message "GPO konnte nicht geloescht werden: $($_.Exception.Message)"
                Write-StatusLine -Label "GPO loeschen" -Status FEHLER -Detail $_.Exception.Message
            }
        } else {
            Write-StatusLine -Label "GPO loeschen" -Status Uebersprungen
        }
    } else {
        Write-Log -Level INFO -Message "Nichts zu tun - GPO existiert nicht (mehr)."
        Write-StatusLine -Label "GPO loeschen" -Status Uebersprungen -Detail "GPO existiert nicht (mehr)"
    }
    #endregion
} else {
    #region -------------------------------------------------- Erstellung ---
    # Dieselben Well-Known-GUIDs wie in Set-CAROObserverPrerequisites.ps1 -
    # sprachunabhaengig, siehe dortige Begruendung. Labels hier bewusst die
    # englischen Microsoft-Kanonnamen (nur Anzeige in der audit.csv, fuer die
    # tatsaechliche Anwendung zaehlt ausschliesslich die GUID-Spalte).
    $auditSubcategories = [ordered]@{
        '0CCE9235-69AE-11D9-BED3-505054503030' = 'User Account Management'
        '0CCE9236-69AE-11D9-BED3-505054503030' = 'Computer Account Management'
        '0CCE9237-69AE-11D9-BED3-505054503030' = 'Security Group Management'
        '0CCE9238-69AE-11D9-BED3-505054503030' = 'Distribution Group Management'
        '0CCE9239-69AE-11D9-BED3-505054503030' = 'Application Group Management'
        '0CCE923A-69AE-11D9-BED3-505054503030' = 'Other Account Management Events'
        '0CCE923B-69AE-11D9-BED3-505054503030' = 'Directory Service Access'
        '0CCE923C-69AE-11D9-BED3-505054503030' = 'Directory Service Changes'
        '0CCE922F-69AE-11D9-BED3-505054503030' = 'Audit Policy Change'
    }

    $existingGpo = Get-GPO -Name $GpoName -ErrorAction SilentlyContinue
    if ($existingGpo) {
        throw "Eine GPO namens '$GpoName' existiert bereits (GUID $($existingGpo.Id)). Bitte -GpoName anders waehlen oder die bestehende GPO zuerst mit -RemoveGPO entfernen."
    }

    $doCreate = Confirm-Action -Title "Neue GPO anlegen" `
        -Description "Legt eine neue, leere Gruppenrichtlinie namens '$GpoName' an (noch nicht verknuepft, noch ohne Audit-Inhalt)." `
        -Command "New-GPO -Name '$GpoName'"
    if (-not $doCreate) {
        Write-Log -Level WARN -Message "Abgebrochen vor GPO-Erstellung."
        Write-StatusLine -Label "GPO anlegen" -Status Uebersprungen -Detail "abgebrochen"
        exit 1
    }

    $gpo = New-GPO -Name $GpoName -Comment "Erstellt von New-CAROObserverAuditGPO.ps1 am $($scriptStart.ToString('yyyy-MM-dd HH:mm:ss')) - Audit-Voraussetzungen fuer CARO-AD-Observer (PDF 'Audit-Richtlinien konfigurieren')."
    Write-Log -Level RESULT -Message "GPO angelegt: '$($gpo.DisplayName)', GUID $($gpo.Id)."
    Write-StatusLine -Label "GPO anlegen" -Status OK

    $domainDns = ($domainDN -split ',' | ForEach-Object { $_ -replace '^DC=', '' }) -join '.'
    $sysvolGpoPath = "\\$domainDns\SYSVOL\$domainDns\Policies\{$($gpo.Id)}"

    # --- Unterkategorien erzwingen (Sicherheitsoption -> GptTmpl.inf) ---
    $doForce = Confirm-Action -Title "'Unterkategorien erzwingen' in der GPO setzen" `
        -Description "Sicherheitsoption 'Ueberwachung: Unterkategorieeinstellungen der Ueberwachungsrichtlinie erzwingen' wird aktiviert (PDF Schritt 4 - muss als Erstes stehen, sonst koennen die Unterkategorien unten ignoriert werden)." `
        -Command "GptTmpl.inf [Registry Values]: MACHINE\System\CurrentControlSet\Control\Lsa\SCENoApplyLegacyAuditPolicy=4,1"
    if ($doForce) {
        $secEditDir = Join-Path $sysvolGpoPath 'Machine\Microsoft\Windows NT\SecEdit'
        New-Item -Path $secEditDir -ItemType Directory -Force | Out-Null
        $gptTmplPath = Join-Path $secEditDir 'GptTmpl.inf'
        $gptTmplContent = @(
            '[Unicode]'
            'Unicode=yes'
            '[Version]'
            'signature="$CHICAGO$"'
            'Revision=1'
            '[Registry Values]'
            'MACHINE\System\CurrentControlSet\Control\Lsa\SCENoApplyLegacyAuditPolicy=4,1'
        )
        Set-Content -Path $gptTmplPath -Value $gptTmplContent -Encoding Unicode
        Write-Log -Level RESULT -Message "GptTmpl.inf geschrieben: $gptTmplPath"
        Write-StatusLine -Label "Unterkategorien erzwingen (GPO-Inhalt)" -Status OK
    } else {
        Write-StatusLine -Label "Unterkategorien erzwingen (GPO-Inhalt)" -Status Uebersprungen
    }

    # --- Audit-Unterkategorien (audit.csv) ---
    $doAudit = Confirm-Action -Title "9 Audit-Unterkategorien in der GPO setzen" `
        -Description "Kontenverwaltung (6 Unterkategorien), DS-Zugriff (2: Verzeichnisdienstzugriff/-aenderungen), Richtlinienaenderung (1) werden jeweils auf 'Erfolg' gesetzt." `
        -Command "audit.csv mit $($auditSubcategories.Count) Zeilen, Setting Value=1 (Erfolg) je Unterkategorie"
    if ($doAudit) {
        $auditDir = Join-Path $sysvolGpoPath 'Machine\Microsoft\Windows NT\Audit'
        New-Item -Path $auditDir -ItemType Directory -Force | Out-Null
        $auditCsvPath = Join-Path $auditDir 'audit.csv'
        $csvLines = @('Machine Name,Policy Target,Subcategory,Subcategory GUID,Inclusion Setting,Exclusion Setting,Setting Value')
        foreach ($guid in $auditSubcategories.Keys) {
            $label = $auditSubcategories[$guid]
            $csvLines += ",System,$label,{$guid},Success,,1"
        }
        Set-Content -Path $auditCsvPath -Value $csvLines -Encoding UTF8
        Write-Log -Level RESULT -Message "audit.csv geschrieben: $auditCsvPath ($($auditSubcategories.Count) Unterkategorien)."
        Write-StatusLine -Label "9 Audit-Unterkategorien (GPO-Inhalt)" -Status OK
    } else {
        Write-StatusLine -Label "9 Audit-Unterkategorien (GPO-Inhalt)" -Status Uebersprungen
    }

    # --- Client-Side-Extensions registrieren (gPCMachineExtensionNames) ---
    # Ohne diesen Eintrag weiss der Group-Policy-Client nicht, dass diese GPO
    # ueberhaupt Computer-Inhalt hat - sie wuerde bei jedem Refresh ignoriert
    # und taucht nicht einmal unter "Angewendete Gruppenrichtlinienobjekte"
    # auf, obwohl Verknuepfung/Berechtigungen/Inhalt korrekt sind (live
    # verifiziert). Normalerweise setzen GPMC/die GroupPolicy-Cmdlets dieses
    # Attribut automatisch beim Bearbeiten einer Einstellung ueber die GUI;
    # da wir audit.csv/GptTmpl.inf direkt ins SYSVOL schreiben, muss es hier
    # manuell nachgezogen werden. Die beiden GUID-Paare sind feste, windows-
    # weit identische Kennungen (nicht domaenenspezifisch):
    #   - Sicherheitseinstellungen (verarbeitet GptTmpl.inf): live aus einer
    #     uebers GPMC erzeugten Test-GPO verifiziert.
    #   - Audit-Richtlinienkonfiguration (verarbeitet audit.csv): laut
    #     offizieller Microsoft-Spezifikation [MS-GPAC], Abschnitt
    #     "Audit Configuration Extension"
    #     (learn.microsoft.com/en-us/openspecs/windows_protocols/ms-gpac).
    $cseSecuritySettings = '{827D319E-6EAC-11D2-A4EA-00C04F79F83A}{803E14A0-B4FB-11D0-A0D0-00A0C90F574B}'
    $cseAuditPolicy      = '{F3CCC681-B74C-4060-9F26-CD84525DCA2A}{0F3F3735-573D-9804-99E4-AB2A69BA5FD4}'
    $extensionParts = @()
    if ($doForce) { $extensionParts += $cseSecuritySettings }
    if ($doAudit) { $extensionParts += $cseAuditPolicy }

    if ($extensionParts.Count -gt 0) {
        $extensionNames = ($extensionParts | ForEach-Object { "[$_]" }) -join ''
        $doExtensions = Confirm-Action -Title "Client-Side-Extensions in der GPO registrieren" `
            -Description "Traegt im AD-Attribut 'gPCMachineExtensionNames' ein, dass die GPO Sicherheitseinstellungen- und/oder Audit-Richtlinien-Inhalt enthaelt. Zwingend noetig, sonst wird der oben geschriebene Inhalt vom Client ignoriert." `
            -Command "AD-Attribut gPCMachineExtensionNames = $extensionNames"
        if ($doExtensions) {
            try {
                $gpoExtEntry = [ADSI]"LDAP://CN={$($gpo.Id)},CN=Policies,CN=System,$domainDN"
                $gpoExtEntry.psbase.Properties['gPCMachineExtensionNames'].Value = $extensionNames
                $gpoExtEntry.psbase.CommitChanges()
                Write-Log -Level RESULT -Message "gPCMachineExtensionNames gesetzt: $extensionNames"
                Write-StatusLine -Label "Client-Side-Extensions registrieren" -Status OK
            } catch {
                Write-Log -Level ERROR -Message "gPCMachineExtensionNames konnte nicht gesetzt werden: $($_.Exception.Message)"
                Write-StatusLine -Label "Client-Side-Extensions registrieren" -Status FEHLER -Detail $_.Exception.Message
            }
        } else {
            Write-StatusLine -Label "Client-Side-Extensions registrieren" -Status Uebersprungen
        }
    }

    # --- Versionsnummer aktualisieren, damit DCs den neuen Inhalt erkennen ---
    $doVersion = Confirm-Action -Title "GPO-Version aktualisieren" `
        -Description "Erhoeht die Versionsnummer der GPO (GPT.INI + passendes AD-Attribut), damit Domaenencontroller den neuen Inhalt beim naechsten Sicherheitsrichtlinien-Refresh uebernehmen." `
        -Command "GPT.INI: Version= (Computer-Anteil +1); AD-Attribut versionNumber auf denselben Wert gesetzt"
    if ($doVersion) {
        $gptIniPath = Join-Path $sysvolGpoPath 'GPT.INI'
        $currentVersion = [uint32]0
        if (Test-Path -Path $gptIniPath) {
            $iniContent = Get-Content -Path $gptIniPath -ErrorAction SilentlyContinue
            $versionLine = $iniContent | Where-Object { $_ -match '^Version=(\d+)' } | Select-Object -First 1
            if ($versionLine -and $versionLine -match '^Version=(\d+)') { $currentVersion = [uint32]$Matches[1] }
        }
        $computerVersion = [uint32]((($currentVersion -band 0xFFFF) + 1) -band 0xFFFF)
        $userVersion     = [uint32](($currentVersion -shr 16) -band 0xFFFF)
        $newVersion      = [uint32](($userVersion -shl 16) -bor $computerVersion)

        Set-Content -Path $gptIniPath -Value @('[General]', "Version=$newVersion") -Encoding ASCII
        Write-Log -Level RESULT -Message "GPT.INI aktualisiert: Version=$newVersion (Computer-Anteil $computerVersion)."

        try {
            $gpoEntry = [ADSI]"LDAP://CN={$($gpo.Id)},CN=Policies,CN=System,$domainDN"
            $gpoEntry.psbase.Properties['versionNumber'].Value = [int]$newVersion
            $gpoEntry.psbase.CommitChanges()
            Write-Log -Level RESULT -Message "AD-Attribut versionNumber aktualisiert: $newVersion."
            Write-StatusLine -Label "GPO-Version aktualisieren" -Status OK
        } catch {
            Write-Log -Level WARN -Message "AD-Attribut versionNumber konnte nicht gesetzt werden: $($_.Exception.Message) - GPO wird evtl. erst beim naechsten regulaeren Refresh vollstaendig erkannt."
            Write-StatusLine -Label "GPO-Version aktualisieren" -Status WARNUNG -Detail "AD-Attribut nicht gesetzt - Details im Log"
        }
    } else {
        Write-StatusLine -Label "GPO-Version aktualisieren" -Status Uebersprungen
    }

    # --- Mit OU verknuepfen ---
    $doLink = Confirm-Action -Title "GPO mit OU verknuepfen" `
        -Description "Verknuepft '$GpoName' mit '$TargetOU', Link-Prioritaet $GpoLinkOrder (1 = hoechste)." `
        -Command "New-GPLink -Guid $($gpo.Id) -Target '$TargetOU' -Order $GpoLinkOrder -LinkEnabled Yes"
    $linked = $false
    if ($doLink) {
        try {
            New-GPLink -Guid $gpo.Id -Target $TargetOU -Order $GpoLinkOrder -LinkEnabled Yes -ErrorAction Stop | Out-Null
            Write-Log -Level RESULT -Message "GPO verknuepft mit '$TargetOU', Link-Prioritaet $GpoLinkOrder."
            $linked = $true
            Write-StatusLine -Label "GPO mit OU verknuepfen" -Status OK
        } catch {
            Write-Log -Level ERROR -Message "Verknuepfung fehlgeschlagen: $($_.Exception.Message)"
            Write-StatusLine -Label "GPO mit OU verknuepfen" -Status FEHLER -Detail $_.Exception.Message
        }
    } else {
        Write-StatusLine -Label "GPO mit OU verknuepfen" -Status Uebersprungen
    }

    $backupInfo = [pscustomobject]@{
        GpoName   = $GpoName
        GpoGuid   = [string]$gpo.Id
        TargetOU  = $TargetOU
        LinkOrder = $GpoLinkOrder
        Linked    = $linked
        CreatedAt = $scriptStart.ToString('o')
        Server    = $hostName
    }
    $backupInfo | ConvertTo-Json | Set-Content -Path $BackupOutFile -Encoding UTF8
    Write-Log -Level INFO -Message "Backup-Datei fuer Rueckbau geschrieben: $BackupOutFile"

    Write-Host ""
    Write-Host "==================== Fertig ====================" -ForegroundColor White
    Write-Host "GPO '$GpoName' (GUID $($gpo.Id)) angelegt$(if ($linked) { " und verknuepft" } else { ", ABER NICHT verknuepft" })."
    Write-Host "Rueckbau: .\New-CAROObserverAuditGPO.ps1 -RemoveGPO -BackupFile '$BackupOutFile'"
    Write-Host "Hinweis: Es kann einige Minuten dauern (AD-/SYSVOL-Replikation, Sicherheitsrichtlinien-Refresh),"
    Write-Host "bis alle Domaenencontroller die neue GPO vollstaendig anwenden."
    #endregion
}

Write-Log -Level INFO -Message "Script beendet. Fehler=$script:ErrorCount Warnungen=$script:WarningCount"

Write-Host ""
if ($script:ErrorCount -gt 0) {
    Write-Host "GESAMTERGEBNIS: FEHLER ($script:ErrorCount Fehler, $script:WarningCount Warnungen) - Details in der Log-Datei: $LogFile" -ForegroundColor Red
} elseif ($script:WarningCount -gt 0) {
    Write-Host "GESAMTERGEBNIS: mit Warnungen ($script:WarningCount) - Details in der Log-Datei: $LogFile" -ForegroundColor Yellow
} else {
    Write-Host "GESAMTERGEBNIS: OK (Log: $LogFile)" -ForegroundColor Green
}
