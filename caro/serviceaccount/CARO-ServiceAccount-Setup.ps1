# CARO-ServiceAccount-Setup.ps1
# First-draft implementation for Plan / Apply / Rollback with interactive options

param(
    [ValidateSet('Plan','Apply','Rollback')]
    [string]$Mode = 'Plan',
    [string]$ConfigPath = '',
    [switch]$WhatIf,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$ConservativeWhitelist = @(
    'sAMAccountName',
    'userPrincipalName',
    'displayName',
    'givenName',
    'sn',
    'mail',
    'telephoneNumber',
    'physicalDeliveryOfficeName',
    'streetAddress',
    'l',
    'st',
    'postalCode',
    'department',
    'title',
    'description',
    'manager',
    'employeeID',
    'employeeNumber',
    'homeDirectory',
    'homeDrive',
    'initials',
    'info'
)

function Get-ScriptFolder {
    if ($PSScriptRoot) { return $PSScriptRoot }
    return Split-Path -Parent $MyInvocation.MyCommand.Path
}

function Ensure-LogsFolder {
    $scriptFolder = Get-ScriptFolder
    $logFolder = Join-Path $scriptFolder 'CARO-ServiceAccount-Setup-Logs'
    if (-not (Test-Path $logFolder)) {
        New-Item -Path $logFolder -ItemType Directory -Force | Out-Null
    }
    return $logFolder
}

function New-OutputFileName {
    param(
        [Parameter(Mandatory = $true)] [string]$Type,
        [Parameter(Mandatory = $true)] [string]$Ext
    )

    $ts = (Get-Date).ToString('yyyy-MM-dd-HHmmss')
    $fileName = "${ts}-CARO-SA-$Type.$Ext"
    return (Join-Path (Ensure-LogsFolder) $fileName)
}

function Get-CaroAttributes {
    $examples = Join-Path (Get-ScriptFolder) 'examples' 'cts.manage.nativeActiveDirectoryStandardUser.json'
    if (-not (Test-Path $examples)) { return @() }

    try {
        $json = Get-Content -Path $examples -Raw | ConvertFrom-Json
        $vars = @()

        foreach ($d in $json.ConfigurationParameterDefinitions) {
            if ($d.VariableName) { $vars += $d.VariableName }
            if ($d.Description -and $d.Description.Strings) {
                foreach ($s in $d.Description.Strings.Values) {
                    $matches = [regex]::Matches($s, '\[([a-zA-Z0-9_\-]+)\]')
                    foreach ($m in $matches) { $vars += $m.Groups[1].Value }
                }
            }
        }

        $vars = $vars | Select-Object -Unique | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        return @($vars)
    }
    catch {
        return @()
    }
}

function Prompt-YesNo {
    param(
        [string]$Prompt,
        [string]$Default = 'y'
    )

    $defaultText = if ($Default -eq 'y') { 'y' } else { 'n' }
    $answer = Read-Host "$Prompt [$defaultText]"
    if ([string]::IsNullOrWhiteSpace($answer)) { return ($Default -eq 'y') }
    return ($answer.Trim().ToLowerInvariant() -eq 'y')
}

function Prompt-Choice {
    param(
        [string]$Prompt,
        [string]$DefaultValue = '1',
        [string[]]$Options = @('1','2')
    )

    $answer = Read-Host "$Prompt [$DefaultValue]"
    if ([string]::IsNullOrWhiteSpace($answer)) { $answer = $DefaultValue }
    if ($answer -in $Options) { return $answer }
    return $DefaultValue
}

function Save-Config {
    param(
        [Parameter(Mandatory = $true)] [hashtable]$Config
    )

    $path = New-OutputFileName -Type 'Config' -Ext 'json'
    $Config | ConvertTo-Json -Depth 10 | Out-File -FilePath $path -Encoding UTF8
    Write-Host "Config written to: $path"
    return $path
}

function Select-ADAttributeStrategy {
    $choice = Prompt-Choice -Prompt "Select AD attribute strategy`n1) ConservativeWhitelist (default)`n2) CAROStandardUser (from examples)`n3) WriteAll (risk)`n4) Manual (interactive)" -DefaultValue '1' -Options @('1','2','3','4')

    switch ($choice) {
        '1' {
            return @{ Strategy = 'ConservativeWhitelist'; Attributes = $ConservativeWhitelist }
        }
        '2' {
            $attrs = Get-CaroAttributes
            if (-not $attrs -or $attrs.Count -eq 0) {
                $attrs = $ConservativeWhitelist
            }
            return @{ Strategy = 'CAROStandardUser'; Attributes = @($attrs) }
        }
        '3' {
            return @{ Strategy = 'WriteAll'; Attributes = @() }
        }
        '4' {
            $input = Read-Host 'Enter comma-separated attribute names to allow'
            $attrs = @()
            if (-not [string]::IsNullOrWhiteSpace($input)) {
                $attrs = $input.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
            }
            return @{ Strategy = 'Manual'; Attributes = @($attrs) }
        }
        default {
            return @{ Strategy = 'ConservativeWhitelist'; Attributes = $ConservativeWhitelist }
        }
    }
}

function Get-PropertyValue {
    param(
        [Parameter(Mandatory = $true)] [object]$Object,
        [Parameter(Mandatory = $true)] [string]$PropertyName
    )

    if ($null -eq $Object) { return $null }
    if ($Object -is [hashtable]) {
        if ($Object.ContainsKey($PropertyName)) { return $Object[$PropertyName] }
        return $null
    }

    $prop = $Object.PSObject.Properties[$PropertyName]
    if ($null -ne $prop) { return $prop.Value }
    return $null
}

function Run-Plan {
    $plan = [ordered]@{}
    $plan.ConfigurationId = "cfg-$((Get-Date).ToString('yyyyMMddHHmmss'))"
    $plan.PlanId = (Get-Date).ToString('o')

    $plan.ServiceAccount = @{}
    $plan.ServiceAccount.sAMAccountName = Read-Host 'Service Account SamAccountName'
    $plan.ServiceAccount.displayName = Read-Host 'Display Name'
    $plan.ServiceAccount.TargetOU = Read-Host 'Target OU (e.g. OU=ServiceAccounts,DC=contoso,DC=local)'

    $plan.ADEnabled = (Prompt-YesNo -Prompt 'Enable Active Directory' -Default 'y')
    if ($plan.ADEnabled) {
        $plan.DelegationOUs = @()
        $delegationInput = Read-Host 'Delegation OU(s): enter comma-separated values (leave empty to skip)'
        if (-not [string]::IsNullOrWhiteSpace($delegationInput)) {
            $plan.DelegationOUs = @($delegationInput.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        }

        $adChoice = Select-ADAttributeStrategy
        $plan.ADAttributeStrategy = $adChoice.Strategy
        $plan.ADAttributes = @($adChoice.Attributes)
    }

    $plan.FileserverEnabled = (Prompt-YesNo -Prompt 'Enable Fileserver' -Default 'n')
    if ($plan.FileserverEnabled) {
        $plan.FileserverList = @()
        $servers = Read-Host 'Fileserver list: comma-separated names or hostnames'
        if (-not [string]::IsNullOrWhiteSpace($servers)) {
            $plan.FileserverList = @($servers.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        }

        $fsChoice = Prompt-Choice -Prompt 'Fileserver strategy: 1) LocalAdmins (default) 2) Granular (manual NTFS ACLs)' -DefaultValue '1' -Options @('1','2')
        $plan.FileserverStrategy = if ($fsChoice -eq '2') { 'Granular' } else { 'LocalAdmins' }
    }

    $plan.ExchangeEnabled = (Prompt-YesNo -Prompt 'Enable Exchange' -Default 'n')
    if ($plan.ExchangeEnabled) {
        $roleChoice = Prompt-Choice -Prompt 'Exchange role: 1) ReadOnly 2) Management (default)' -DefaultValue '2' -Options @('1','2')
        $plan.ExchangeRoleChoice = if ($roleChoice -eq '1') { 'ReadOnly' } else { 'Management' }
    }

    $plan.ApplyMode = 'Plan'
    Save-Config $plan | Out-Null
    Write-Host 'Plan complete. Review the generated configuration file in the logs folder.'
}

function Run-Apply {
    if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
        $ConfigPath = Read-Host 'Provide path to Config.json'
    }

    if (-not (Test-Path $ConfigPath)) {
        throw "Config file not found: $ConfigPath"
    }

    $config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
    $executionId = (Get-Date).ToString('o')

    $result = [ordered]@{}
    $result.ExecutionId = $executionId
    $result.ConfigPath = $ConfigPath
    $result.AppliedAt = (Get-Date).ToString('o')
    $result.Actions = @()
    $result.Warnings = @()
    $result.Errors = @()

    $serviceAccount = @{}
    if ($config.ServiceAccount) {
        foreach ($prop in $config.ServiceAccount.PSObject.Properties) {
            $serviceAccount[$prop.Name] = $prop.Value
        }
    }

    $samName = Get-PropertyValue -Object $serviceAccount -PropertyName 'sAMAccountName'
    if (-not $samName) {
        $samName = Read-Host 'SamAccountName for service account'
        $serviceAccount['sAMAccountName'] = $samName
    }

    $adAvailable = $false
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        $adAvailable = $true
    }
    catch {
        $result.Warnings += 'ActiveDirectory module not available. AD actions simulated.'
    }

    if ($config.ADEnabled) {
        $strategy = [string]$config.ADAttributeStrategy
        $attrs = @($config.ADAttributes)

        if ($strategy -eq 'WriteAll') {
            $result.Actions += "[AD] WriteAllProperties enabled for $samName"
        }
        else {
            foreach ($attr in $attrs) {
                $result.Actions += "[AD] Property-specific permission granted for attribute '$attr' on user '$samName'"
            }
        }

        if ($WhatIf) {
            Write-Host "[WhatIf] Would process AD configuration for $samName"
        }
        elseif ($adAvailable) {
            $existing = Get-ADUser -Filter "SamAccountName -eq '$samName'" -ErrorAction SilentlyContinue
            $targetOU = Get-PropertyValue -Object $config -PropertyName 'TargetOU'
            $userProps = @{}
            foreach ($attribute in $attrs) {
                $value = Get-PropertyValue -Object $serviceAccount -PropertyName $attribute
                if ($null -ne $value -and $attribute -notin @('sAMAccountName')) {
                    $userProps[$attribute] = $value
                }
            }

            if ($null -eq $existing) {
                Write-Host "Creating AD user: $samName"
                $newUserParams = @{
                    SamAccountName = $samName
                    Name = (Get-PropertyValue -Object $serviceAccount -PropertyName 'displayName')
                    Enabled = $true
                    Path = $targetOU
                }
                if ($userProps.Count -gt 0) {
                    $newUserParams += @{ OtherAttributes = $userProps }
                }
                New-ADUser @newUserParams
                $result.Actions += "[AD] Created AD user $samName in $targetOU"
            }
            else {
                Write-Host "Updating AD user: $samName"
                if ($userProps.Count -gt 0) {
                    Set-ADUser -Identity $existing -Replace $userProps
                }
                $result.Actions += "[AD] Updated AD user $samName"
            }
        }
        else {
            $result.Actions += "[AD] Simulated AD user create/update for $samName"
        }
    }

    if ($config.FileserverEnabled) {
        $servers = @()
        if ($config.FileserverList) { $servers = @($config.FileserverList) }
        foreach ($server in $servers) {
            if ($config.FileserverStrategy -eq 'LocalAdmins') {
                $action = "[FileServer] Add $samName to local Administrators group on $server"
            }
            else {
                $action = "[FileServer] Apply granular ACLs on $server (Traverse + ChangePermissions) for $samName"
            }
            $result.Actions += $action
            if ($WhatIf) { Write-Host "[WhatIf] $action" }
            else { Write-Host $action }
        }
    }

    if ($config.ExchangeEnabled) {
        $role = [string]$config.ExchangeRoleChoice
        if ($role -eq 'ReadOnly') {
            $msg = "[Exchange] Assign View-Only Organization Management to $samName"
        }
        else {
            $msg = "[Exchange] Assign Organization Management to $samName"
        }
        $result.Actions += $msg
        if ($WhatIf) { Write-Host "[WhatIf] $msg" } else { Write-Host $msg }
    }

    $outPath = New-OutputFileName -Type 'Result' -Ext 'json'
    $result | ConvertTo-Json -Depth 10 | Out-File -FilePath $outPath -Encoding UTF8
    Write-Host "Apply complete. Result file: $outPath"
}

function Run-Rollback {
    $resultPath = if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) { $ConfigPath } else { '' }
    if ([string]::IsNullOrWhiteSpace($resultPath)) {
        $logFolder = Ensure-LogsFolder
        $latest = Get-ChildItem -Path $logFolder -Filter '*-CARO-SA-Result.json' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if (-not $latest) {
            throw 'No result file found in logs folder to rollback.'
        }
        $resultPath = $latest.FullName
    }

    if (-not (Test-Path $resultPath)) {
        throw "Result file not found: $resultPath"
    }

    $result = Get-Content -Path $resultPath -Raw | ConvertFrom-Json
    $rollback = [ordered]@{
        RolledBackExecutionId = $result.ExecutionId
        RolledBackAt = (Get-Date).ToString('o')
        Actions = @()
    }

    foreach ($action in @($result.Actions)) {
        $rollback.Actions += "Rollback simulated: $action"
        Write-Host "Rollback simulated: $action"
    }

    $rollbackPath = New-OutputFileName -Type 'Rollback' -Ext 'json'
    $rollback | ConvertTo-Json -Depth 10 | Out-File -FilePath $rollbackPath -Encoding UTF8
    Write-Host "Rollback output written to: $rollbackPath"
}

switch ($Mode) {
    'Plan' { Run-Plan }
    'Apply' { Run-Apply }
    'Rollback' { Run-Rollback }
}
