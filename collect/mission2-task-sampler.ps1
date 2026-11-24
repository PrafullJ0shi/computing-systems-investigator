#Requires -Version 5.1
<#
.SYNOPSIS
    Sample CPU, memory, processes, disk, and network across one browser task.

.DESCRIPTION
    The everyday task is opening a browser and loading several tabs.
    The script prompts at each stage, samples for about 20 seconds, and
    writes a CSV. It does not take screenshots. It prints the Task Manager
    shots to take while each sample is running.
#>

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\Common.ps1')

$SampleSeconds = 20

function Format-CsvField {
    param([AllowNull()][string]$Value)
    if ($null -eq $Value) {
        return ''
    }
    $text = [string]$Value
    $chars = @([char]',', [char]'"', [char]"`r", [char]"`n")
    if ($text.IndexOfAny($chars) -ge 0) {
        return '"' + $text.Replace('"', '""') + '"'
    }
    return $text
}

function Format-CsvNumber {
    param($Number)
    if ($null -eq $Number -or $Number -eq '') {
        return ''
    }
    return ([double]$Number).ToString('0.00', [System.Globalization.CultureInfo]::InvariantCulture)
}

function Format-CsvInt {
    param($Number)
    if ($null -eq $Number -or $Number -eq '') {
        return ''
    }
    return ([int64][math]::Round([double]$Number)).ToString([System.Globalization.CultureInfo]::InvariantCulture)
}

function Get-ScreenshotLines {
    param([Parameter(Mandatory = $true)][string]$StageId)
    return @(
        ("evidence/screenshots/m2-{0}-processes.png | Task Manager, Processes. If you see a small window, click More details. Show CPU and Memory, and the summary at the top. Sort by Memory." -f $StageId),
        ("evidence/screenshots/m2-{0}-cpu.png | Performance, CPU." -f $StageId),
        ("evidence/screenshots/m2-{0}-memory.png | Performance, Memory." -f $StageId),
        ("evidence/screenshots/m2-{0}-disk.png | Performance, Disk. If several disks are listed, choose the disk that holds Windows." -f $StageId),
        ("evidence/screenshots/m2-{0}-network.png | Performance, the active Wi-Fi or Ethernet graph. Crop or cover any IPv4 address, IPv6 address, or hardware address before you save it. Do not open the Users tab." -f $StageId)
    )
}

function Read-PerfTable {
    param([Parameter(Mandatory = $true)][string]$LanguageId)
    $key = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Perflib\' + $LanguageId
    $property = Get-ItemProperty -LiteralPath $key -Name Counter -ErrorAction Stop
    $raw = @(ConvertTo-List $property.Counter)
    $table = @{}
    for ($i = 0; $i -lt ($raw.Count - 1); $i += 2) {
        $id = [string]$raw[$i]
        $name = [string]$raw[$i + 1]
        if (-not $table.ContainsKey($id)) {
            $table[$id] = $name
        }
    }
    return $table
}

function Get-NameVariants {
    param([string]$EnglishName, $EnglishTable, $LocalTable)
    $names = New-Object System.Collections.Generic.List[string]
    $names.Add($EnglishName) | Out-Null
    if ($null -eq $EnglishTable -or $null -eq $LocalTable) {
        return $names.ToArray()
    }
    foreach ($id in @($EnglishTable.Keys)) {
        if ([string]$EnglishTable[$id] -ne $EnglishName) {
            continue
        }
        if (-not $LocalTable.ContainsKey([string]$id)) {
            continue
        }
        $localized = [string]$LocalTable[$id]
        if (-not $names.Contains($localized)) {
            $names.Add($localized) | Out-Null
        }
    }
    return $names.ToArray()
}

