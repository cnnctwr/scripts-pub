<#
================================================================
 Notepad++ Auto-Update
================================================================
 Haelt eine bestehende Notepad++-Installation auf einem Windows
 Server aktuell (offizieller silent Installer von GitHub Releases).

 - Kompatibel mit Windows PowerShell 5.1 und PowerShell 7+
 - Legt bei Bedarf selbst eine geplante Aufgabe an
   (woechentlich, Sonntag 03:00 Uhr)
 - Bricht ab, wenn Notepad++ gerade laeuft
 - Prueft die Version VOR dem Download (kein unnoetiger Download)
 - Schreibt pro Lauf ein eigenes Log nach %ProgramData%\Notepad++
 - Raeumt temporaere Dateien in jedem Fall auf (Erfolg/Abbruch/Fehler)

 Ablage: manuell nach C:\Scripts kopieren.
================================================================
#>

#Requires -Version 5.1
#Requires -RunAsAdministrator

# --- Konfiguration ---------------------------------------------------------

$TaskName     = "Notepad++ Update"
$LogDir       = Join-Path $env:ProgramData "Notepad++"
$GitHubApiUrl = "https://api.github.com/repos/notepad-plus-plus/notepad-plus-plus/releases/latest"

$ScriptPath = $PSCommandPath
if (-not $ScriptPath) { $ScriptPath = $MyInvocation.MyCommand.Path }

# --- Log-Setup ---------------------------------------------------------------

