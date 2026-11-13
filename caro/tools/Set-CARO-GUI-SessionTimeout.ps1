# im Default ist der Session Timeout in der CARO Web Oberfläche auf 60 Minuten gesetz (50 Minuten werden angezeigt). Mit diesem Skript kann ein individueller Wert festgelegt werden.

# Aufruf-Beispiel für 12 Stunden 
# .\Set-CARO-GUI-SessionTimeout.ps1 -Minutes 720

param(
    [Parameter(Mandatory)]
    [ValidateRange(1,525600)]
    [int]$Minutes
)

$searchPaths = @(
    'C:\ProgramData\CUSATUM Service GmbH\CARO\etc',
    'D:\ProgramData\CUSATUM Service GmbH\CARO\etc'
)

$caroPath = $searchPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $caroPath) {
    Write-Error @"
Keine CARO-Installation gefunden.

Geprüft wurden:
- C:\ProgramData\CUSATUM Service GmbH\CARO\etc
- D:\ProgramData\CUSATUM Service GmbH\CARO\etc
"@
    exit 1
}

$configPath = Join-Path $caroPath 'CARO.config.json'

# Konfiguration laden oder neu erzeugen
if (Test-Path $configPath) {
    try {
        $config = Get-Content $configPath -Raw | ConvertFrom-Json
    }
    catch {
        Write-Error "Die Datei '$configPath' enthält kein gültiges JSON."
        exit 1
    }
}
else {
    $config = [PSCustomObject]@{}
}

# userManagement sicherstellen
if (-not ($config.PSObject.Properties.Name -contains 'userManagement')) {
    $config | Add-Member `
        -MemberType NoteProperty `
        -Name userManagement `
        -Value ([PSCustomObject]@{})
}

# sessionTimeOutMinutes setzen
if ($config.userManagement.PSObject.Properties.Name -contains 'sessionTimeOutMinutes') {
    $config.userManagement.sessionTimeOutMinutes = $Minutes
}
else {
    $config.userManagement | Add-Member `
        -MemberType NoteProperty `
        -Name sessionTimeOutMinutes `
        -Value $Minutes
}

# Speichern
$config |
    ConvertTo-Json -Depth 100 |
    Set-Content -Path $configPath -Encoding UTF8

Write-Host ""
Write-Host "CARO GUI Session Timeout erfolgreich gesetzt." -ForegroundColor Green
Write-Host "Pfad    : $configPath"
Write-Host "Timeout : $Minutes Minuten"
