# Shared helpers for the Windows collectors.
# Dot-source this file. It does not collect evidence by itself.

Set-StrictMode -Version 2.0

# $PSScriptRoot is the caller when this file is dot-sourced on some hosts.
# MyCommand.Path is the path of this file.
if ($MyInvocation.MyCommand.Path) {
    $script:CsiLibDir = Split-Path -Parent $MyInvocation.MyCommand.Path
} else {
    $script:CsiLibDir = $PSScriptRoot
}

function Get-RepoRoot {
    $collectDir = Split-Path -Parent $script:CsiLibDir
    return (Split-Path -Parent $collectDir)
}

function Get-StampUtc {
    return ([DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss'))
}

function Get-IsoTimestamp {
    return ([DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ'))
}

function Initialize-Evidence {
    param([Parameter(Mandatory = $true)][string]$RepoRoot)
    foreach ($relative in @('evidence', 'evidence\raw', 'evidence\screenshots')) {
        $path = Join-Path $RepoRoot $relative
        if (-not (Test-Path -LiteralPath $path)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }
    }
}

function Set-TextFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content
    )
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $normalised = $Content -replace "(?<!`r)`n", "`r`n"
    $utf8 = New-Object System.Text.UTF8Encoding $true
    [System.IO.File]::WriteAllText($Path, $normalised, $utf8)
}

function ConvertTo-ProcessArgumentString {
    param([string[]]$ArgumentList)
    if ($null -eq $ArgumentList) {
        return ''
    }
    $pieces = New-Object System.Collections.Generic.List[string]
    foreach ($arg in $ArgumentList) {
        if ($null -eq $arg) {
            $arg = ''
        }
        if ($arg -match '[\s"]') {
            $escaped = $arg.Replace('"', '\"')
            $pieces.Add('"' + $escaped + '"')
        } else {
            $pieces.Add($arg)
        }
    }
    return ($pieces.ToArray() -join ' ')
}

function Invoke-Native {
    <#
        Run one program and capture its exit code, stdout, and stderr.
        Both streams are read together so a long pip log cannot block.
        The parent process environment is left unchanged.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$File,
        [string[]]$ArgumentList = @(),
        [string]$WorkingDirectory
    )
    if ([string]::IsNullOrWhiteSpace($WorkingDirectory)) {
        $WorkingDirectory = (Get-Location).ProviderPath
    }
    if (-not (Test-Path -LiteralPath $File)) {
        return [pscustomobject]@{
            ExitCode = -1
            Text     = "command not found: $File"
            StdOut   = ''
            StdErr   = "command not found: $File"
        }
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $File
    $psi.Arguments = (ConvertTo-ProcessArgumentString -ArgumentList $ArgumentList)
    $psi.WorkingDirectory = $WorkingDirectory
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $utf8 = New-Object System.Text.UTF8Encoding $false
    $psi.StandardOutputEncoding = $utf8
    $psi.StandardErrorEncoding = $utf8
    if ($psi.EnvironmentVariables.ContainsKey('PYTHONIOENCODING')) {
        $psi.EnvironmentVariables['PYTHONIOENCODING'] = 'utf-8'
    } else {
        $psi.EnvironmentVariables.Add('PYTHONIOENCODING', 'utf-8')
    }
    if ($psi.EnvironmentVariables.ContainsKey('PYTHONUTF8')) {
        $psi.EnvironmentVariables['PYTHONUTF8'] = '1'
    } else {
        $psi.EnvironmentVariables.Add('PYTHONUTF8', '1')
    }

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    try {
        $started = $proc.Start()
        if (-not $started) {
            return [pscustomobject]@{
                ExitCode = -1
                Text     = 'failed to start process'
                StdOut   = ''
                StdErr   = 'failed to start process'
            }
        }
        $outTask = $proc.StandardOutput.ReadToEndAsync()
        $errTask = $proc.StandardError.ReadToEndAsync()
        $stdout = [string]$outTask.Result
        $stderr = [string]$errTask.Result
        $proc.WaitForExit()
        $code = [int]$proc.ExitCode
        $text = $stdout
        if (-not [string]::IsNullOrEmpty($stderr)) {
            if (-not [string]::IsNullOrEmpty($text) -and -not $text.EndsWith("`n")) {
                $text += "`r`n"
            }
            $text += $stderr
        }
        return [pscustomobject]@{
            ExitCode = $code
            Text     = $text
            StdOut   = $stdout
            StdErr   = $stderr
        }
    } catch {
        return [pscustomobject]@{
            ExitCode = -1
            Text     = ('exception: ' + $_.Exception.Message)
            StdOut   = ''
            StdErr   = $_.Exception.Message
        }
    } finally {
        $proc.Dispose()
    }
}

function Get-Prop {
    param($Object, [string]$Name)
    if ($null -eq $Object) {
        return $null
    }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }
    return $property.Value
}

function ConvertTo-List {
    param($Value)
    if ($null -eq $Value) {
        return @()
    }
    if ($Value -is [string]) {
        return @($Value)
    }
    if ($Value -is [System.Array]) {
        # Windows PowerShell 5.1 wraps $null as a one-element array.
        if ($Value.Count -eq 1 -and $null -eq $Value[0]) {
            return @()
        }
        return $Value
    }
    return @($Value)
}

function Format-InvariantNumber {
    param($Number, [int]$Decimals = 2)
    if ($null -eq $Number -or $Number -eq '') {
        return $null
    }
    $value = [double]$Number
    $format = '0'
    if ($Decimals -gt 0) {
        $format = '0.' + ('0' * $Decimals)
    }
    return $value.ToString($format, [System.Globalization.CultureInfo]::InvariantCulture)
}

function Format-Bytes {
    param($Bytes)
    if ($null -eq $Bytes -or $Bytes -eq '') {
        return $null
    }
    $count = [int64]$Bytes
    $gib = $count / 1GB
    $gibText = $gib.ToString('0.00', [System.Globalization.CultureInfo]::InvariantCulture)
    $byteText = $count.ToString([System.Globalization.CultureInfo]::InvariantCulture)
    return ("{0} bytes ({1} GiB)" -f $byteText, $gibText)
}

function Test-SensitiveValue {
    param([AllowNull()][string]$Text)
    if ([string]::IsNullOrEmpty($Text)) {
        return $false
    }
    if ($Text -match '(?i)\b([0-9a-f]{2}[:-]){5}[0-9a-f]{2}\b') {
        return $true
    }
    if ($Text -match '\b(?:10\.\d{1,3}\.\d{1,3}\.\d{1,3}|192\.168\.\d{1,3}\.\d{1,3}|172\.(?:1[6-9]|2\d|3[0-1])\.\d{1,3}\.\d{1,3})\b') {
        return $true
    }
    return $false
}

function Get-RedactionContext {
    $profilePath = $env:USERPROFILE
    if ([string]::IsNullOrEmpty($profilePath)) {
        $profilePath = ''
    }
    $user = [Environment]::UserName
    if ([string]::IsNullOrEmpty($user)) {
        $user = ''
    }
    $computer = $env:COMPUTERNAME
    if ([string]::IsNullOrEmpty($computer)) {
        $computer = [Environment]::MachineName
    }
    if ([string]::IsNullOrEmpty($computer)) {
        $computer = ''
    }
    return [pscustomobject]@{
        UserProfile = $profilePath
        UserName    = $user
        Computer    = $computer
    }
}

function Redact-Text {
    param(
        [AllowNull()][string]$Text,
        $Context
    )
    if ([string]::IsNullOrEmpty($Text)) {
        return ''
    }
    if ($null -eq $Context) {
        $Context = Get-RedactionContext
    }
    $value = $Text
    $profilePath = [string]$Context.UserProfile
    if (-not [string]::IsNullOrEmpty($profilePath)) {
        $value = $value.Replace($profilePath, '<USERPROFILE>')
        $forward = $profilePath.Replace('\', '/')
        $value = $value.Replace($forward, '<USERPROFILE>')
    }
    $user = [string]$Context.UserName
    if ($user.Length -ge 3) {
        $pattern = '(?i)(?<=\\|/)' + [regex]::Escape($user) + '(?=\\|/|$)'
        $value = [regex]::Replace($value, $pattern, '<USER>')
    }
    $computer = [string]$Context.Computer
    $common = @('user', 'home', 'laptop', 'desktop', 'windows', 'python', 'system', 'admin', 'owner', 'computer', 'default', 'public')
    $skipComputer = $false
    if ($computer.Length -lt 4) {
        $skipComputer = $true
    }
    foreach ($word in $common) {
        if ($computer.Equals($word, [System.StringComparison]::OrdinalIgnoreCase)) {
            $skipComputer = $true
        }
    }
    if (-not $skipComputer) {
        $value = [regex]::Replace($value, '(?i)\b' + [regex]::Escape($computer) + '\b', '<HOST>')
        $value = $value.Replace('\\' + $computer, '\\<HOST>')
    }
    $value = [regex]::Replace($value, '(?i)\b([0-9a-f]{2}[:-]){5}[0-9a-f]{2}\b', '<MAC>')
    $value = [regex]::Replace(
        $value,
        '\b(?:10\.\d{1,3}\.\d{1,3}\.\d{1,3}|192\.168\.\d{1,3}\.\d{1,3}|172\.(?:1[6-9]|2\d|3[0-1])\.\d{1,3}\.\d{1,3})\b',
        '<PRIVATE_IP>'
    )
    $value = [regex]::Replace($value, '(?i)\bfe80:[0-9a-f:]+\b', '<LINK_LOCAL_IP>')
    $value = [regex]::Replace($value, '(?i)\b(?:fc|fd)[0-9a-f]{2}:[0-9a-f:]+\b', '<PRIVATE_IP>')
    return $value
}

function New-Field {
    param(
        [Parameter(Mandatory = $true)][string]$Area,
        [Parameter(Mandatory = $true)][string]$Name,
        $Value,
        [Parameter(Mandatory = $true)][string]$Source,
        [string]$Status = '',
        [string]$Note = ''
    )
    $text = $null
    if ($null -ne $Value) {
        $text = [string]$Value
        if ([string]::IsNullOrWhiteSpace($text)) {
            $text = $null
        }
    }
    $resolved = $Status
    if ([string]::IsNullOrEmpty($resolved)) {
        if ($null -eq $text) {
            $resolved = 'not_exposed'
        } else {
            $resolved = 'observed'
        }
    }
    if ($resolved -eq 'observed' -and $null -ne $text -and (Test-SensitiveValue -Text $text)) {
        $resolved = 'omitted'
        $text = $null
        if ([string]::IsNullOrEmpty($Note)) {
            $Note = 'The value matched a MAC address or private IP pattern and was dropped.'
        }
    }
    return [pscustomobject]@{
        area   = $Area
        name   = $Name
        status = $resolved
        value  = $text
        source = $Source
        note   = $Note
    }
}

function Get-CimSafe {
    param([Parameter(Mandatory = $true)][string]$ClassName)
    try {
        $raw = Get-CimInstance -ClassName $ClassName -ErrorAction Stop
        $items = @(ConvertTo-List $raw)
        return [pscustomobject]@{
            Ok    = $true
            Items = $items
            Error = ''
        }
    } catch {
        return [pscustomobject]@{
            Ok    = $false
            Items = @()
            Error = $_.Exception.Message
        }
    }
}

function ConvertTo-JsonText {
    param($Object)
    return ($Object | ConvertTo-Json -Depth 12)
}

function Assert-WindowsHost {
    if ($env:OS -ne 'Windows_NT') {
        Write-Host 'These collectors run on the investigator''s Windows laptop, under Windows PowerShell 5.1.'
        Write-Host ("This session reports OS={0}." -f $env:OS)
        exit 1
    }
    if ($PSVersionTable.PSVersion.Major -lt 5) {
        Write-Host ("Windows PowerShell 5.1 is required. This session is {0}." -f $PSVersionTable.PSVersion)
        exit 1
    }
}