function New-CounterCandidates {
    param([string[]]$Sets, [string[]]$Counters, [string]$Instance)
    $paths = New-Object System.Collections.Generic.List[string]
    foreach ($set in @(ConvertTo-List $Sets)) {
        foreach ($counter in @(ConvertTo-List $Counters)) {
            if ([string]::IsNullOrEmpty($Instance)) {
                $paths.Add('\' + $set + '\' + $counter) | Out-Null
            } else {
                $paths.Add('\' + $set + '(' + $Instance + ')\' + $counter) | Out-Null
            }
        }
    }
    return $paths.ToArray()
}

function Resolve-CounterPath {
    param([string[]]$Candidates)
    foreach ($candidate in @(ConvertTo-List $Candidates)) {
        try {
            $null = Get-Counter -Counter $candidate -ErrorAction Stop
            return $candidate
        } catch {
            continue
        }
    }
    return $null
}

function Resolve-OneCounter {
    param(
        [string]$SetName,
        [string]$CounterName,
        [string]$Instance,
        $EnglishTable,
        $LocalTable
    )
    $sets = @(Get-NameVariants -EnglishName $SetName -EnglishTable $EnglishTable -LocalTable $LocalTable)
    $counters = @(Get-NameVariants -EnglishName $CounterName -EnglishTable $EnglishTable -LocalTable $LocalTable)
    $candidates = @(New-CounterCandidates -Sets $sets -Counters $counters -Instance $Instance)
    return (Resolve-CounterPath -Candidates $candidates)
}

function Get-CounterSamples {
    param([string]$CounterPath)
    if ([string]::IsNullOrEmpty($CounterPath)) {
        return $null
    }
    try {
        $data = Get-Counter -Counter $CounterPath -ErrorAction Stop
        return @(ConvertTo-List (Get-Prop $data 'CounterSamples'))
    } catch {
        return $null
    }
}

function Get-PreferredCooked {
    param($Samples)
    $rows = @(ConvertTo-List $Samples)
    if ($rows.Count -eq 0) {
        return $null
    }
    foreach ($sample in $rows) {
        $instance = [string](Get-Prop $sample 'InstanceName')
        if ($instance.Equals('_total', [System.StringComparison]::OrdinalIgnoreCase)) {
            $cooked = Get-Prop $sample 'CookedValue'
            if ($null -ne $cooked) { return [double]$cooked }
        }
    }
    if ($rows.Count -eq 1) {
        $cooked = Get-Prop $rows[0] 'CookedValue'
        if ($null -ne $cooked) { return [double]$cooked }
    }
    return $null
}

function Get-NetworkCooked {
    param($Samples)
    $rows = @(ConvertTo-List $Samples)
    if ($rows.Count -eq 0) {
        return $null
    }
    $sum = 0.0
    $found = $false
    foreach ($sample in $rows) {
        $instance = [string](Get-Prop $sample 'InstanceName')
        $lower = $instance.ToLowerInvariant()
        if ($lower.Contains('loopback') -or $lower.Contains('isatap') -or $lower.Contains('teredo')) {
            continue
        }
        $cooked = Get-Prop $sample 'CookedValue'
        if ($null -eq $cooked) {
            continue
        }
        $sum += [double]$cooked
        $found = $true
    }
    if (-not $found) {
        return $null
    }
    return $sum
}

function Get-CimCpuPercent {
    try {
        $rows = @(ConvertTo-List (Get-CimInstance -ClassName 'Win32_PerfFormattedData_PerfOS_Processor' -ErrorAction Stop))
        foreach ($row in $rows) {
            if ([string](Get-Prop $row 'Name') -eq '_Total') {
                $value = Get-Prop $row 'PercentProcessorTime'
                if ($null -ne $value) { return [double]$value }
            }
        }
    } catch {
        return $null
    }
    return $null
}

function Get-CimAvailableMb {
    try {
        $os = Get-CimInstance -ClassName 'Win32_OperatingSystem' -ErrorAction Stop
        $kb = Get-Prop $os 'FreePhysicalMemory'
        if ($null -eq $kb -or $kb -eq '') { return $null }
        return ([double]$kb / 1024.0)
    } catch {
        return $null
    }
}

function Get-CimDisk {
    try {
        $rows = @(ConvertTo-List (Get-CimInstance -ClassName 'Win32_PerfFormattedData_PerfDisk_PhysicalDisk' -ErrorAction Stop))
        foreach ($row in $rows) {
            if ([string](Get-Prop $row 'Name') -eq '_Total') {
                return [pscustomobject]@{
                    Percent = $(if ($null -eq (Get-Prop $row 'PercentDiskTime')) { $null } else { [double](Get-Prop $row 'PercentDiskTime') })
                    Bytes   = $(if ($null -eq (Get-Prop $row 'DiskBytesPersec')) { $null } else { [double](Get-Prop $row 'DiskBytesPersec') })
                }
            }
        }
    } catch {
        return $null
    }
    return $null
}

function Get-CimNetworkBytes {
    try {
        $rows = @(ConvertTo-List (Get-CimInstance -ClassName 'Win32_PerfFormattedData_Tcpip_NetworkInterface' -ErrorAction Stop))
        $sum = 0.0
        $found = $false
        foreach ($row in $rows) {
            $name = [string](Get-Prop $row 'Name')
            $lower = $name.ToLowerInvariant()
            if ($lower.Contains('loopback') -or $lower.Contains('isatap') -or $lower.Contains('teredo')) {
                continue
            }
            $value = Get-Prop $row 'BytesTotalPersec'
            if ($null -eq $value) { continue }
            $sum += [double]$value
            $found = $true
        }
        if ($found) { return $sum }
    } catch {
        return $null
    }
    return $null
}

function Get-BrowserSnapshot {
    param($Processes)
    $wanted = @('chrome', 'msedge', 'firefox', 'brave', 'opera', 'iexplore', 'vivaldi', 'waterfox', 'librewolf', 'chromium')
    $matches = New-Object System.Collections.Generic.List[object]
    foreach ($proc in @(ConvertTo-List $Processes)) {
        $name = [string](Get-Prop $proc 'ProcessName')
        foreach ($candidate in $wanted) {
            if ($name.Equals($candidate, [System.StringComparison]::OrdinalIgnoreCase)) {
                $matches.Add($proc) | Out-Null
                break
            }
        }
    }
    $total = [int64]0
    $parts = New-Object System.Collections.Generic.List[string]
    $ordered = @($matches | Sort-Object -Property WorkingSet64 -Descending)
    $rank = 0
    foreach ($proc in $ordered) {
        $bytes = Get-Prop $proc 'WorkingSet64'
        if ($null -eq $bytes) { $bytes = 0 }
        $total += [int64]$bytes
        $rank += 1
        if ($rank -le 5) {
            $parts.Add(('name={0};pid={1};working_set_bytes={2}' -f (Get-Prop $proc 'ProcessName'), (Get-Prop $proc 'Id'), $bytes)) | Out-Null
        }
    }
    return [pscustomobject]@{
        Count = $matches.Count
        Bytes = $total
        Top   = ($parts.ToArray() -join '|')
    }
}

function Get-MeanText {
    param($Values)
    $numbers = @(ConvertTo-List $Values)
    if ($numbers.Count -eq 0) {
        return ''
    }
    $sum = 0.0
    foreach ($value in $numbers) { $sum += [double]$value }
    return (Format-InvariantNumber -Number ($sum / $numbers.Count) -Decimals 2)
}

function Get-LimitText {
    param($Values, [switch]$Maximum)
    $numbers = @(ConvertTo-List $Values)
    if ($numbers.Count -eq 0) { return '' }
    $best = [double]$numbers[0]
    foreach ($value in $numbers) {
        $current = [double]$value
        if ($Maximum -and $current -gt $best) { $best = $current }
        if (-not $Maximum -and $current -lt $best) { $best = $current }
    }
    return (Format-InvariantNumber -Number $best -Decimals 2)
}

function Collect-Numbers {
    param($Rows, [string]$Name)
    $list = New-Object System.Collections.Generic.List[double]
    foreach ($row in @(ConvertTo-List $Rows)) {
        $text = [string](Get-Prop $row $Name)
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        $parsed = 0.0
        $ok = [double]::TryParse(
            $text,
            [System.Globalization.NumberStyles]::Float,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [ref]$parsed
        )
        if ($ok) { $list.Add($parsed) | Out-Null }
    }
    return $list.ToArray()
}

$repo = Get-RepoRoot
Initialize-Evidence -RepoRoot $repo
$stamp = Get-StampUtc
$rawDir = Join-Path $repo 'evidence\raw'
$csvPath = Join-Path $rawDir ("m2-samples-{0}.csv" -f $stamp)
$checklistPath = Join-Path $rawDir ("m2-screenshot-checklist-{0}.txt" -f $stamp)
$ProgressPreference = 'SilentlyContinue'

Write-Host ''
Write-Host 'Mission 2. Everyday task: open a browser and load several tabs.'
Write-Host 'Four stages. Each stage samples for about 20 seconds.'
Write-Host 'Have Task Manager ready (Ctrl+Shift+Esc).'
Write-Host 'Use public pages. Do not type anything private.'
Write-Host ''

$declaredBrowser = (Read-Host 'Which browser will you open?').Trim()
if ([string]::IsNullOrWhiteSpace($declaredBrowser)) { $declaredBrowser = '(not typed)' }
$declaredPages = (Read-Host 'Which public pages will you load?').Trim()
if ([string]::IsNullOrWhiteSpace($declaredPages)) { $declaredPages = '(not typed)' }

$englishTable = $null
$localTable = $null
$counterNote = 'English counter paths were tried.'
try {
    $perflib = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Perflib'
    $language = [string](Get-ItemProperty -LiteralPath $perflib -Name CurrentLanguage -ErrorAction Stop).CurrentLanguage
    $englishTable = Read-PerfTable -LanguageId '009'
    $localTable = Read-PerfTable -LanguageId $language
    $counterNote = 'Counter names were resolved with Perflib 009 and CurrentLanguage ' + $language + '.'
} catch {
    $counterNote = 'Localized counter names were not read (' + $_.Exception.Message + '). English paths were tried.'
}

$cpuPath = Resolve-OneCounter -SetName 'Processor' -CounterName '% Processor Time' -Instance '_Total' -EnglishTable $englishTable -LocalTable $localTable
$memoryPath = Resolve-OneCounter -SetName 'Memory' -CounterName 'Available MBytes' -Instance '' -EnglishTable $englishTable -LocalTable $localTable
$diskPctPath = Resolve-OneCounter -SetName 'PhysicalDisk' -CounterName '% Disk Time' -Instance '_Total' -EnglishTable $englishTable -LocalTable $localTable
$diskBytesPath = Resolve-OneCounter -SetName 'PhysicalDisk' -CounterName 'Disk Bytes/sec' -Instance '_Total' -EnglishTable $englishTable -LocalTable $localTable
$networkPath = Resolve-OneCounter -SetName 'Network Interface' -CounterName 'Bytes Total/sec' -Instance '*' -EnglishTable $englishTable -LocalTable $localTable

$stagePlans = @(
    [pscustomobject]@{
        Id    = 'before'
        Title = 'Before'
        Body  = 'Close every browser window, including a tray icon if the browser stays running after the last window closes. Leave Task Manager and this window open. When the machine is idle, press Enter. Take the five "before" screenshots while the sample runs. Do not open the browser yet.'
    },
    [pscustomobject]@{
        Id    = 'during'
        Title = 'During'
        Body  = 'Open the browser now and start loading the pages you named. As soon as they are loading, press Enter. Take the five "during" screenshots while the sample runs. Leave the browser open.'
    },
    [pscustomobject]@{
        Id    = 'after'
        Title = 'After'
        Body  = 'Wait until the pages have finished loading and the machine has settled. Leave the browser open on those pages. Press Enter, then take the five "after" screenshots while the sample runs.'
    },
    [pscustomobject]@{
        Id    = 'on-closing'
        Title = 'On closing'
        Body  = 'Close the browser completely. If it remains in the notification area, quit it there too. Press Enter immediately after you close it, then take the five "on-closing" screenshots while the sample runs. If the browser is still listed in Task Manager, leave that fact in your notes.'
    }
)

$checklist = New-Object System.Collections.Generic.List[string]
$checklist.Add('Mission 2 screenshot checklist') | Out-Null
$checklist.Add('Take each file during that stage''s sample. The script cannot take the screenshots.') | Out-Null
$checklist.Add('Place the Processes, CPU, and Memory images in the report body. Place Disk and Network in an appendix.') | Out-Null
$checklist.Add('On the network image, crop or cover any IP address or hardware address.') | Out-Null
$checklist.Add('Do not photograph the Users tab or a page that shows the computer name.') | Out-Null
$checklist.Add('') | Out-Null
foreach ($plan in $stagePlans) {
    $checklist.Add('== ' + $plan.Title + ' ==') | Out-Null
    $checklist.Add($plan.Body) | Out-Null
    foreach ($line in (Get-ScreenshotLines -StageId $plan.Id)) {
        $checklist.Add($line) | Out-Null
    }
    $checklist.Add('') | Out-Null
}
Set-TextFile -Path $checklistPath -Content ($checklist.ToArray() -join "`n")
Write-Host ("Screenshot checklist: {0}" -f $checklistPath)
Write-Host $counterNote

$header = @(
    'timestamp_utc', 'stage', 'sample_index', 'elapsed_ms',
    'cpu_percent', 'cpu_source',
    'available_memory_mb', 'memory_source',
    'process_count', 'browser_process_count', 'browser_working_set_bytes', 'top_browser_processes',
    'disk_percent_time', 'disk_bytes_per_sec', 'disk_source',
    'network_bytes_per_sec', 'network_source'
)
$headerLine = ($header | ForEach-Object { Format-CsvField $_ }) -join ','
$utf8Bom = New-Object System.Text.UTF8Encoding $true
[System.IO.File]::WriteAllText($csvPath, $headerLine + "`r`n", $utf8Bom)
$utf8 = New-Object System.Text.UTF8Encoding $false

$rows = New-Object System.Collections.Generic.List[object]
$pathsToPrime = @($cpuPath, $memoryPath, $diskPctPath, $diskBytesPath, $networkPath) | Where-Object { -not [string]::IsNullOrEmpty($_) }
if (@($pathsToPrime).Count -gt 0) {
    Write-Host 'Reading each rate counter once and discarding that read, so the recorded samples have a previous observation.'
    foreach ($path in @($pathsToPrime)) {
        try { $null = Get-Counter -Counter $path -ErrorAction Stop } catch { }
    }
    Start-Sleep -Seconds 1
}

foreach ($plan in $stagePlans) {
    Write-Host ''
    Write-Host ('======== ' + $plan.Title + ' ========')
    Write-Host $plan.Body
    Write-Host 'Screenshots to take during this sample:'
    foreach ($line in (Get-ScreenshotLines -StageId $plan.Id)) {
        Write-Host ('  ' + $line)
    }
    Read-Host ('Press Enter to start the ' + $plan.Title + ' sample') | Out-Null
    Write-Host 'Sampling for about 20 seconds. Take the screenshots now.'
    $deadline = (Get-Date).AddSeconds($SampleSeconds)
    $index = 0
    while ((Get-Date) -lt $deadline -and $index -lt 25) {
        $index += 1
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        $cpu = $null
        $cpuSource = ''
        $cpuSamples = Get-CounterSamples -CounterPath $cpuPath
        $cpu = Get-PreferredCooked -Samples $cpuSamples
        if ($null -ne $cpu) {
            $cpuSource = 'Get-Counter'
        } else {
            $cpu = Get-CimCpuPercent
            if ($null -ne $cpu) { $cpuSource = 'Win32_PerfFormattedData_PerfOS_Processor' }
        }

        $memory = $null
        $memorySource = ''
        $memorySamples = Get-CounterSamples -CounterPath $memoryPath
        $memory = Get-PreferredCooked -Samples $memorySamples
        if ($null -ne $memory) {
            $memorySource = 'Get-Counter'
        } else {
            $memory = Get-CimAvailableMb
            if ($null -ne $memory) { $memorySource = 'Win32_OperatingSystem.FreePhysicalMemory' }
        }

        $diskPercent = $null
        $diskBytes = $null
        $diskSource = ''
        $diskPercentSamples = Get-CounterSamples -CounterPath $diskPctPath
        $diskByteSamples = Get-CounterSamples -CounterPath $diskBytesPath
        $diskPercent = Get-PreferredCooked -Samples $diskPercentSamples
        $diskBytes = Get-PreferredCooked -Samples $diskByteSamples
        if ($null -ne $diskPercent -or $null -ne $diskBytes) {
            $diskSource = 'Get-Counter'
        } else {
            $cimDisk = Get-CimDisk
            if ($null -ne $cimDisk) {
                $diskPercent = $cimDisk.Percent
                $diskBytes = $cimDisk.Bytes
                if ($null -ne $diskPercent -or $null -ne $diskBytes) {
                    $diskSource = 'Win32_PerfFormattedData_PerfDisk_PhysicalDisk'
                }
            }
        }

        $network = $null
        $networkSource = ''
        $networkSamples = Get-CounterSamples -CounterPath $networkPath
        $network = Get-NetworkCooked -Samples $networkSamples
        if ($null -ne $network) {
            $networkSource = 'Get-Counter'
        } else {
            $network = Get-CimNetworkBytes
            if ($null -ne $network) { $networkSource = 'Win32_PerfFormattedData_Tcpip_NetworkInterface' }
        }

        $processCount = $null
        $browser = [pscustomobject]@{ Count = $null; Bytes = $null; Top = '' }
        try {
            $processes = @(ConvertTo-List (Get-Process -ErrorAction Stop))
            $processCount = $processes.Count
            $browser = Get-BrowserSnapshot -Processes $processes
        } catch {
            $processCount = $null
        }

        $watch.Stop()
        $row = [pscustomobject]@{
            timestamp_utc             = (Get-IsoTimestamp)
            stage                     = $plan.Id
            sample_index              = $index
            elapsed_ms                = $watch.ElapsedMilliseconds
            cpu_percent               = (Format-CsvNumber $cpu)
            cpu_source                = $cpuSource
            available_memory_mb       = (Format-CsvNumber $memory)
            memory_source             = $memorySource
            process_count             = $(if ($null -eq $processCount) { '' } else { [string]$processCount })
            browser_process_count     = $(if ($null -eq $browser.Count) { '' } else { [string]$browser.Count })
            browser_working_set_bytes = $(if ($null -eq $browser.Bytes) { '' } else { [string]$browser.Bytes })
            top_browser_processes     = [string]$browser.Top
            disk_percent_time         = (Format-CsvNumber $diskPercent)
            disk_bytes_per_sec        = (Format-CsvNumber $diskBytes)
            disk_source               = $diskSource
            network_bytes_per_sec     = (Format-CsvNumber $network)
            network_source            = $networkSource
        }
        $values = @(
            $row.timestamp_utc, $row.stage, $row.sample_index, $row.elapsed_ms,
            $row.cpu_percent, $row.cpu_source,
            $row.available_memory_mb, $row.memory_source,
            $row.process_count, $row.browser_process_count, $row.browser_working_set_bytes, $row.top_browser_processes,
            $row.disk_percent_time, $row.disk_bytes_per_sec, $row.disk_source,
            $row.network_bytes_per_sec, $row.network_source
        )
        $line = ($values | ForEach-Object { Format-CsvField ([string]$_) }) -join ','
        [System.IO.File]::AppendAllText($csvPath, $line + "`r`n", $utf8)
        $rows.Add($row) | Out-Null
        $remaining = 1000 - $watch.ElapsedMilliseconds
        if ($remaining -gt 50 -and (Get-Date).AddMilliseconds($remaining) -lt $deadline.AddSeconds(1)) {
            Start-Sleep -Milliseconds ([int]$remaining)
        }
    }
    Write-Host ("{0} sample stored ({1} rows)." -f $plan.Title, $index)
}

$closingNote = (Read-Host 'Optional: one sentence on what you noticed, or press Enter to skip').Trim()
if ([string]::IsNullOrWhiteSpace($closingNote)) { $closingNote = '(not typed)' }

$statLines = New-Object System.Collections.Generic.List[string]
foreach ($plan in $stagePlans) {
    $stageRows = @($rows | Where-Object { $_.stage -eq $plan.Id })
    $cpuValues = @(Collect-Numbers -Rows $stageRows -Name 'cpu_percent')
    $memValues = @(Collect-Numbers -Rows $stageRows -Name 'available_memory_mb')
    $procValues = @(Collect-Numbers -Rows $stageRows -Name 'process_count')
    $wsValues = @(Collect-Numbers -Rows $stageRows -Name 'browser_working_set_bytes')
    $diskValues = @(Collect-Numbers -Rows $stageRows -Name 'disk_bytes_per_sec')
    $netValues = @(Collect-Numbers -Rows $stageRows -Name 'network_bytes_per_sec')
    $statLines.Add((
        '{0} samples={1} cpu_mean={2} cpu_min={3} cpu_max={4} available_mb_mean={5} available_mb_min={6} available_mb_max={7} process_mean={8} browser_working_set_bytes_mean={9} disk_bytes_per_sec_mean={10} network_bytes_per_sec_mean={11}' -f `
            $plan.Id, $stageRows.Count, (Get-MeanText -Values $cpuValues), (Get-LimitText -Values $cpuValues), (Get-LimitText -Values $cpuValues -Maximum), `
            (Get-MeanText -Values $memValues), (Get-LimitText -Values $memValues), (Get-LimitText -Values $memValues -Maximum), `
            (Get-MeanText -Values $procValues), (Get-MeanText -Values $wsValues), (Get-MeanText -Values $diskValues), (Get-MeanText -Values $netValues)
    )) | Out-Null
}

$expected = New-Object System.Collections.Generic.List[string]
foreach ($plan in $stagePlans) {
    foreach ($kind in @('processes', 'cpu', 'memory', 'disk', 'network')) {
        $expected.Add(('evidence/screenshots/m2-{0}-{1}.png' -f $plan.Id, $kind)) | Out-Null
    }
}

$result = [pscustomobject]@{
    generated_utc          = (Get-IsoTimestamp)
    declared_browser       = $declaredBrowser
    declared_pages         = $declaredPages
    closing_note           = $closingNote
    sample_seconds         = $SampleSeconds
    counter_note           = $counterNote
    cpu_counter            = [string]$cpuPath
    memory_counter         = [string]$memoryPath
    disk_percent_counter   = [string]$diskPctPath
    disk_bytes_counter     = [string]$diskBytesPath
    network_counter        = [string]$networkPath
    csv                    = $csvPath
    checklist              = $checklistPath
    stage_stats            = ($statLines.ToArray() -join "`n")
    expected_screenshots   = ($expected.ToArray() -join "`n")
    measurement_note       = 'Means ignore blank cells. They are calculated from the CSV and are not a second measurement. The first Get-Counter read of each rate counter was discarded before recording. Browser working set is the sum of WorkingSet64 across matching processes, so shared pages can be counted more than once. % Disk Time can read 0 or above 100; Disk Bytes/sec is recorded beside it. Task Manager was open during the samples.'
}

$jsonPath = Join-Path $rawDir ("m2-session-{0}.json" -f $stamp)
Set-TextFile -Path $jsonPath -Content (ConvertTo-JsonText -Object $result)
Write-Host ("Mission 2 wrote {0}" -f $csvPath)
Write-Output ([pscustomobject]@{
    Ok       = $true
    Stamp    = $stamp
    JsonPath = $jsonPath
    CsvPath  = $csvPath
    Result   = $result
})
