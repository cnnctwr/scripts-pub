# ============================================================
# CARO Suite - Download, Entpacken & Installation
# ============================================================

# --- Konfiguration -----------------------------------------------------------

$DownloadUrl  = "https://cusatum.de/wp-content/uploads/1618/31/CARO-Suite-Setup.zip"
$OriginalName = "CARO-Suite-Setup"

$DownloadsDir = [Environment]::GetFolderPath("UserProfile") + "\Downloads"
$Timestamp    = Get-Date -Format "yyyy-MM-dd-HHmmss"
$BaseName     = "$Timestamp-$OriginalName"
$ZipPath      = Join-Path $DownloadsDir "$BaseName.zip"
$ExtractDir   = Join-Path $DownloadsDir $BaseName

# --- Vorab-Versionspruefung (nur letzter Teil des ZIPs) ----------------------

Write-Host "Pruefe verfuegbare Version..."

$VerfuegbareVersion = $null
try {
    # Dateigroesse ermitteln
    $Head     = Invoke-WebRequest -Uri $DownloadUrl -Method Head -UseBasicParsing
    $FileSize = [long]$Head.Headers['Content-Length']
    $RangeStart = [Math]::Max(0, $FileSize - 1000)

    # Nur die letzten 1000 Byte laden
    $ProgressPreference = 'SilentlyContinue'
    $TailBytes = (Invoke-WebRequest -Uri $DownloadUrl `
        -Headers @{ Range = "bytes=$RangeStart-" } `
        -UseBasicParsing).Content

    # ZIP-Central-Directory nach MSI-Dateinamen durchsuchen
    for ($i = 0; $i -lt $TailBytes.Length - 46; $i++) {
        if ($TailBytes[$i]   -eq 0x50 -and $TailBytes[$i+1] -eq 0x4B -and
            $TailBytes[$i+2] -eq 0x01 -and $TailBytes[$i+3] -eq 0x02) {
            $NameLen = [BitConverter]::ToUInt16($TailBytes, $i + 28)
            if ($NameLen -gt 0 -and ($i + 46 + $NameLen) -le $TailBytes.Length) {
                $EntryName = [System.Text.Encoding]::UTF8.GetString($TailBytes, $i + 46, $NameLen)
                if ($EntryName -like "*.msi") {
                    if ($EntryName -match '(\d{4}\.\d+\.\d+\.\d+)') {
                        $VerfuegbareVersion = $matches[1]
                    }
                    break
                }
            }
        }
    }
} catch {
    # Vorab-Pruefung fehlgeschlagen - wird spaeter beim vollstaendigen Download erneut versucht
}

# --- Installierte Version aus der Registry lesen -----------------------------

$Installed = Get-ItemProperty `
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" `
    -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -like "*CARO*" } |
    Select-Object -First 1

$InstalliertVersion = $null
if ($Installed -and $Installed.DisplayName -match '(\d{4}\.\d+\.\d+\.\d+)') {
    $InstalliertVersion = $matches[1]
}

# --- Versionsvergleich und Benutzerentscheidung ------------------------------

if ($VerfuegbareVersion -and $InstalliertVersion) {
    $NeuV  = [Version]$VerfuegbareVersion
    $AltV  = [Version]$InstalliertVersion

    if ($NeuV -le $AltV) {
        Write-Host ""
        Write-Host "Verfuegbare Version:  $VerfuegbareVersion"
        Write-Host "Installierte Version: $InstalliertVersion"
        Write-Host ""
        Write-Host "Kein Update erforderlich."
        Write-Host ""
        Read-Host "Taste druecken zum Beenden"
        exit 0
    }
}

# Neue Version oder Erstinstallation
Write-Host ""
if ($VerfuegbareVersion) {
    Write-Host "Neue Version der CARO Suite gefunden: $VerfuegbareVersion"
} else {
    Write-Host "CARO Suite - Update / Installation"
}
if ($InstalliertVersion) {
    Write-Host "Installierte Version:  $InstalliertVersion"
    Write-Host "Verfuegbare Version:   $VerfuegbareVersion"
}
Write-Host ""
Write-Host "Die Lizenzbestimmungen liegen nach dem Download lesbar in folgendem Verzeichnis:"
Write-Host $ExtractDir
Write-Host ""
Write-Host "Wenn Sie mit 'Ja' antworten, stimmen Sie diesen Bedingungen zu"
Write-Host "und installieren die neueste Version der CARO Suite."
Write-Host ""
$Antwort = Read-Host "Wollen Sie fortfahren? (J/N)"
if ($Antwort -notmatch "^[Jj]$") { Write-Host "Abgebrochen."; exit 0 }

# --- Download ----------------------------------------------------------------

Write-Host ""
Write-Host "Lade herunter: $DownloadUrl"
Write-Host "Ziel:          $ZipPath"

$ProgressPreference = 'SilentlyContinue'
try {
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $ZipPath -UseBasicParsing
    Write-Host "Download abgeschlossen."
} catch {
    Write-Error "Download fehlgeschlagen: $_"
    exit 1
}

# --- Entpacken ---------------------------------------------------------------

Write-Host "Entpacke nach: $ExtractDir"

try {
    Expand-Archive -Path $ZipPath -DestinationPath $ExtractDir -Force
    Write-Host "Entpacken abgeschlossen."
} catch {
    Write-Error "Entpacken fehlgeschlagen: $_"
    exit 1
}

# --- ZIP loeschen ------------------------------------------------------------

Remove-Item -Path $ZipPath -Force
Write-Host "ZIP-Datei geloescht."

# --- MSI suchen --------------------------------------------------------------

$MsiFile = Get-ChildItem -Path $ExtractDir -Filter "*.msi" -Recurse | Select-Object -First 1

if (-not $MsiFile) {
    Write-Error "Keine MSI-Datei in '$ExtractDir' gefunden."
    exit 1
}

Write-Host "MSI gefunden: $($MsiFile.FullName)"

# --- Blockierung aufheben ----------------------------------------------------

Unblock-File -Path $MsiFile.FullName
Write-Host "Datei entsperrt."

# --- Installation ------------------------------------------------------------

Write-Host "Installiere CARO Suite..."
$InstallArgs = "/i `"$($MsiFile.FullName)`" /passive /norestart"

$Process = Start-Process -FilePath "msiexec.exe" -ArgumentList $InstallArgs -Wait -PassThru

if ($Process.ExitCode -eq 0) {
    Write-Host "Installation erfolgreich abgeschlossen."
} elseif ($Process.ExitCode -eq 3010) {
    Write-Host "Installation erfolgreich - Neustart erforderlich."
} else {
    Write-Warning "Installation beendet mit Exit-Code: $($Process.ExitCode)"
    Write-Warning "Nachschlagen: https://learn.microsoft.com/de-de/windows/win32/msi/error-codes"
}

Write-Host ""
Write-Host "Installiertes Paket liegt in: $ExtractDir"
Write-Host ""
Read-Host "Taste druecken zum Beenden"
