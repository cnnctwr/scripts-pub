# ================================================================
# CARO-Suite - Download, Entpacken & Installation
# =================================================================
# Dieses Skript lädt die aktuelle Version der CARO-Suite herunter, entpackt sie und installiert sie.
# Es prüft auch, ob bereits eine Version installiert ist und zeigt entsprechend den Wartungsdialog an.
#
# Datei mit der Endung .ps1 auf dem CARO-Server speichern und mit PowerShell ausführen (Rechtsklick -> "Mit PowerShell ausführen").
# Nach dem ersten Ausführen wird ein Shortcut auf dem Desktop erstellt, um den Prozess in Zukunft mit einem Doppelklick zu starten.
#
# Kompatibel mit PowerShell 5.1 und höher (inkl. PowerShell Core).
# =================================================================

# --- Self-Unblock ---
try {
    Unblock-File -Path $MyInvocation.MyCommand.Path -ErrorAction SilentlyContinue
} catch {}

# --- Konfiguration -----------------------------------------------------------

$DownloadUrl  = "https://cusatum.de/wp-content/uploads/1618/31/CARO-Suite-Setup.zip"
$OriginalName = "CARO-Suite-Setup"   # Dateiname ohne .zip

# Downloads-Verzeichnis des aktuellen Benutzers
$DownloadsDir = [Environment]::GetFolderPath("UserProfile") + "\Downloads"

# Zeitstempel fuer Umbenennung und Zielordner
$Timestamp    = Get-Date -Format "yyyy-MM-dd-HHmmss"
$BaseName     = "$Timestamp-$OriginalName"
$ZipPath      = Join-Path $DownloadsDir "$BaseName.zip"
$ExtractDir   = Join-Path $DownloadsDir $BaseName

# --- Shortcut auf Desktop erstellen ---
$ScriptPath   = $MyInvocation.MyCommand.Path
$ShortcutPath = "$env:USERPROFILE\Desktop\CARO Auto-Updater.lnk"

if (-not (Test-Path $ShortcutPath)) {
    $WScriptShell = New-Object -ComObject WScript.Shell

    $Shortcut = $WScriptShell.CreateShortcut($ShortcutPath)
    $Shortcut.TargetPath = "powershell.exe"
    $Shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""
    $Shortcut.WorkingDirectory = Split-Path $ScriptPath
    $Shortcut.IconLocation = "powershell.exe"
    $Shortcut.Save()

    Write-Host "Shortcut auf dem Desktop wurde erstellt: CARO Auto-Updater.lnk"
    Write-Host "Starte den naechsten Prozess einfach mit Doppelklick auf diesen Link."
    Write-Host ""
}

# --- Bestaetigung ------------------------------------------------------------

Write-Host "Das Skript laedt die aktuelle Version der CARO-Suite herunter, entpackt sie und installiert sie."
Write-Host "Benutzerhandbuch, Lizenzinformationen und die Release Notes"
Write-Host "findest du in diesem Ordner nach Abschluss der Installation:"
Write-Host "$ExtractDir"
Write-Host ""
$Antwort = Read-Host "Fortfahren    (J/N)"
if ($Antwort -notmatch "^[Jj]$") { Write-Host "Abgebrochen."; exit 0 }

# --- Download ----------------------------------------------------------------

Write-Host "Lade herunter: $DownloadUrl"
Write-Host "Ziel:          $ZipPath"

$ProgressPreference = "SilentlyContinue"
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

# --- Blockierung aufheben (entspricht 'Zulassen' in den Eigenschaften) -------

Unblock-File -Path $MsiFile.FullName
Write-Host "Datei entsperrt."

# --- Version der MSI auslesen ------------------------------------------------

$Installer  = New-Object -ComObject WindowsInstaller.Installer
$Db         = $Installer.GetType().InvokeMember("OpenDatabase", "InvokeMethod", $null, $Installer, @($MsiFile.FullName, 0))
$View       = $Db.GetType().InvokeMember("OpenView", "InvokeMethod", $null, $Db, @("SELECT Value FROM Property WHERE Property='ProductVersion'"))
$View.GetType().InvokeMember("Execute", "InvokeMethod", $null, $View, $null)
$Record     = $View.GetType().InvokeMember("Fetch", "InvokeMethod", $null, $View, $null)
$MsiVersion = $Record.GetType().InvokeMember("StringData", "GetProperty", $null, $Record, @(1))
Write-Host "MSI-Version: $MsiVersion"

# --- Installierte Version pruefen --------------------------------------------

$Installed = Get-ItemProperty `
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" `
    -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -like "*CARO*" } |
    Select-Object -First 1

# --- Installation ------------------------------------------------------------

if ($Installed -and $Installed.DisplayVersion -eq $MsiVersion) {
    # Gleiche Version bereits installiert - interaktiven Dialog anzeigen (Change/Repair/Remove)
    Write-Host "Version $MsiVersion ist bereits installiert. Zeige Wartungsdialog..."
    $InstallArgs = "/i `"$($MsiFile.FullName)`""
} else {
    # Neue Version oder Erstinstallation - automatisch mit Fortschrittsbalken
    Write-Host "Installiere Version $MsiVersion..."
    $InstallArgs = "/i `"$($MsiFile.FullName)`" /passive /norestart"
}

Write-Host "Starte Installation..."

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