if (-not (Test-Path -LiteralPath $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}
$LogFile = Join-Path $LogDir ((Get-Date -Format "yyyy-MM-dd-HH-mm") + "-Update.log")

function Write-Log {
    param(
        [Parameter(Mandatory)] [string] $Message,
        [ValidateSet("INFO", "WARN", "ERROR")] [string] $Level = "INFO"
    )
    $line = "{0} [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
    Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
    switch ($Level) {
        "ERROR" { Write-Host $line -ForegroundColor Red }
        "WARN"  { Write-Host $line -ForegroundColor Yellow }
        default { Write-Host $line }
    }
}

$ExitCode = 0
$TempDir  = $null

try {
    Write-Log "=== Notepad++ Update-Skript gestartet (PowerShell $($PSVersionTable.PSVersion)) ==="

    # Aeltere Server-Defaults (v.a. .NET Framework / Windows PowerShell 5.1)
    # verlangen TLS 1.2 explizit, sonst schlaegt der Zugriff auf GitHub fehl.
    try { [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 } catch {}

    # --- Schritt 1: Versionspruefung ----------------------------------------
    Write-Log "Schritt 1/5: Versionspruefung - ermittle installierte Notepad++-Version..."

    $uninstallPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Notepad++",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Notepad++"
    )

    $installedVersion = $null
    $installDir       = $null

    foreach ($p in $uninstallPaths) {
        if (Test-Path -LiteralPath $p) {
            $regEntry = Get-ItemProperty -LiteralPath $p -ErrorAction SilentlyContinue
            if ($regEntry.DisplayVersion)  { $installedVersion = $regEntry.DisplayVersion }
            if ($regEntry.InstallLocation) { $installDir = $regEntry.InstallLocation.TrimEnd('\') }
            if ($installedVersion) { break }
        }
    }

    if (-not $installDir) {
        $candidates = @(
            (Join-Path $env:ProgramFiles "Notepad++")
        )
        if (${env:ProgramFiles(x86)}) { $candidates += (Join-Path ${env:ProgramFiles(x86)} "Notepad++") }

        foreach ($candidate in $candidates) {
            if (Test-Path -LiteralPath (Join-Path $candidate "notepad++.exe")) {
                $installDir = $candidate
                break
            }
        }
    }

    if ($installDir -and -not $installedVersion) {
        $exePath = Join-Path $installDir "notepad++.exe"
        if (Test-Path -LiteralPath $exePath) {
            $installedVersion = (Get-Item -LiteralPath $exePath).VersionInfo.ProductVersion
        }
    }

    if ($installDir) {
        Write-Log "Bestehende Installation gefunden: Verzeichnis '$installDir', Version '$installedVersion'."
    } else {
        $installDir = Join-Path $env:ProgramFiles "Notepad++"
        Write-Log "Keine bestehende Installation gefunden. Erstinstallation nach '$installDir' vorgesehen." -Level WARN
    }

    Write-Log "Frage aktuelle Version bei der GitHub Releases API ab..."
    try {
        $release = Invoke-RestMethod -Uri $GitHubApiUrl -Headers @{ "User-Agent" = "NppUpdateScript" } -UseBasicParsing
    } catch {
        Write-Log "Abfrage der GitHub-API fehlgeschlagen: $($_.Exception.Message)" -Level ERROR
        throw
    }
    $latestVersion = $release.tag_name.TrimStart('v')
    Write-Log "Aktuelle Version laut GitHub: $latestVersion"

    # Windows-Dateiversionen sind immer 4-stellig (z.B. 8.9.7.0), GitHub-Tags
    # sind 3-stellig (8.9.7) - daher fuer den Vergleich auf 3 Stellen kuerzen.
    $installedVersionShort = if ($installedVersion) { ($installedVersion -split '\.')[0..2] -join '.' } else { $null }
    $latestVersionShort    = ($latestVersion -split '\.')[0..2] -join '.'

    $updateNeeded = -not ($installedVersionShort -and ($installedVersionShort -eq $latestVersionShort))
    if ($updateNeeded) {
        Write-Log "Update erforderlich: '$installedVersion' -> '$latestVersion'."
    } else {
        Write-Log "Installierte Version entspricht der aktuellen Version. Kein Update noetig."
    }

    # --- Schritt 2: Pruefung geplante Aufgabe -------------------------------
    Write-Log "Schritt 2/5: Pruefe geplante Aufgabe '$TaskName'..."

    $existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if (-not $existingTask) {
        Write-Log "Geplante Aufgabe nicht gefunden. Lege sie an (woechentlich, Sonntag 03:00 Uhr, Ausfuehrung als SYSTEM)..."
        try {
            $hostExe = (Get-Process -Id $PID).Path
            if (-not $hostExe) { $hostExe = "powershell.exe" }
            $argString = '-NoProfile -ExecutionPolicy Bypass -File "' + $ScriptPath + '"'

            $action    = New-ScheduledTaskAction -Execute $hostExe -Argument $argString
            $trigger   = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At "03:00"
            $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
            $settings  = New-ScheduledTaskSettingsSet -StartWhenAvailable

            Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
                -Principal $principal -Settings $settings `
                -Description "Haelt Notepad++ automatisch aktuell (silent)." -Force | Out-Null

            Write-Log "Geplante Aufgabe erfolgreich angelegt (Aktion: `"$hostExe`" $argString)."
        } catch {
            Write-Log "Anlegen der geplanten Aufgabe fehlgeschlagen: $($_.Exception.Message)" -Level ERROR
        }
    } else {
        Write-Log "Geplante Aufgabe existiert bereits."
    }

    if (-not $updateNeeded) {
        Write-Log "=== Skript erfolgreich beendet (kein Update erforderlich) ==="
        exit 0
    }

    # Vor dem Download pruefen, ob Notepad++ laeuft - spart bei laufendem
    # Prozess einen unnoetigen Download und bricht sauber ab.
    Write-Log "Pruefe ob Notepad++ aktuell ausgefuehrt wird..."
    if (Get-Process -Name "notepad++" -ErrorAction SilentlyContinue) {
        Write-Log "Notepad++ wird gerade ausgefuehrt. Installation wird abgebrochen." -Level WARN
        Write-Log "=== Skript beendet (abgebrochen, Prozess aktiv) ==="
        exit 1
    }
    Write-Log "Notepad++ laeuft nicht. Fahre fort."

    # --- Schritt 3: Download --------------------------------------------------
    Write-Log "Schritt 3/5: Download - ermittle passendes Installer-Paket..."

    $arch = $env:PROCESSOR_ARCHITECTURE
    if ($arch -eq "ARM64") {
        $assetPattern = "*Installer.arm64.exe"
    } elseif ([Environment]::Is64BitOperatingSystem) {
        $assetPattern = "*Installer.x64.exe"
    } else {
        $assetPattern = "*Installer.exe"
    }
    Write-Log "Erkannte Architektur: $arch -> Asset-Muster '$assetPattern'"

    $asset = $release.assets | Where-Object { $_.name -like $assetPattern } | Select-Object -First 1
    if (-not $asset) {
        Write-Log "Kein passendes Installer-Asset fuer Muster '$assetPattern' gefunden." -Level ERROR
        throw "Kein Installer-Asset gefunden."
    }
    Write-Log "Installer-Asset gefunden: $($asset.name)"

    $TempDir = Join-Path $env:TEMP ("NppUpdate_" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
    $installerPath = Join-Path $TempDir $asset.name

    Write-Log "Lade Installer herunter nach '$installerPath'..."
    $ProgressPreference = "SilentlyContinue"
    try {
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $installerPath -UseBasicParsing
        Write-Log "Download abgeschlossen ($((Get-Item -LiteralPath $installerPath).Length) Bytes)."
    } catch {
        Write-Log "Download fehlgeschlagen: $($_.Exception.Message)" -Level ERROR
        throw
    }

    # --- Schritt 4: Entpacken --------------------------------------------------
    # Der offizielle Installer ist eine einzelne EXE (kein Archiv). An Stelle
    # eines Entpack-Schritts wird hier die Authenticode-Signatur geprueft,
    # um die Integritaet des heruntergeladenen Installers sicherzustellen.
    Write-Log "Schritt 4/5: Entpacken/Integritaetspruefung - pruefe Authenticode-Signatur..."
    $sig = Get-AuthenticodeSignature -LiteralPath $installerPath
    if ($sig.Status -ne "Valid") {
        Write-Log "Signaturpruefung fehlgeschlagen: Status '$($sig.Status)'." -Level ERROR
        throw "Ungueltige Signatur des heruntergeladenen Installers."
    }
    Write-Log "Signatur gueltig. Aussteller: $($sig.SignerCertificate.Subject)"

    # Erneute Pruefung unmittelbar vor der Installation: Notepad++ koennte
    # waehrend des Downloads gestartet worden sein.
    if (Get-Process -Name "notepad++" -ErrorAction SilentlyContinue) {
        Write-Log "Notepad++ wurde waehrend des Downloads gestartet. Installation wird abgebrochen." -Level WARN
        exit 1
    }

    # --- Schritt 5: Installieren -----------------------------------------------
    Write-Log "Schritt 5/5: Installieren - starte silent Installation nach '$installDir'..."

    # ProcessStartInfo.Arguments (roher String) statt Start-Process -ArgumentList
    # verwenden: nur so bleibt das NSIS-Flag /D=<Pfad> auf PS 5.1 UND PS7
    # garantiert unquotiert (NSIS verbietet Anfuehrungszeichen bei /D=).
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName        = $installerPath
    $psi.Arguments       = "/S /D=$installDir"
    $psi.UseShellExecute = $false

    $proc = [System.Diagnostics.Process]::Start($psi)
    $proc.WaitForExit()

    if ($proc.ExitCode -ne 0) {
        Write-Log "Installation fehlgeschlagen (Exit-Code $($proc.ExitCode))." -Level ERROR
        throw "Installer beendet mit Exit-Code $($proc.ExitCode)."
    }
    Write-Log "Installer erfolgreich beendet (Exit-Code 0)."

    Start-Sleep -Seconds 2
    $exePath = Join-Path $installDir "notepad++.exe"
    if (Test-Path -LiteralPath $exePath) {
        $newVersion = (Get-Item -LiteralPath $exePath).VersionInfo.ProductVersion
        Write-Log "Installierte Version nach Update: $newVersion"
        # Windows-Dateiversionen sind immer 4-stellig (z.B. 8.9.7.0), GitHub-Tags
        # sind 3-stellig (8.9.7) - daher fuer den Vergleich auf 3 Stellen kuerzen.
        $newVersionShort    = ($newVersion -split '\.')[0..2] -join '.'
        $latestVersionShort = ($latestVersion -split '\.')[0..2] -join '.'
        if ($newVersionShort -ne $latestVersionShort) {
            Write-Log "Installierte Version ($newVersion) weicht von erwarteter Version ($latestVersion) ab." -Level WARN
        }
    } else {
        Write-Log "notepad++.exe wurde nach der Installation nicht unter '$installDir' gefunden." -Level ERROR
        $ExitCode = 2
    }

    Write-Log "=== Skript erfolgreich beendet ==="
}
catch {
    Write-Log "Unerwarteter Fehler: $($_.Exception.Message)" -Level ERROR
    Write-Log "=== Skript mit Fehler beendet ===" -Level ERROR
    $ExitCode = 2
}
finally {
    if ($TempDir -and (Test-Path -LiteralPath $TempDir)) {
        Write-Log "Raeume temporaeres Verzeichnis '$TempDir' auf..."
        Remove-Item -LiteralPath $TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

exit $ExitCode
