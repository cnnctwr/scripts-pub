# ============================================================
# CARO Suite – Download, Entpacken & Installation
# ============================================================

# --- Konfiguration -----------------------------------------------------------

$DownloadUrl  = "https://cusatum.de/wp-content/uploads/1618/31/CARO-Suite-Setup.zip"
$OriginalName = "CARO-Suite-Setup"   # Dateiname ohne .zip

# Downloads-Verzeichnis des aktuellen Benutzers
$DownloadsDir = [Environment]::GetFolderPath("UserProfile") + "\Downloads"

# Zeitstempel für Umbenennung und Zielordner
$Timestamp    = Get-Date -Format "yyyy-MM-dd-HHmmss"
$BaseName     = "$Timestamp-$OriginalName"
$ZipPath      = Join-Path $DownloadsDir "$BaseName.zip"
$ExtractDir   = Join-Path $DownloadsDir $BaseName

# --- Bestätigung -------------------------------------------------------------

$Antwort = Read-Host "Aktuelle Version der CARO Suite herunterladen und installieren? (J/N)"
if ($Antwort -notmatch "^[Jj]$") { Write-Host "Abgebrochen."; exit 0 }

# --- Download ----------------------------------------------------------------

Write-Host "Lade herunter: $DownloadUrl"
Write-Host "Ziel:          $ZipPath"

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

# --- ZIP löschen -------------------------------------------------------------

Remove-Item -Path $ZipPath -Force
Write-Host "ZIP-Datei gelöscht."

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

# --- Installation ------------------------------------------------------------
#
# HINWEIS ZUR SILENT-INSTALLATION:
#   Teste zunächst mit /passive (Fortschrittsbalken sichtbar, kein Klicken nötig).
#   Funktioniert das ohne Probleme, wechsle zu /quiet (vollständig lautlos).
#
#   Falls der Installer ein separates EULA-Flag benötigt, muss es hier ergänzt
#   werden, z.B.: ACCEPT_EULA=1 oder AGREETOLICENSE=yes
#   Diese Property-Namen sind installer-spezifisch. Sollte /passive einen
#   EULA-Dialog anzeigen, den Installer-Hersteller nach dem genauen Property-
#   Namen fragen oder die MSI mit einem Tool wie Orca (kostenlos von Microsoft)
#   öffnen und in der Tabelle "Property" nachsehen.
#
# Option A – Fortschrittsbalken sichtbar, kein Klicken (zum Testen empfohlen):
$InstallArgs = "/i `"$($MsiFile.FullName)`" /passive /norestart"
#
# Option B – Vollständig lautlos, kein Fenster (nach erfolgreichem Test):
# $InstallArgs = "/i `"$($MsiFile.FullName)`" /quiet /norestart"
#
# Option C – Falls ein EULA-Flag nötig ist (Property-Namen anpassen!):
# $InstallArgs = "/i `"$($MsiFile.FullName)`" /quiet /norestart ACCEPT_EULA=1"
# ----------------------------------------------------------------------------

Write-Host "Starte Installation..."
Write-Host "msiexec $InstallArgs"

$Process = Start-Process -FilePath "msiexec.exe" -ArgumentList $InstallArgs -Wait -PassThru

if ($Process.ExitCode -eq 0) {
    Write-Host "Installation erfolgreich abgeschlossen."
} elseif ($Process.ExitCode -eq 3010) {
    Write-Host "Installation erfolgreich – Neustart erforderlich."
} else {
    Write-Warning "Installation beendet mit Exit-Code: $($Process.ExitCode)"
    Write-Warning "Nachschlagen: https://learn.microsoft.com/de-de/windows/win32/msi/error-codes"
}

Write-Host ""
Write-Host "Installiertes Paket liegt in: $ExtractDir"
