#Requires -Version 5.1
<#
.SYNOPSIS
    Run the local collectors and write evidence\summary.md.

.DESCRIPTION
    Read-only toward Windows. The only writes are evidence\ and project\.venv.
    No administrator rights. The execution policy is not changed.
#>

param(
    [switch]$SkipMission1,
    [switch]$SkipMission2,
    [switch]$SkipMission3
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\Common.ps1')
. (Join-Path $PSScriptRoot 'lib\Write-Summary.ps1')

function Select-CollectorOutput {
    param($Output)
    $items = @(ConvertTo-List $Output)
    for ($index = $items.Count - 1; $index -ge 0; $index--) {
        $item = $items[$index]
        if ($null -ne (Get-Prop $item 'Result')) {
            return (Get-Prop $item 'Result')
        }
    }
    return $null
}

function Get-StoredResult {
    param([string]$RepoRoot, [string]$Pattern)
    $dir = Join-Path $RepoRoot 'evidence\raw'
    if (-not (Test-Path -LiteralPath $dir)) { return $null }
    $files = @(Get-ChildItem -LiteralPath $dir -Filter $Pattern -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
    if ($files.Count -eq 0) { return $null }
    try {
        return ([System.IO.File]::ReadAllText($files[0].FullName) | ConvertFrom-Json)
    } catch {
        return $null
    }
}

Assert-WindowsHost
$repo = Get-RepoRoot
Set-Location -LiteralPath $repo
Initialize-Evidence -RepoRoot $repo
$ProgressPreference = 'SilentlyContinue'

$transcript = Join-Path $repo ('evidence\raw\console-{0}.txt' -f (Get-StampUtc))
$transcriptStarted = $false
try {
    Start-Transcript -Path $transcript -Force | Out-Null
    $transcriptStarted = $true
} catch {
    Write-Host ('A console transcript was not started: ' + $_.Exception.Message)
}

Write-Host 'Computing Systems Investigator'
Write-Host 'Local collection on this Windows laptop. Nothing here is a remote measurement.'
Write-Host 'Mission 1 reads the device profile.'
Write-Host 'Mission 2 samples a browser task for about 20 seconds at each of four stages.'
Write-Host 'Mission 3 creates project\.venv, removes it, and creates it again. It needs a network connection for pip.'
Write-Host 'The scripts do not ask for administrator rights and do not change system settings.'
Write-Host ''

$mission1 = $null
$mission2 = $null
$mission3 = $null

if ($SkipMission1) {
    Write-Host 'Skipping Mission 1. The summary will use the newest saved profile if one exists.'
    $mission1 = Get-StoredResult -RepoRoot $repo -Pattern 'm1-profile-*.json'
} else {
    $mission1 = Select-CollectorOutput (& (Join-Path $PSScriptRoot 'mission1-device-profile.ps1'))
}

if ($SkipMission2) {
    Write-Host 'Skipping Mission 2. The summary will use the newest saved session if one exists.'
    $mission2 = Get-StoredResult -RepoRoot $repo -Pattern 'm2-session-*.json'
} else {
    $mission2 = Select-CollectorOutput (& (Join-Path $PSScriptRoot 'mission2-task-sampler.ps1'))
}

if ($SkipMission3) {
    Write-Host 'Skipping Mission 3. The summary will use the newest saved result if one exists.'
    $mission3 = Get-StoredResult -RepoRoot $repo -Pattern 'm3-result-*.json'
} else {
    $mission3 = Select-CollectorOutput (& (Join-Path $PSScriptRoot 'mission3-venv-investigation.ps1'))
}

$summary = Write-EvidenceSummary -RepoRoot $repo -Mission1 $mission1 -Mission2 $mission2 -Mission3 $mission3
Write-Host ''
Write-Host 'Collection finished.'
Write-Host ('Redacted summary: {0}' -f $summary)
Write-Host 'Read the summary before you send it.'
Write-Host 'The console transcript can name this Windows account in its header. Do not submit the transcript unchanged.'
Write-Host 'Save the Task Manager screenshots listed in the summary if any row still says no.'

if ($transcriptStarted) {
    try { Stop-Transcript | Out-Null } catch { }
}
