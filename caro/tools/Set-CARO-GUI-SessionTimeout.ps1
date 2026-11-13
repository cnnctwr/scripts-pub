# im Default ist der Session Time out in der CARO Weboberfläche auf 60 Minuten gesetzt (50 werden angezeigt). Mit diesem Skript kann ein individueller Wert festgelegt werden.
# Der Inhalt einer bestehenden Datei wird respektiert.
# Am Ende kann der CARO-Service neu gestartet werden (notwendig für die tatsächliche Änderung)

# Aufruf, Beispiel für 12 Stunden 
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

Write-Host ""
$restart = Read-Host "Soll der Dienst 'CARO-Suite Server' jetzt neu gestartet werden? (J/N)"

if ($restart -match '^[JjYy]$') {
    try {
        Restart-Service -Name 'CARO-Suite Server' -ErrorAction Stop

        Write-Host ""
        Write-Host "Dienst 'CARO-Suite Server' wurde erfolgreich neu gestartet." -ForegroundColor Green
    }
    catch {
        Write-Error "Der Dienst konnte nicht neu gestartet werden: $($_.Exception.Message)"
        exit 1
    }
}
else {
    Write-Host ""
    Write-Host "Kein Dienstneustart durchgeführt." -ForegroundColor Yellow
    Write-Host "Die Änderung wird erst nach einem Neustart des Dienstes 'CARO-Suite Server' wirksam."
}
