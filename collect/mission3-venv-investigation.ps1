#Requires -Version 5.1
<#
.SYNOPSIS
    Compare system Python with a project virtual environment.

.DESCRIPTION
    Creates project\.venv, installs project\requirements.txt, runs the
    project, records the isolation evidence, deletes the environment, and
    creates it again. Raw output stays in evidence\raw. Use -Smoke only
    for the remote CI check. Smoke output is not device evidence.
#>

param(
    [switch]$Smoke
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\Common.ps1')

function Get-CommandPath {
    param([Parameter(Mandatory = $true)][string]$Name)
    $command = Get-Command -Name $Name -ErrorAction SilentlyContinue
    if ($null -eq $command) {
        return $null
    }
    $source = [string](Get-Prop $command 'Source')
    if ([string]::IsNullOrWhiteSpace($source)) {
        $source = [string](Get-Prop $command 'Path')
    }
    if ([string]::IsNullOrWhiteSpace($source)) {
        return $null
    }
    return $source
}

function ConvertTo-SingleQuoted {
    param([string]$Text)
    return "'" + $Text.Replace("'", "''") + "'"
}

function Test-JsonTrue {
    param($Value)
    if ($null -eq $Value) { return $false }
    if ($Value -is [bool]) { return [bool]$Value }
    return ([string]$Value).Equals('true', [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-PythonHelp {
    return @(
        'Python 3.9 or newer was not found on PATH.',
        '',
        'Install it for the current user. An administrator password is not required.',
        '1. Open https://www.python.org/downloads/windows/',
        '2. Download the Windows installer (64-bit) for Python 3.12 or newer.',
        '3. Run the installer. If it asks for administrator approval, cancel it and start it again.',
        '4. Leave "Install for all users" unchecked. That choice installs under your user profile.',
        '5. Check "Add python.exe to PATH" and "py launcher".',
        '6. Finish, close PowerShell, open a new window, and run the collector again.',
        '',
        'requirements.txt pins rich==15.0.0, which needs Python 3.9 or newer.',
        'The collector will not replace that pin with an older package.',
        'A Windows Store alias named python is not a Python installation. If python opens the Store, use the installer above.',
        'The embeddable zip package does not include venv. Use the full installer.'
    ) -join "`n"
}

function Add-CommandLog {
    param($Log, [string]$Title, [string]$File, [string[]]$ArgumentList, $Result)
    [void]$Log.AppendLine('---- ' + $Title + ' ----')
    [void]$Log.AppendLine('utc: ' + (Get-IsoTimestamp))
    $rendered = ''
    if ($null -ne $ArgumentList) {
        $rendered = (($ArgumentList | ForEach-Object { [string]$_ }) -join ' ')
    }
    [void]$Log.AppendLine('command: ' + $File + ' ' + $rendered)
    [void]$Log.AppendLine('exit_code: ' + [string]$Result.ExitCode)
    [void]$Log.AppendLine('stdout:')
    [void]$Log.AppendLine([string]$Result.StdOut)
    [void]$Log.AppendLine('stderr:')
    [void]$Log.AppendLine([string]$Result.StdErr)
    [void]$Log.AppendLine('')
}

function Get-PythonAttempts {
    param($Log)
    $attempts = New-Object System.Collections.Generic.List[object]
    $specs = New-Object System.Collections.Generic.List[object]
    $py = Get-CommandPath -Name 'py'
    if ($py) { $specs.Add([pscustomobject]@{ File = $py; Prefix = @('-3'); Label = 'py -3' }) | Out-Null }
    $python = Get-CommandPath -Name 'python'
    if ($python) { $specs.Add([pscustomobject]@{ File = $python; Prefix = @(); Label = 'python' }) | Out-Null }
    $python3 = Get-CommandPath -Name 'python3'
    if ($python3) { $specs.Add([pscustomobject]@{ File = $python3; Prefix = @(); Label = 'python3' }) | Out-Null }

    $selected = $null
    foreach ($spec in $specs) {
        $argumentList = @()
        foreach ($prefix in @($spec.Prefix)) { $argumentList += $prefix }
        $argumentList += '-c'
        $argumentList += 'import sys; print(sys.executable); print(''VERSION=%d.%d.%d'' % sys.version_info[:3])'
        $result = Invoke-Native -File $spec.File -ArgumentList $argumentList
        Add-CommandLog -Log $Log -Title ('probe ' + $spec.Label) -File $spec.File -ArgumentList $argumentList -Result $result
        $versionText = ''
        $executable = ''
        foreach ($line in ([string]$result.StdOut -split "`r?`n")) {
            $trimmed = $line.Trim()
            if ($trimmed.StartsWith('VERSION=')) {
                $versionText = $trimmed.Substring(8).Trim()
            } elseif (-not [string]::IsNullOrWhiteSpace($trimmed) -and [string]::IsNullOrWhiteSpace($executable)) {
                $executable = $trimmed
            }
        }
        $parsed = $null
        $usable = $false
        if ($result.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($versionText)) {
            try {
                $parsed = [version]$versionText
                if ($parsed -ge [version]'3.9.0' -and (Test-Path -LiteralPath $executable)) {
                    $usable = $true
                }
            } catch {
                $parsed = $null
            }
        }
        $attempts.Add([pscustomobject]@{
            Label      = $spec.Label
            File       = $spec.File
            ExitCode   = $result.ExitCode
            Version    = $versionText
            Executable = $executable
            Usable     = $usable
        }) | Out-Null
        if ($usable -and $null -eq $selected) {
            $selected = [pscustomobject]@{
                Label      = $spec.Label
                Launcher   = $spec.File
                Executable = $executable
                Version    = $parsed
            }
        }
    }
    return [pscustomobject]@{
        Selected = $selected
        Attempts = $attempts.ToArray()
    }
}

function Get-TreeSizeBytes {
    param([Parameter(Mandatory = $true)][string]$Path)
    $total = [int64]0
    if (-not (Test-Path -LiteralPath $Path)) { return $total }
    $files = Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue
    foreach ($file in @(ConvertTo-List $files)) {
        $total += [int64]$file.Length
    }
    return $total
}

function Remove-ProjectVenv {
    param(
        [Parameter(Mandatory = $true)][string]$VenvPath,
        [Parameter(Mandatory = $true)][string]$RepoRoot
    )
    $full = [System.IO.Path]::GetFullPath($VenvPath)
    $root = [System.IO.Path]::GetFullPath($RepoRoot)
    if (-not $root.EndsWith('\')) { $root = $root + '\' }
    if (-not $full.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Refusing to delete a virtual environment outside the repository.'
    }
    if ((Split-Path -Leaf $full) -ne '.venv') {
        throw 'Refusing to delete a directory that is not named .venv.'
    }
    if (-not (Test-Path -LiteralPath $full)) { return }
    $attempt = 0
    while ($attempt -lt 3) {
        try {
            Remove-Item -LiteralPath $full -Recurse -Force -ErrorAction Stop
            return
        } catch {
            $attempt += 1
            Start-Sleep -Seconds 1
            if ($attempt -ge 3) { throw }
        }
    }
}

function Remove-SmokeDirectory {
    param([Parameter(Mandatory = $true)][string]$Path)
    $full = [System.IO.Path]::GetFullPath($Path)
    $temp = [System.IO.Path]::GetFullPath($env:TEMP)
    if (-not $temp.EndsWith('\')) { $temp = $temp + '\' }
    if (-not $full.StartsWith($temp, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Refusing to delete a smoke directory outside TEMP.'
    }
    if ($full -notmatch 'csi-smoke-') {
        throw 'Refusing to delete an unexpected smoke directory.'
    }
    if (Test-Path -LiteralPath $full) {
        Remove-Item -LiteralPath $full -Recurse -Force
    }
}

function Read-PyVenvCfg {
    param([Parameter(Mandatory = $true)][string]$Path)
    $map = @{}
    if (-not (Test-Path -LiteralPath $Path)) { return $map }
    foreach ($line in @(Get-Content -LiteralPath $Path -ErrorAction Stop)) {
        $text = [string]$line
        $index = $text.IndexOf('=')
        if ($index -lt 1) { continue }
        $key = $text.Substring(0, $index).Trim()
        $value = $text.Substring($index + 1).Trim()
        if (-not $map.ContainsKey($key)) { $map[$key] = $value }
    }
    return $map
}

function Get-PipPairs {
    param([string]$JsonText)
    $pairs = New-Object System.Collections.Generic.List[string]
    if ([string]::IsNullOrWhiteSpace($JsonText)) { return $pairs.ToArray() }
    try {
        $parsed = $JsonText | ConvertFrom-Json
    } catch {
        return $pairs.ToArray()
    }
    foreach ($item in @(ConvertTo-List $parsed)) {
        $name = [string](Get-Prop $item 'name')
        $version = [string](Get-Prop $item 'version')
        if (-not [string]::IsNullOrWhiteSpace($name)) {
            $pairs.Add(('{0}=={1}' -f $name.ToLowerInvariant(), $version)) | Out-Null
        }
    }
    return $pairs.ToArray()
}

function New-SetDiffText {
    param($LeftPairs, $RightPairs, [string]$LeftLabel, [string]$RightLabel)
    $leftMap = @{}
    foreach ($pair in @(ConvertTo-List $LeftPairs)) {
        $parts = [string]$pair
        $index = $parts.IndexOf('==')
        if ($index -lt 1) { continue }
        $leftMap[$parts.Substring(0, $index)] = $parts.Substring($index + 2)
    }
    $rightMap = @{}
    foreach ($pair in @(ConvertTo-List $RightPairs)) {
        $parts = [string]$pair
        $index = $parts.IndexOf('==')
        if ($index -lt 1) { continue }
        $rightMap[$parts.Substring(0, $index)] = $parts.Substring($index + 2)
    }
    $onlyLeft = New-Object System.Collections.Generic.List[string]
    $onlyRight = New-Object System.Collections.Generic.List[string]
    $changed = New-Object System.Collections.Generic.List[string]
    foreach ($name in @($leftMap.Keys)) {
        if (-not $rightMap.ContainsKey($name)) {
            $onlyLeft.Add(('{0}=={1}' -f $name, $leftMap[$name])) | Out-Null
        } elseif ([string]$leftMap[$name] -ne [string]$rightMap[$name]) {
            $changed.Add(('{0}: {1} has {2}; {3} has {4}' -f $name, $LeftLabel, $leftMap[$name], $RightLabel, $rightMap[$name])) | Out-Null
        }
    }
    foreach ($name in @($rightMap.Keys)) {
        if (-not $leftMap.ContainsKey($name)) {
            $onlyRight.Add(('{0}=={1}' -f $name, $rightMap[$name])) | Out-Null
        }
    }
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add(('only in {0}: {1}' -f $LeftLabel, $(if ($onlyLeft.Count -eq 0) { '(none)' } else { $onlyLeft.ToArray() -join ', ' }))) | Out-Null
    $lines.Add(('only in {0}: {1}' -f $RightLabel, $(if ($onlyRight.Count -eq 0) { '(none)' } else { $onlyRight.ToArray() -join ', ' }))) | Out-Null
    $lines.Add(('version differs: {0}' -f $(if ($changed.Count -eq 0) { '(none)' } else { $changed.ToArray() -join '; ' }))) | Out-Null
    $equal = ($onlyLeft.Count -eq 0 -and $onlyRight.Count -eq 0 -and $changed.Count -eq 0)
    return [pscustomobject]@{
        Text  = ($lines.ToArray() -join "`n")
        Equal = $equal
    }
}

function ConvertFrom-ProbeOutput {
    param($Result)
    if ($null -eq $Result -or [string]::IsNullOrWhiteSpace([string]$Result.StdOut)) {
        return $null
    }
    try {
        return ($Result.StdOut | ConvertFrom-Json)
    } catch {
        return $null
    }
}

function New-IsolationText {
    param($SystemProbe, $VenvProbe)
    $lines = New-Object System.Collections.Generic.List[string]
    if ($null -eq $VenvProbe) {
        $lines.Add('The virtual-environment probe did not return JSON.') | Out-Null
        return ($lines.ToArray() -join "`n")
    }
    $venvRich = Get-Prop $VenvProbe 'rich'
    $sysRich = $null
    if ($null -ne $SystemProbe) { $sysRich = Get-Prop $SystemProbe 'rich' }
    $venvPrefix = [string](Get-Prop $VenvProbe 'prefix')
    $venvBase = [string](Get-Prop $VenvProbe 'base_prefix')
    $sysPrefix = ''
    if ($null -ne $SystemProbe) { $sysPrefix = [string](Get-Prop $SystemProbe 'prefix') }

    if ($venvPrefix -and $venvBase -and -not $venvPrefix.TrimEnd('\').Equals($venvBase.TrimEnd('\'), [System.StringComparison]::OrdinalIgnoreCase)) {
        $lines.Add('Inside the virtual environment, sys.prefix and sys.base_prefix differ.') | Out-Null
    } else {
        $lines.Add('Inside the virtual environment, sys.prefix and sys.base_prefix do not differ. Record the probe values.') | Out-Null
    }
    if ($sysPrefix -and $venvBase -and $sysPrefix.TrimEnd('\').Equals($venvBase.TrimEnd('\'), [System.StringComparison]::OrdinalIgnoreCase)) {
        $lines.Add('The environment base_prefix matches the system interpreter prefix.') | Out-Null
    } elseif ($sysPrefix -and $venvBase) {
        $lines.Add('The environment base_prefix does not match the system interpreter prefix.') | Out-Null
    }

    if (Test-JsonTrue (Get-Prop $venvRich 'importable')) {
        $lines.Add('rich was importable in the virtual environment.') | Out-Null
        $lines.Add('venv rich version: ' + [string](Get-Prop $venvRich 'version')) | Out-Null
        $lines.Add('venv rich file: ' + [string](Get-Prop $venvRich 'file')) | Out-Null
    } else {
        $lines.Add('rich was not importable in the virtual environment.') | Out-Null
        $lines.Add('venv error type: ' + [string](Get-Prop $venvRich 'error_type')) | Out-Null
        $lines.Add('venv error: ' + [string](Get-Prop $venvRich 'error')) | Out-Null
    }

    if ($null -eq $sysRich) {
        $lines.Add('The system probe has no rich result.') | Out-Null
    } elseif (Test-JsonTrue (Get-Prop $sysRich 'importable')) {
        $lines.Add('System Python imported rich. Do not describe this result as an ImportError.') | Out-Null
        $lines.Add('system rich version: ' + [string](Get-Prop $sysRich 'version')) | Out-Null
        $lines.Add('system rich file: ' + [string](Get-Prop $sysRich 'file')) | Out-Null
        $venvFile = [string](Get-Prop $venvRich 'file')
        $sysFile = [string](Get-Prop $sysRich 'file')
        if ($venvFile -and $sysFile) {
            if ($venvFile.Equals($sysFile, [System.StringComparison]::OrdinalIgnoreCase)) {
                $lines.Add('The rich file paths are the same.') | Out-Null
            } else {
                $lines.Add('The rich file paths differ.') | Out-Null
            }
        }
    } else {
        $errorType = [string](Get-Prop $sysRich 'error_type')
        $lines.Add('System Python did not import rich.') | Out-Null
        $lines.Add('system error type: ' + $errorType) | Out-Null
        $lines.Add('system error: ' + [string](Get-Prop $sysRich 'error')) | Out-Null
        if ($errorType -eq 'ModuleNotFoundError' -or $errorType -eq 'ImportError') {
            $lines.Add('Python 3 reports a missing module as ModuleNotFoundError. That class is a subclass of ImportError. Keep the type this probe captured.') | Out-Null
        } else {
            $lines.Add('The captured exception is not ImportError or ModuleNotFoundError. Report the type above.') | Out-Null
        }
    }

    $venvSites = @(ConvertTo-List (Get-Prop $VenvProbe 'site_packages'))
    $sysSites = @()
    if ($null -ne $SystemProbe) { $sysSites = @(ConvertTo-List (Get-Prop $SystemProbe 'site_packages')) }
    $lines.Add('venv site-packages:') | Out-Null
    if ($venvSites.Count -eq 0) { $lines.Add('  (none reported)') | Out-Null }
    foreach ($sitePath in $venvSites) { $lines.Add('  ' + [string]$sitePath) | Out-Null }
    $lines.Add('system site-packages:') | Out-Null
    if ($sysSites.Count -eq 0) { $lines.Add('  (none reported)') | Out-Null }
    foreach ($sitePath in $sysSites) { $lines.Add('  ' + [string]$sitePath) | Out-Null }
    return ($lines.ToArray() -join "`n")
}

function Invoke-PipJson {
    param($Log, [string]$Title, [string]$Python)
    $arguments = @('-m', 'pip', 'list', '--format=json', '--disable-pip-version-check')
    $result = Invoke-Native -File $Python -ArgumentList $arguments
    Add-CommandLog -Log $Log -Title $Title -File $Python -ArgumentList $arguments -Result $result
    return $result
}

function Invoke-InterpreterPrint {
    param($Log, [string]$Title, [string]$Python)
    $code = "import sys; print('executable=' + sys.executable); print('prefix=' + sys.prefix); print('base_prefix=' + sys.base_prefix); print('PATH_BEGIN'); print('\n'.join(sys.path)); print('PATH_END')"
    $arguments = @('-c', $code)
    $result = Invoke-Native -File $Python -ArgumentList $arguments
    Add-CommandLog -Log $Log -Title $Title -File $Python -ArgumentList $arguments -Result $result
    return $result
}

function Invoke-ProbeFile {
    param($Log, [string]$Title, [string]$Python, [string]$Probe, [string]$WorkingDirectory)
    $arguments = @($Probe)
    $result = Invoke-Native -File $Python -ArgumentList $arguments -WorkingDirectory $WorkingDirectory
    Add-CommandLog -Log $Log -Title $Title -File $Python -ArgumentList $arguments -Result $result
    return $result
}

$repo = Get-RepoRoot
$projectDir = Join-Path $repo 'project'
$requirements = Join-Path $projectDir 'requirements.txt'
$probe = Join-Path $repo 'collect\py\probe_interpreter.py'
$log = New-Object System.Text.StringBuilder
[void]$log.AppendLine('LOCAL RAW COMMAND LOG')
[void]$log.AppendLine('Paths in this file can contain your username. Do not submit it unchanged.')
[void]$log.AppendLine('evidence/summary.md is the redacted copy.')
[void]$log.AppendLine('')

if ($Smoke) {
    Write-Host 'REMOTE CI SMOKE TEST'
    Write-Host 'This is a functional check that the virtual-environment steps run.'
    Write-Host 'On GitHub Actions the computer is a hosted windows-latest runner, not the investigator laptop.'
    Write-Host 'Do not copy this log into the report as device evidence.'
    Assert-WindowsHost
    $found = Get-PythonAttempts -Log $log
    if ($null -eq $found.Selected) {
        Write-Host (Get-PythonHelp)
        Write-Host $log.ToString()
        exit 1
    }
    $smokeRoot = Join-Path $env:TEMP ('csi-smoke-' + [guid]::NewGuid().ToString('n'))
    New-Item -ItemType Directory -Path $smokeRoot -Force | Out-Null
    $smokeVenv = Join-Path $smokeRoot '.venv'
    $failed = $false
    try {
        $createArgs = @('-m', 'venv', $smokeVenv)
        $created = Invoke-Native -File $found.Selected.Executable -ArgumentList $createArgs
        Add-CommandLog -Log $log -Title 'smoke venv create' -File $found.Selected.Executable -ArgumentList $createArgs -Result $created
        $smokePython = Join-Path $smokeVenv 'Scripts\python.exe'
        if ($created.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $smokePython)) {
            Write-Host 'Smoke test could not create the virtual environment.'
            $failed = $true
        } else {
            $installArgs = @('-m', 'pip', 'install', '--disable-pip-version-check', '-r', $requirements)
            $installed = Invoke-Native -File $smokePython -ArgumentList $installArgs -WorkingDirectory $projectDir
            Add-CommandLog -Log $log -Title 'smoke pip install' -File $smokePython -ArgumentList $installArgs -Result $installed
            $runArgs = @('-m', 'isolated_env')
            $ran = Invoke-Native -File $smokePython -ArgumentList $runArgs -WorkingDirectory $projectDir
            Add-CommandLog -Log $log -Title 'smoke run project' -File $smokePython -ArgumentList $runArgs -Result $ran
            $venvProbeResult = Invoke-ProbeFile -Log $log -Title 'smoke venv probe' -Python $smokePython -Probe $probe -WorkingDirectory $projectDir
            $sysProbeResult = Invoke-ProbeFile -Log $log -Title 'smoke system probe' -Python $found.Selected.Executable -Probe $probe -WorkingDirectory $projectDir
            $venvProbe = ConvertFrom-ProbeOutput $venvProbeResult
            $sysProbe = ConvertFrom-ProbeOutput $sysProbeResult
            Write-Host (New-IsolationText -SystemProbe $sysProbe -VenvProbe $venvProbe)
            $importable = $false
            if ($null -ne $venvProbe) {
                $importable = Test-JsonTrue (Get-Prop (Get-Prop $venvProbe 'rich') 'importable')
            }
            $prefixDiffers = $false
            if ($null -ne $venvProbe) {
                $prefix = [string](Get-Prop $venvProbe 'prefix')
                $base = [string](Get-Prop $venvProbe 'base_prefix')
                if ($prefix -and $base -and -not $prefix.TrimEnd('\').Equals($base.TrimEnd('\'), [System.StringComparison]::OrdinalIgnoreCase)) {
                    $prefixDiffers = $true
                }
            }
            if ($installed.ExitCode -ne 0 -or $ran.ExitCode -ne 0 -or -not $importable -or -not $prefixDiffers) {
                Write-Host 'Smoke test failed. Project output follows.'
                Write-Host ([string]$ran.StdOut)
                Write-Host ([string]$ran.StdErr)
                $failed = $true
            } elseif ([string]$ran.StdOut -notmatch 'Renderer') {
                Write-Host 'Smoke test ran, but the project output did not identify a renderer.'
                Write-Host ([string]$ran.StdOut)
                $failed = $true
            }
        }
    } finally {
        Remove-SmokeDirectory -Path $smokeRoot
    }
    Write-Host 'REMOTE CI SMOKE TEST finished. These lines are not laptop evidence.'
    if ($failed) { exit 1 }
    exit 0
}

Assert-WindowsHost
Initialize-Evidence -RepoRoot $repo
$stamp = Get-StampUtc
$rawDir = Join-Path $repo 'evidence\raw'
$venvPath = Join-Path $projectDir '.venv'

Write-Host ''
Write-Host 'Mission 3. What does an isolated environment actually mean?'
Write-Host 'Open report/REPORT_TEMPLATE.md and write the prediction before you continue.'
Write-Host 'The collector records the UTC time when you answer. That time should be later than the time in the report.'
Write-Host 'Type YES if the prediction is already written. Any other answer skips Mission 3 and does not create a virtual environment.'
$predictionAnswer = (Read-Host 'Prediction written?').Trim()
$predictionUtc = Get-IsoTimestamp
if ($predictionAnswer.ToUpperInvariant() -ne 'YES') {
    $result = [pscustomobject]@{
        generated_utc         = (Get-IsoTimestamp)
        prediction_confirmed  = 'false'
        prediction_utc        = $predictionUtc
        stopped               = 'prediction-not-confirmed'
        help                  = 'Mission 3 did not run. Write the prediction in the report, then run the collector again.'
        isolation_text        = ''
        reproducibility_text  = ''
        pip_diff_system_text  = ''
        pip_diff_runs_text    = ''
        command_log           = ''
    }
    $jsonPath = Join-Path $rawDir ("m3-result-{0}.json" -f $stamp)
    Set-TextFile -Path $jsonPath -Content (ConvertTo-JsonText -Object $result)
    Write-Host 'Mission 3 stopped before creating a virtual environment.'
    Write-Output ([pscustomobject]@{ Ok = $false; Stamp = $stamp; JsonPath = $jsonPath; Result = $result })
    return
}

if (Test-Path -LiteralPath $venvPath) {
    Write-Host 'project\.venv already exists. The investigation deletes that directory and creates it twice.'
    Write-Host 'Type DELETE to allow that. Any other answer skips Mission 3.'
    $deleteAnswer = (Read-Host 'Delete project\.venv?').Trim()
    if ($deleteAnswer.ToUpperInvariant() -ne 'DELETE') {
        $result = [pscustomobject]@{
            generated_utc        = (Get-IsoTimestamp)
            prediction_confirmed = 'true'
            prediction_utc       = $predictionUtc
            stopped              = 'existing-venv-kept'
            help                 = 'Mission 3 did not run because project\.venv was left in place.'
            isolation_text       = ''
            reproducibility_text = ''
            pip_diff_system_text = ''
            pip_diff_runs_text   = ''
            command_log          = ''
        }
        $jsonPath = Join-Path $rawDir ("m3-result-{0}.json" -f $stamp)
        Set-TextFile -Path $jsonPath -Content (ConvertTo-JsonText -Object $result)
        Write-Output ([pscustomobject]@{ Ok = $false; Stamp = $stamp; JsonPath = $jsonPath; Result = $result })
        return
    }
}

$whereExe = Get-CommandPath -Name 'where.exe'
if ([string]::IsNullOrWhiteSpace($whereExe)) {
    $whereExe = Join-Path $env:SystemRoot 'System32\where.exe'
}
foreach ($name in @('python', 'py', 'python3')) {
    $arguments = @($name)
    $result = Invoke-Native -File $whereExe -ArgumentList $arguments
    Add-CommandLog -Log $log -Title ('where.exe ' + $name) -File $whereExe -ArgumentList $arguments -Result $result
}
$pyLauncher = Get-CommandPath -Name 'py'
if ($pyLauncher) {
    $pyList = Invoke-Native -File $pyLauncher -ArgumentList @('-0p')
    Add-CommandLog -Log $log -Title 'py -0p' -File $pyLauncher -ArgumentList @('-0p') -Result $pyList
} else {
    [void]$log.AppendLine('---- py -0p ----')
    [void]$log.AppendLine('command not found: py')
    [void]$log.AppendLine('')
}

$found = Get-PythonAttempts -Log $log
if ($null -eq $found.Selected) {
    $help = Get-PythonHelp
    [void]$log.AppendLine($help)
    $logPath = Join-Path $rawDir ("m3-commands-{0}.txt" -f $stamp)
    Set-TextFile -Path $logPath -Content $log.ToString()
    $result = [pscustomobject]@{
        generated_utc        = (Get-IsoTimestamp)
        prediction_confirmed = 'true'
        prediction_utc       = $predictionUtc
        stopped              = 'python-missing'
        help                  = $help
        python_executable    = ''
        python_version       = ''
        isolation_text       = ''
        reproducibility_text = ''
        pip_diff_system_text = ''
        pip_diff_runs_text   = ''
        command_log          = $logPath
    }
    $jsonPath = Join-Path $rawDir ("m3-result-{0}.json" -f $stamp)
    Set-TextFile -Path $jsonPath -Content (ConvertTo-JsonText -Object $result)
    $helpPath = Join-Path $rawDir ("m3-python-missing-{0}.txt" -f $stamp)
    Set-TextFile -Path $helpPath -Content $help
    Write-Host $help
    Write-Output ([pscustomobject]@{ Ok = $false; Stamp = $stamp; JsonPath = $jsonPath; Result = $result })
    return
}

$systemPython = $found.Selected.Executable
Write-Host ("Using {0} ({1}), version {2}." -f $found.Selected.Label, $systemPython, $found.Selected.Version)

# Step 1. Record the system interpreter before a virtual environment exists.
Invoke-InterpreterPrint -Log $log -Title 'system python -c' -Python $systemPython | Out-Null
$systemPip = Invoke-Native -File $systemPython -ArgumentList @('-m', 'pip', 'list', '--disable-pip-version-check')
Add-CommandLog -Log $log -Title 'system pip list' -File $systemPython -ArgumentList @('-m', 'pip', 'list', '--disable-pip-version-check') -Result $systemPip
$systemPipJson = Invoke-PipJson -Log $log -Title 'system pip list json' -Python $systemPython
$systemProbeResult = Invoke-ProbeFile -Log $log -Title 'system probe' -Python $systemPython -Probe $probe -WorkingDirectory $projectDir
$whereBefore = Invoke-Native -File $whereExe -ArgumentList @('python')
Add-CommandLog -Log $log -Title 'where python before venv' -File $whereExe -ArgumentList @('python') -Result $whereBefore

function Invoke-Generation {
    param($Log, [string]$Name, [string]$BasePython, [string]$VenvPath, [string]$RepoRoot, [string]$ProjectDir, [string]$Requirements, [string]$Probe, [string]$WhereExe)
    Remove-ProjectVenv -VenvPath $VenvPath -RepoRoot $RepoRoot
    $createArgs = @('-m', 'venv', $VenvPath)
    $created = Invoke-Native -File $BasePython -ArgumentList $createArgs -WorkingDirectory $RepoRoot
    Add-CommandLog -Log $Log -Title ($Name + ' venv create') -File $BasePython -ArgumentList $createArgs -Result $created
    $python = Join-Path $VenvPath 'Scripts\python.exe'
    $cfgPath = Join-Path $VenvPath 'pyvenv.cfg'
    if ($created.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $python)) {
        return [pscustomobject]@{
            Ok        = $false
            Stage     = 'create'
            Python    = $python
            Create    = $created
            Install   = $null
            Run       = $null
            Probe     = $null
            PipJson   = ''
            CfgText   = ''
            Cfg       = @{}
            SizeBytes = 0
        }
    }
    $installArgs = @('-m', 'pip', 'install', '--disable-pip-version-check', '-r', $Requirements)
    $installed = Invoke-Native -File $python -ArgumentList $installArgs -WorkingDirectory $ProjectDir
    Add-CommandLog -Log $Log -Title ($Name + ' pip install') -File $python -ArgumentList $installArgs -Result $installed
    Invoke-InterpreterPrint -Log $Log -Title ($Name + ' python -c') -Python $python | Out-Null
    $pipList = Invoke-Native -File $python -ArgumentList @('-m', 'pip', 'list', '--disable-pip-version-check')
    Add-CommandLog -Log $Log -Title ($Name + ' pip list') -File $python -ArgumentList @('-m', 'pip', 'list', '--disable-pip-version-check') -Result $pipList
    $pipJson = Invoke-PipJson -Log $Log -Title ($Name + ' pip list json') -Python $python
    $probeResult = Invoke-ProbeFile -Log $Log -Title ($Name + ' probe') -Python $python -Probe $Probe -WorkingDirectory $ProjectDir
    $runArgs = @('-m', 'isolated_env')
    $ran = Invoke-Native -File $python -ArgumentList $runArgs -WorkingDirectory $ProjectDir
    Add-CommandLog -Log $Log -Title ($Name + ' run project') -File $python -ArgumentList $runArgs -Result $ran
    $cfgText = ''
    if (Test-Path -LiteralPath $cfgPath) {
        $cfgText = [System.IO.File]::ReadAllText($cfgPath)
        [void]$Log.AppendLine('---- ' + $Name + ' pyvenv.cfg ----')
        [void]$Log.AppendLine($cfgText)
        [void]$Log.AppendLine('')
    }
    $size = Get-TreeSizeBytes -Path $VenvPath
    [void]$Log.AppendLine(('{0} directory size bytes: {1}' -f $Name, $size))
    [void]$Log.AppendLine('')
    return [pscustomobject]@{
        Ok        = ($installed.ExitCode -eq 0 -and $ran.ExitCode -eq 0)
        Stage     = $(if ($installed.ExitCode -ne 0) { 'install' } elseif ($ran.ExitCode -ne 0) { 'run' } else { 'done' })
        Python    = $python
        Create    = $created
        Install   = $installed
        Run       = $ran
        ProbeRaw  = $probeResult
        Probe     = (ConvertFrom-ProbeOutput $probeResult)
        PipJson   = [string]$pipJson.StdOut
        CfgText   = $cfgText
        Cfg       = (Read-PyVenvCfg -Path $cfgPath)
        SizeBytes = $size
    }
}

# Step 2-8. First environment.
$run1 = Invoke-Generation -Log $log -Name 'run1' -BasePython $systemPython -VenvPath $venvPath -RepoRoot $repo -ProjectDir $projectDir -Requirements $requirements -Probe $probe -WhereExe $whereExe

$activationText = ''
$activateScript = Join-Path $venvPath 'Scripts\Activate.ps1'
if (Test-Path -LiteralPath $activateScript) {
    $helperLines = @(
        ('Set-Location -LiteralPath ' + (ConvertTo-SingleQuoted $projectDir)),
        ('. ' + (ConvertTo-SingleQuoted $activateScript)),
        "Write-Output '--- where python after activation ---'",
        ('& ' + (ConvertTo-SingleQuoted $whereExe) + ' python'),
        "Write-Output '--- prefix after activation ---'",
        '& python -c "import sys; print(sys.prefix)"'
    )
    $helperPath = Join-Path $env:TEMP ('csi-activate-' + [guid]::NewGuid().ToString('n') + '.ps1')
    Set-TextFile -Path $helperPath -Content ($helperLines -join "`n")
    $powershellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $helperArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $helperPath)
    $activated = Invoke-Native -File $powershellExe -ArgumentList $helperArgs -WorkingDirectory $projectDir
    Add-CommandLog -Log $log -Title 'child process activation' -File $powershellExe -ArgumentList $helperArgs -Result $activated
    $activationText = [string]$activated.Text
    Remove-Item -LiteralPath $helperPath -Force -ErrorAction SilentlyContinue
}
$whereAfter = Invoke-Native -File $whereExe -ArgumentList @('python')
Add-CommandLog -Log $log -Title 'where python in parent after child activation' -File $whereExe -ArgumentList @('python') -Result $whereAfter
$parentWhereUnchanged = ([string]$whereBefore.StdOut).Trim() -eq ([string]$whereAfter.StdOut).Trim()

$systemProbe = ConvertFrom-ProbeOutput $systemProbeResult
$isolationText = New-IsolationText -SystemProbe $systemProbe -VenvProbe $run1.Probe
$systemPairs = @(Get-PipPairs -JsonText ([string]$systemPipJson.StdOut))
$run1Pairs = @(Get-PipPairs -JsonText ([string]$run1.PipJson))
$pipDiffSystem = New-SetDiffText -LeftPairs $systemPairs -RightPairs $run1Pairs -LeftLabel 'system' -RightLabel 'run1'

# Step 9-10. Tear down and recreate.
$run2 = $null
$pipDiffRuns = $null
if (-not $run1.Ok) {
    $reproText = 'Run 1 did not finish cleanly (stage: ' + $run1.Stage + '). Run 2 was not started. The command log has the failure.'
} else {
    $run2 = Invoke-Generation -Log $log -Name 'run2' -BasePython $systemPython -VenvPath $venvPath -RepoRoot $repo -ProjectDir $projectDir -Requirements $requirements -Probe $probe -WhereExe $whereExe
    $run2Pairs = @(Get-PipPairs -JsonText ([string]$run2.PipJson))
    $pipDiffRuns = New-SetDiffText -LeftPairs $run1Pairs -RightPairs $run2Pairs -LeftLabel 'run1' -RightLabel 'run2'
    $reproLines = New-Object System.Collections.Generic.List[string]
    $reproLines.Add('Run 1 was deleted and Run 2 was created from the same base interpreter and requirements.txt.') | Out-Null
    $reproLines.Add(('run1 size bytes: {0}' -f $run1.SizeBytes)) | Out-Null
    $reproLines.Add(('run2 size bytes: {0}' -f $run2.SizeBytes)) | Out-Null
    $reproLines.Add(('sizes match exactly: {0}' -f ($run1.SizeBytes -eq $run2.SizeBytes))) | Out-Null
    $reproLines.Add(('run1 project exit: {0}' -f $run1.Run.ExitCode)) | Out-Null
    $reproLines.Add(('run2 project exit: {0}' -f $run2.Run.ExitCode)) | Out-Null
    $home1 = ''
    $home2 = ''
    $include1 = ''
    $include2 = ''
    $version1 = ''
    $version2 = ''
    if ($run1.Cfg.ContainsKey('home')) { $home1 = [string]$run1.Cfg['home'] }
    if ($run2.Cfg.ContainsKey('home')) { $home2 = [string]$run2.Cfg['home'] }
    if ($run1.Cfg.ContainsKey('include-system-site-packages')) { $include1 = [string]$run1.Cfg['include-system-site-packages'] }
    if ($run2.Cfg.ContainsKey('include-system-site-packages')) { $include2 = [string]$run2.Cfg['include-system-site-packages'] }
    if ($run1.Cfg.ContainsKey('version')) { $version1 = [string]$run1.Cfg['version'] }
    if ($run2.Cfg.ContainsKey('version')) { $version2 = [string]$run2.Cfg['version'] }
    $reproLines.Add(('pyvenv home matches: {0}' -f ($home1 -eq $home2))) | Out-Null
    $reproLines.Add(('include-system-site-packages run1: {0}' -f $include1)) | Out-Null
    $reproLines.Add(('include-system-site-packages run2: {0}' -f $include2)) | Out-Null
    $reproLines.Add(('pyvenv version run1: {0}' -f $version1)) | Out-Null
    $reproLines.Add(('pyvenv version run2: {0}' -f $version2)) | Out-Null
    $reproLines.Add('Package comparison:') | Out-Null
    $reproLines.Add($pipDiffRuns.Text) | Out-Null
    $reproLines.Add('The second environment is left at project\.venv so the project can be run again.') | Out-Null
    $reproText = $reproLines.ToArray() -join "`n"
}

$logPath = Join-Path $rawDir ("m3-commands-{0}.txt" -f $stamp)
Set-TextFile -Path $logPath -Content $log.ToString()
if (-not [string]::IsNullOrWhiteSpace([string]$systemProbeResult.StdOut)) {
    Set-TextFile -Path (Join-Path $rawDir ("m3-system-probe-{0}.json" -f $stamp)) -Content ([string]$systemProbeResult.StdOut)
}
if ($null -ne $run1.ProbeRaw -and -not [string]::IsNullOrWhiteSpace([string]$run1.ProbeRaw.StdOut)) {
    Set-TextFile -Path (Join-Path $rawDir ("m3-run1-probe-{0}.json" -f $stamp)) -Content ([string]$run1.ProbeRaw.StdOut)
}
if ($null -ne $run2 -and $null -ne $run2.ProbeRaw -and -not [string]::IsNullOrWhiteSpace([string]$run2.ProbeRaw.StdOut)) {
    Set-TextFile -Path (Join-Path $rawDir ("m3-run2-probe-{0}.json" -f $stamp)) -Content ([string]$run2.ProbeRaw.StdOut)
}
if (-not [string]::IsNullOrWhiteSpace([string]$run1.CfgText)) {
    Set-TextFile -Path (Join-Path $rawDir ("m3-run1-pyvenv-{0}.cfg" -f $stamp)) -Content ([string]$run1.CfgText)
}
if ($null -ne $run2 -and -not [string]::IsNullOrWhiteSpace([string]$run2.CfgText)) {
    Set-TextFile -Path (Join-Path $rawDir ("m3-run2-pyvenv-{0}.cfg" -f $stamp)) -Content ([string]$run2.CfgText)
}

$cfgHome = ''
$cfgInclude = ''
$cfgVersion = ''
if ($run1.Cfg.ContainsKey('home')) { $cfgHome = [string]$run1.Cfg['home'] }
if ($run1.Cfg.ContainsKey('include-system-site-packages')) { $cfgInclude = [string]$run1.Cfg['include-system-site-packages'] }
if ($run1.Cfg.ContainsKey('version')) { $cfgVersion = [string]$run1.Cfg['version'] }

$result = [pscustomobject]@{
    generated_utc            = (Get-IsoTimestamp)
    prediction_confirmed     = 'true'
    prediction_utc           = $predictionUtc
    stopped                  = ''
    help                     = ''
    python_executable        = $systemPython
    python_version           = [string]$found.Selected.Version
    python_label             = $found.Selected.Label
    run1_ok                  = [string]$run1.Ok
    run1_stage               = [string]$run1.Stage
    run1_exit                = $(if ($null -eq $run1.Run) { '' } else { [string]$run1.Run.ExitCode })
    run1_size_bytes          = [string]$run1.SizeBytes
    run2_ok                  = $(if ($null -eq $run2) { '' } else { [string]$run2.Ok })
    run2_exit                = $(if ($null -eq $run2 -or $null -eq $run2.Run) { '' } else { [string]$run2.Run.ExitCode })
    run2_size_bytes          = $(if ($null -eq $run2) { '' } else { [string]$run2.SizeBytes })
    pyvenv_home              = $cfgHome
    pyvenv_include_system    = $cfgInclude
    pyvenv_version           = $cfgVersion
    parent_where_unchanged   = [string]$parentWhereUnchanged
    activation_text          = $activationText
    isolation_text           = $isolationText
    reproducibility_text     = $reproText
    pip_diff_system_text     = [string]$pipDiffSystem.Text
    pip_diff_runs_text       = $(if ($null -eq $pipDiffRuns) { '' } else { [string]$pipDiffRuns.Text })
    command_log              = $logPath
    final_venv               = $venvPath
}
$jsonPath = Join-Path $rawDir ("m3-result-{0}.json" -f $stamp)
Set-TextFile -Path $jsonPath -Content (ConvertTo-JsonText -Object $result)
Write-Host ("Mission 3 wrote {0}" -f $logPath)
Write-Host 'Review evidence/summary.md after run-all.ps1 finishes. The command log can contain your username inside a path.'
Write-Output ([pscustomobject]@{ Ok = [bool]$run1.Ok; Stamp = $stamp; JsonPath = $jsonPath; Result = $result })
