#Requires -Version 5.1
<#
.SYNOPSIS
    Read a device profile with built-in Windows tools.

.DESCRIPTION
    Read-only. No administrator rights. Serial numbers, MAC addresses,
    private IP addresses, usernames, and the computer name are not collected.
    Each field is marked observed, not_exposed, or omitted.
#>

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\Common.ps1')

function Get-MappedName {
    param($Map, $Code)
    if ($null -eq $Code -or $Code -eq '') {
        return $null
    }
    $key = [string]$Code
    if ($Map.ContainsKey($key)) {
        return ("{0} ({1})" -f $key, $Map[$key])
    }
    return ("{0} (no name in the collector map; keep the raw code)" -f $key)
}

function Add-ProfileField {
    param($Fields, $Area, $Name, $Value, $Source, $Status = '', $Note = '')
    $Fields.Add((New-Field -Area $Area -Name $Name -Value $Value -Source $Source -Status $Status -Note $Note)) | Out-Null
}

$repo = Get-RepoRoot
Initialize-Evidence -RepoRoot $repo
$stamp = Get-StampUtc
$fields = New-Object System.Collections.Generic.List[object]
$errors = New-Object System.Collections.Generic.List[string]
$candidates = New-Object System.Collections.Generic.List[string]

$pcSystemType = @{
    '0' = 'Unspecified'
    '1' = 'Desktop'
    '2' = 'Mobile'
    '3' = 'Workstation'
    '4' = 'Enterprise Server'
    '5' = 'SOHO Server'
    '6' = 'Appliance PC'
    '7' = 'Performance Server'
    '8' = 'Slate'
}
$chassisType = @{
    '1'  = 'Other'
    '2'  = 'Unknown'
    '3'  = 'Desktop'
    '4'  = 'Low Profile Desktop'
    '5'  = 'Pizza Box'
    '6'  = 'Mini Tower'
    '7'  = 'Tower'
    '8'  = 'Portable'
    '9'  = 'Laptop'
    '10' = 'Notebook'
    '11' = 'Hand Held'
    '12' = 'Docking Station'
    '13' = 'All in One'
    '14' = 'Sub Notebook'
    '15' = 'Space-Saving'
    '16' = 'Lunch Box'
    '17' = 'Main System Chassis'
    '18' = 'Expansion Chassis'
    '19' = 'SubChassis'
    '20' = 'Bus Expansion Chassis'
    '21' = 'Peripheral Chassis'
    '22' = 'Storage Chassis'
    '23' = 'Rack Mount Chassis'
    '24' = 'Sealed-Case PC'
    '30' = 'Tablet'
    '31' = 'Convertible'
    '32' = 'Detachable'
}
# Names below are the CIM MemoryType values documented for Win32_PhysicalMemory.
# SMBIOSMemoryType is a different code. This script stores that code raw.
$memoryType = @{
    '0'  = 'Unknown'
    '1'  = 'Other'
    '2'  = 'DRAM'
    '3'  = 'Synchronous DRAM'
    '4'  = 'Cache DRAM'
    '5'  = 'EDO'
    '6'  = 'EDRAM'
    '7'  = 'VRAM'
    '8'  = 'SRAM'
    '9'  = 'RAM'
    '10' = 'ROM'
    '11' = 'Flash'
    '12' = 'EEPROM'
    '13' = 'FEPROM'
    '14' = 'EPROM'
    '15' = 'CDRAM'
    '16' = '3DRAM'
    '17' = 'SDRAM'
    '18' = 'SGRAM'
    '19' = 'RDRAM'
    '20' = 'DDR'
    '21' = 'DDR2'
    '22' = 'DDR2 FB-DIMM'
    '24' = 'DDR3'
    '25' = 'FBD2'
    '26' = 'DDR4'
}
$cacheLevel = @{
    '3' = 'L1'
    '4' = 'L2'
    '5' = 'L3'
}
$cacheKind = @{
    '1' = 'Other'
    '2' = 'Unknown'
    '3' = 'Instruction'
    '4' = 'Data'
    '5' = 'Unified'
}
$netStatus = @{
    '0'  = 'Disconnected'
    '1'  = 'Connecting'
    '2'  = 'Connected'
    '3'  = 'Disconnecting'
    '4'  = 'Hardware not present'
    '5'  = 'Hardware disabled'
    '6'  = 'Hardware malfunction'
    '7'  = 'Media disconnected'
    '8'  = 'Authenticating'
    '9'  = 'Authentication succeeded'
    '10' = 'Authentication failed'
    '11' = 'Invalid address'
    '12' = 'Credentials required'
}

Add-ProfileField $fields 'Collector' 'PowerShell version' $PSVersionTable.PSVersion.ToString() '$PSVersionTable.PSVersion'
Add-ProfileField $fields 'Collector' 'PowerShell edition' $PSVersionTable.PSEdition '$PSVersionTable.PSEdition'

$computer = Get-CimSafe -ClassName 'Win32_ComputerSystem'
if (-not $computer.Ok) {
    $errors.Add('Win32_ComputerSystem: ' + $computer.Error) | Out-Null
    Add-ProfileField $fields 'Device and operating system' 'Manufacturer' $null 'Win32_ComputerSystem' 'not_exposed' $computer.Error
    Add-ProfileField $fields 'Device and operating system' 'Model' $null 'Win32_ComputerSystem' 'not_exposed' $computer.Error
} else {
    $system = $null
    if ($computer.Items.Count -gt 0) {
        $system = $computer.Items[0]
    }
    Add-ProfileField $fields 'Device and operating system' 'Manufacturer' (Get-Prop $system 'Manufacturer') 'Win32_ComputerSystem.Manufacturer'
    Add-ProfileField $fields 'Device and operating system' 'Model' (Get-Prop $system 'Model') 'Win32_ComputerSystem.Model'
    Add-ProfileField $fields 'Device and operating system' 'System type' (Get-Prop $system 'SystemType') 'Win32_ComputerSystem.SystemType'
    $pcCode = Get-Prop $system 'PCSystemType'
    Add-ProfileField $fields 'Device and operating system' 'PCSystemType' (Get-MappedName $pcSystemType $pcCode) 'Win32_ComputerSystem.PCSystemType' '' 'Documented names: Microsoft Win32_ComputerSystem. The word Mobile is the documented name for code 2; it is not rewritten to laptop.'
    $totalMemory = Get-Prop $system 'TotalPhysicalMemory'
    Add-ProfileField $fields 'Memory' 'Total physical memory' (Format-Bytes $totalMemory) 'Win32_ComputerSystem.TotalPhysicalMemory'
}

Add-ProfileField $fields 'Device and operating system' 'Computer name' $null 'not collected' 'omitted' 'Hostnames are omitted.'
Add-ProfileField $fields 'Device and operating system' 'User name' $null 'not collected' 'omitted' 'Usernames are omitted.'
Add-ProfileField $fields 'Device and operating system' 'Serial number' $null 'not collected' 'omitted' 'Serial numbers are omitted.'

$enclosure = Get-CimSafe -ClassName 'Win32_SystemEnclosure'
if (-not $enclosure.Ok) {
    $errors.Add('Win32_SystemEnclosure: ' + $enclosure.Error) | Out-Null
    Add-ProfileField $fields 'Device and operating system' 'ChassisTypes' $null 'Win32_SystemEnclosure' 'not_exposed' $enclosure.Error
} elseif ($enclosure.Items.Count -eq 0) {
    Add-ProfileField $fields 'Device and operating system' 'ChassisTypes' $null 'Win32_SystemEnclosure.ChassisTypes' 'not_exposed'
} else {
    $codes = @(Get-Prop $enclosure.Items[0] 'ChassisTypes')
    if ($codes.Count -eq 0 -or $null -eq $codes[0]) {
        Add-ProfileField $fields 'Device and operating system' 'ChassisTypes' $null 'Win32_SystemEnclosure.ChassisTypes' 'not_exposed'
    } else {
        $names = @()
        foreach ($code in $codes) {
            $names += (Get-MappedName $chassisType $code)
        }
        Add-ProfileField $fields 'Device and operating system' 'ChassisTypes' ($names -join '; ') 'Win32_SystemEnclosure.ChassisTypes'
    }
}

$osInfo = Get-CimSafe -ClassName 'Win32_OperatingSystem'
if (-not $osInfo.Ok -or $osInfo.Items.Count -eq 0) {
    $message = $osInfo.Error
    if ([string]::IsNullOrEmpty($message)) { $message = 'no instances' }
    $errors.Add('Win32_OperatingSystem: ' + $message) | Out-Null
    Add-ProfileField $fields 'Device and operating system' 'Operating system name' $null 'Win32_OperatingSystem' 'not_exposed' $message
    Add-ProfileField $fields 'Device and operating system' 'Version' $null 'Win32_OperatingSystem' 'not_exposed' $message
    Add-ProfileField $fields 'Device and operating system' 'Build number' $null 'Win32_OperatingSystem' 'not_exposed' $message
    Add-ProfileField $fields 'Device and operating system' 'OS architecture' $null 'Win32_OperatingSystem' 'not_exposed' $message
} else {
    $os = $osInfo.Items[0]
    Add-ProfileField $fields 'Device and operating system' 'Operating system name' (Get-Prop $os 'Caption') 'Win32_OperatingSystem.Caption' '' 'Use Caption together with Version and BuildNumber. Version stays in the 10.0 series on Windows 10 and Windows 11.'
    Add-ProfileField $fields 'Device and operating system' 'Version' (Get-Prop $os 'Version') 'Win32_OperatingSystem.Version'
    Add-ProfileField $fields 'Device and operating system' 'Build number' (Get-Prop $os 'BuildNumber') 'Win32_OperatingSystem.BuildNumber'
    Add-ProfileField $fields 'Device and operating system' 'OS architecture' (Get-Prop $os 'OSArchitecture') 'Win32_OperatingSystem.OSArchitecture'
}

$processors = Get-CimSafe -ClassName 'Win32_Processor'
$coreTotal = $null
$logicalTotal = $null
if (-not $processors.Ok) {
    $errors.Add('Win32_Processor: ' + $processors.Error) | Out-Null
    Add-ProfileField $fields 'Processor' 'Vendor' $null 'Win32_Processor' 'not_exposed' $processors.Error
    Add-ProfileField $fields 'Processor' 'Model' $null 'Win32_Processor' 'not_exposed' $processors.Error
} elseif ($processors.Items.Count -eq 0) {
    Add-ProfileField $fields 'Processor' 'Model' $null 'Win32_Processor' 'not_exposed' 'The class returned no instances.'
} else {
    $index = 0
    $coreSum = 0
    $logicalSum = 0
    $sawCore = $false
    $sawLogical = $false
    foreach ($cpu in $processors.Items) {
        $index += 1
        $suffix = ''
        if ($processors.Items.Count -gt 1) { $suffix = " #$index" }
        Add-ProfileField $fields 'Processor' ("Vendor" + $suffix) (Get-Prop $cpu 'Manufacturer') 'Win32_Processor.Manufacturer'
        Add-ProfileField $fields 'Processor' ("Model" + $suffix) (Get-Prop $cpu 'Name') 'Win32_Processor.Name'
        $cores = Get-Prop $cpu 'NumberOfCores'
        $logical = Get-Prop $cpu 'NumberOfLogicalProcessors'
        Add-ProfileField $fields 'Processor' ("Cores" + $suffix) $cores 'Win32_Processor.NumberOfCores'
        Add-ProfileField $fields 'Processor' ("Logical processors" + $suffix) $logical 'Win32_Processor.NumberOfLogicalProcessors'
        Add-ProfileField $fields 'Processor' ("Max clock (MHz)" + $suffix) (Get-Prop $cpu 'MaxClockSpeed') 'Win32_Processor.MaxClockSpeed' '' 'This is the clock the class reports, not a timed benchmark.'
        Add-ProfileField $fields 'Processor' ("Address width" + $suffix) (Get-Prop $cpu 'AddressWidth') 'Win32_Processor.AddressWidth'
        Add-ProfileField $fields 'Processor' ("L2 cache KB" + $suffix) (Get-Prop $cpu 'L2CacheSize') 'Win32_Processor.L2CacheSize' '' 'Kilobytes, as reported by the property. Blank means not exposed.'
        Add-ProfileField $fields 'Processor' ("L3 cache KB" + $suffix) (Get-Prop $cpu 'L3CacheSize') 'Win32_Processor.L3CacheSize' '' 'Kilobytes, as reported by the property. Blank means not exposed.'
        $virt = Get-Prop $cpu 'VirtualizationFirmwareEnabled'
        if ($null -eq $virt) {
            Add-ProfileField $fields 'Processor' ("VirtualizationFirmwareEnabled" + $suffix) $null 'Win32_Processor.VirtualizationFirmwareEnabled' 'not_exposed'
        } else {
            Add-ProfileField $fields 'Processor' ("VirtualizationFirmwareEnabled" + $suffix) ([string]$virt) 'Win32_Processor.VirtualizationFirmwareEnabled'
        }
        if ($null -ne $cores -and $cores -ne '') { $coreSum += [int]$cores; $sawCore = $true }
        if ($null -ne $logical -and $logical -ne '') { $logicalSum += [int]$logical; $sawLogical = $true }
    }
    if ($sawCore) { $coreTotal = $coreSum }
    if ($sawLogical) { $logicalTotal = $logicalSum }
    if ($sawCore -and $sawLogical -and $logicalSum -gt $coreSum) {
        $candidates.Add(("Win32_Processor reports {0} logical processors and {1} cores." -f $logicalSum, $coreSum)) | Out-Null
    }
}
Add-ProfileField $fields 'Processor' 'ProcessorId' $null 'not collected' 'omitted' 'ProcessorId is omitted.'

$caches = Get-CimSafe -ClassName 'Win32_CacheMemory'
if (-not $caches.Ok) {
    $errors.Add('Win32_CacheMemory: ' + $caches.Error) | Out-Null
    Add-ProfileField $fields 'Memory' 'Cache' $null 'Win32_CacheMemory' 'not_exposed' $caches.Error
} elseif ($caches.Items.Count -eq 0) {
    Add-ProfileField $fields 'Memory' 'Cache' $null 'Win32_CacheMemory' 'not_exposed' 'Win32_CacheMemory returned no instances.'
} else {
    $index = 0
    foreach ($cache in $caches.Items) {
        $index += 1
        $level = Get-MappedName $cacheLevel (Get-Prop $cache 'Level')
        $kind = Get-MappedName $cacheKind (Get-Prop $cache 'CacheType')
        $installed = Get-Prop $cache 'InstalledSize'
        $max = Get-Prop $cache 'MaxCacheSize'
        $purpose = Get-Prop $cache 'Purpose'
        $text = "level={0}; type={1}; installed_kb={2}; max_kb={3}; purpose={4}" -f $level, $kind, $installed, $max, $purpose
        Add-ProfileField $fields 'Memory' ("Cache entry #{0}" -f $index) $text 'Win32_CacheMemory' '' 'Sizes are kilobytes as reported. Level names 3=L1, 4=L2, 5=L3 follow the Win32_CacheMemory documentation.'
    }
}

$modules = Get-CimSafe -ClassName 'Win32_PhysicalMemory'
if (-not $modules.Ok) {
    $errors.Add('Win32_PhysicalMemory: ' + $modules.Error) | Out-Null
    Add-ProfileField $fields 'Memory' 'Modules' $null 'Win32_PhysicalMemory' 'not_exposed' $modules.Error
} elseif ($modules.Items.Count -eq 0) {
    Add-ProfileField $fields 'Memory' 'Modules' $null 'Win32_PhysicalMemory' 'not_exposed' 'Win32_PhysicalMemory returned no instances.'
} else {
    $index = 0
    $sumBytes = [int64]0
    $sawCapacity = $false
    foreach ($stick in $modules.Items) {
        $index += 1
        $capacity = Get-Prop $stick 'Capacity'
        if ($null -ne $capacity -and $capacity -ne '') {
            $sumBytes += [int64]$capacity
            $sawCapacity = $true
        }
        $cimType = Get-MappedName $memoryType (Get-Prop $stick 'MemoryType')
        $smbios = Get-Prop $stick 'SMBIOSMemoryType'
        $speed = Get-Prop $stick 'Speed'
        $configured = Get-Prop $stick 'ConfiguredClockSpeed'
        $form = Get-Prop $stick 'FormFactor'
        $bank = Get-Prop $stick 'BankLabel'
        $locator = Get-Prop $stick 'DeviceLocator'
        $text = "capacity={0}; MemoryType={1}; SMBIOSMemoryType={2}; speed={3}; configured_clock={4}; form_factor={5}; bank={6}; locator={7}" -f (Format-Bytes $capacity), $cimType, $smbios, $speed, $configured, $form, $bank, $locator
        Add-ProfileField $fields 'Memory' ("Module #{0}" -f $index) $text 'Win32_PhysicalMemory' '' 'MemoryType uses the CIM names on the Microsoft Win32_PhysicalMemory page. SMBIOSMemoryType is the raw firmware code and is not renamed by this script. SerialNumber and PartNumber are omitted.'
    }
    if ($sawCapacity) {
        Add-ProfileField $fields 'Memory' 'Sum of module capacities' (Format-Bytes $sumBytes) 'sum of Win32_PhysicalMemory.Capacity' '' 'This sum can differ from TotalPhysicalMemory. Keep both figures.'
    }
}
Add-ProfileField $fields 'Memory' 'Module serial number' $null 'not collected' 'omitted' 'Serial numbers are omitted.'
Add-ProfileField $fields 'Memory' 'Module part number' $null 'not collected' 'omitted' 'Part numbers are omitted.'

$drives = Get-CimSafe -ClassName 'Win32_DiskDrive'
if (-not $drives.Ok) {
    $errors.Add('Win32_DiskDrive: ' + $drives.Error) | Out-Null
    Add-ProfileField $fields 'Storage' 'Disk drives' $null 'Win32_DiskDrive' 'not_exposed' $drives.Error
} elseif ($drives.Items.Count -eq 0) {
    Add-ProfileField $fields 'Storage' 'Disk drives' $null 'Win32_DiskDrive' 'not_exposed'
} else {
    $index = 0
    foreach ($disk in $drives.Items) {
        $index += 1
        $text = "model={0}; interface={1}; media_type={2}; size={3}; partitions={4}; status={5}" -f (Get-Prop $disk 'Model'), (Get-Prop $disk 'InterfaceType'), (Get-Prop $disk 'MediaType'), (Format-Bytes (Get-Prop $disk 'Size')), (Get-Prop $disk 'Partitions'), (Get-Prop $disk 'Status')
        Add-ProfileField $fields 'Storage' ("Disk drive #{0}" -f $index) $text 'Win32_DiskDrive' '' 'SerialNumber, PNPDeviceID, and FirmwareRevision are omitted. MediaType on this class is often a generic phrase; compare it with Get-PhysicalDisk.'
    }
}

try {
    $physical = @(ConvertTo-List (Get-PhysicalDisk -ErrorAction Stop))
    if ($physical.Count -eq 0) {
        Add-ProfileField $fields 'Storage' 'Physical disk media' $null 'Get-PhysicalDisk' 'not_exposed' 'Get-PhysicalDisk returned no disks.'
    } else {
        $index = 0
        foreach ($disk in $physical) {
            $index += 1
            $media = Get-Prop $disk 'MediaType'
            $text = "friendly_name={0}; media_type={1}; bus_type={2}; size={3}; health={4}" -f (Get-Prop $disk 'FriendlyName'), $media, (Get-Prop $disk 'BusType'), (Format-Bytes (Get-Prop $disk 'Size')), (Get-Prop $disk 'HealthStatus')
            Add-ProfileField $fields 'Storage' ("Physical disk #{0}" -f $index) $text 'Get-PhysicalDisk' '' 'SerialNumber and UniqueId are omitted. MediaType is the storage-type field (HDD, SSD, SCM, or Unspecified).'
            if ($null -ne $media -and [string]$media -ne '' -and [string]$media -ne 'Unspecified') {
                $candidates.Add(("Get-PhysicalDisk reports MediaType {0} for physical disk #{1}." -f $media, $index)) | Out-Null
            }
        }
    }
} catch {
    $errors.Add('Get-PhysicalDisk: ' + $_.Exception.Message) | Out-Null
    Add-ProfileField $fields 'Storage' 'Physical disk media' $null 'Get-PhysicalDisk' 'not_exposed' $_.Exception.Message
}

$logical = Get-CimSafe -ClassName 'Win32_LogicalDisk'
if (-not $logical.Ok) {
    $errors.Add('Win32_LogicalDisk: ' + $logical.Error) | Out-Null
    Add-ProfileField $fields 'Storage' 'Fixed volumes' $null 'Win32_LogicalDisk' 'not_exposed' $logical.Error
} else {
    $foundFixed = $false
    foreach ($volume in $logical.Items) {
        $driveType = Get-Prop $volume 'DriveType'
        if ([string]$driveType -ne '3') {
            continue
        }
        $foundFixed = $true
        $deviceId = Get-Prop $volume 'DeviceID'
        $text = "file_system={0}; size={1}; free_space={2}" -f (Get-Prop $volume 'FileSystem'), (Format-Bytes (Get-Prop $volume 'Size')), (Format-Bytes (Get-Prop $volume 'FreeSpace'))
        Add-ProfileField $fields 'Storage' ("Fixed volume {0}" -f $deviceId) $text 'Win32_LogicalDisk' '' 'DriveType 3 is a local disk. VolumeName is omitted. Removable and network drives are not listed.'
    }
    if (-not $foundFixed) {
        Add-ProfileField $fields 'Storage' 'Fixed volumes' $null 'Win32_LogicalDisk' 'not_exposed' 'No DriveType 3 volumes were returned.'
    }
}

$adapterNote = ''
try {
    $adapters = @(Get-NetAdapter -ErrorAction Stop)
    $physicalCount = 0
    $otherCount = 0
    foreach ($adapter in $adapters) {
        $hardware = Get-Prop $adapter 'HardwareInterface'
        $isHardware = $false
        if ($null -ne $hardware) {
            $isHardware = [bool]$hardware
        }
        if (-not $isHardware) {
            $otherCount += 1
            continue
        }
        $physicalCount += 1
        $text = "name={0}; description={1}; status={2}; media_type={3}; link_speed={4}" -f (Get-Prop $adapter 'Name'), (Get-Prop $adapter 'InterfaceDescription'), (Get-Prop $adapter 'Status'), (Get-Prop $adapter 'MediaType'), (Get-Prop $adapter 'LinkSpeed')
        Add-ProfileField $fields 'Network and I/O' ("Adapter #{0}" -f $physicalCount) $text 'Get-NetAdapter' '' 'Type and status only. MacAddress and every IP address are omitted.'
    }
    Add-ProfileField $fields 'Network and I/O' 'Non-physical adapter count' ([string]$otherCount) 'Get-NetAdapter' '' 'Names of non-physical adapters are omitted. Only the count is kept.'
    if ($physicalCount -eq 0) {
        Add-ProfileField $fields 'Network and I/O' 'Physical adapters' $null 'Get-NetAdapter' 'not_exposed' 'No adapter with HardwareInterface true was returned.'
    }
} catch {
    $adapterNote = $_.Exception.Message
    $errors.Add('Get-NetAdapter: ' + $adapterNote) | Out-Null
    $fallback = Get-CimSafe -ClassName 'Win32_NetworkAdapter'
    if (-not $fallback.Ok) {
        Add-ProfileField $fields 'Network and I/O' 'Adapters' $null 'Get-NetAdapter and Win32_NetworkAdapter' 'not_exposed' $adapterNote
    } else {
        $count = 0
        foreach ($adapter in $fallback.Items) {
            $physicalAdapter = Get-Prop $adapter 'PhysicalAdapter'
            if ($null -eq $physicalAdapter -or -not [bool]$physicalAdapter) {
                continue
            }
            $count += 1
            $statusCode = Get-Prop $adapter 'NetConnectionStatus'
            $text = "name={0}; adapter_type={1}; status={2}" -f (Get-Prop $adapter 'Name'), (Get-Prop $adapter 'AdapterType'), (Get-MappedName $netStatus $statusCode)
            Add-ProfileField $fields 'Network and I/O' ("Adapter #{0}" -f $count) $text 'Win32_NetworkAdapter' '' 'Get-NetAdapter was not available. MACAddress, GUID, and PNPDeviceID are omitted.'
        }
        if ($count -eq 0) {
            Add-ProfileField $fields 'Network and I/O' 'Adapters' $null 'Win32_NetworkAdapter' 'not_exposed' $adapterNote
        }
    }
}
Add-ProfileField $fields 'Network and I/O' 'MAC address' $null 'not collected' 'omitted' 'MAC addresses are omitted.'
Add-ProfileField $fields 'Network and I/O' 'IP address' $null 'not collected' 'omitted' 'Private and public IP addresses are not collected.'

$video = Get-CimSafe -ClassName 'Win32_VideoController'
if (-not $video.Ok -or $video.Items.Count -eq 0) {
    $message = $video.Error
    if ([string]::IsNullOrEmpty($message)) { $message = 'no instances' }
    Add-ProfileField $fields 'Network and I/O' 'Display adapter' $null 'Win32_VideoController' 'not_exposed' $message
} else {
    $index = 0
    foreach ($card in $video.Items) {
        $index += 1
        $ram = Get-Prop $card 'AdapterRAM'
        $text = "name={0}; horizontal={1}; vertical={2}; adapter_ram={3}" -f (Get-Prop $card 'Name'), (Get-Prop $card 'CurrentHorizontalResolution'), (Get-Prop $card 'CurrentVerticalResolution'), (Format-Bytes $ram)
        Add-ProfileField $fields 'Network and I/O' ("Display adapter #{0}" -f $index) $text 'Win32_VideoController' '' 'AdapterRAM is a 32-bit property and is not always the GPU memory size. Report the returned number. PNPDeviceID is omitted.'
    }
}

$keyboard = Get-CimSafe -ClassName 'Win32_Keyboard'
if ($keyboard.Ok) {
    Add-ProfileField $fields 'Network and I/O' 'Keyboard count' ([string]$keyboard.Items.Count) 'Win32_Keyboard'
    if ($keyboard.Items.Count -gt 0) {
        Add-ProfileField $fields 'Network and I/O' 'Keyboard name' (Get-Prop $keyboard.Items[0] 'Name') 'Win32_Keyboard.Name'
    }
} else {
    Add-ProfileField $fields 'Network and I/O' 'Keyboard count' $null 'Win32_Keyboard' 'not_exposed' $keyboard.Error
}

$pointing = Get-CimSafe -ClassName 'Win32_PointingDevice'
if ($pointing.Ok) {
    Add-ProfileField $fields 'Network and I/O' 'Pointing device count' ([string]$pointing.Items.Count) 'Win32_PointingDevice'
    if ($pointing.Items.Count -gt 0) {
        Add-ProfileField $fields 'Network and I/O' 'Pointing device name' (Get-Prop $pointing.Items[0] 'Name') 'Win32_PointingDevice.Name'
    }
} else {
    Add-ProfileField $fields 'Network and I/O' 'Pointing device count' $null 'Win32_PointingDevice' 'not_exposed' $pointing.Error
}

$candidateText = ''
if ($candidates.Count -eq 0) {
    $candidateText = ''
} else {
    $candidateText = ($candidates.ToArray() -join "`n")
}

$result = [pscustomobject]@{
    generated_utc       = (Get-IsoTimestamp)
    powershell          = $PSVersionTable.PSVersion.ToString()
    fields              = $fields.ToArray()
    feature_candidates  = $candidateText
    errors              = ($(if ($errors.Count -eq 0) { '' } else { $errors.ToArray() -join "`n" }))
}

$rawDir = Join-Path $repo 'evidence\raw'
$jsonPath = Join-Path $rawDir ("m1-profile-{0}.json" -f $stamp)
$textPath = Join-Path $rawDir ("m1-profile-{0}.txt" -f $stamp)
$json = ConvertTo-JsonText -Object $result
Set-TextFile -Path $jsonPath -Content $json

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('Mission 1 device profile') | Out-Null
$lines.Add('generated_utc: ' + $result.generated_utc) | Out-Null
$lines.Add('Fields below are whitelisted. Serial numbers, MAC addresses, IP addresses, usernames, and the computer name were not requested.') | Out-Null
$lines.Add('') | Out-Null
foreach ($field in $fields) {
    $shown = $field.value
    if ($null -eq $shown) { $shown = '' }
    $lines.Add(('- {0} / {1}' -f $field.area, $field.name)) | Out-Null
    $lines.Add(('  status: {0}' -f $field.status)) | Out-Null
    $lines.Add(('  value: {0}' -f $shown)) | Out-Null
    $lines.Add(('  source: {0}' -f $field.source)) | Out-Null
    if (-not [string]::IsNullOrEmpty([string]$field.note)) {
        $lines.Add(('  note: {0}' -f $field.note)) | Out-Null
    }
}
if (-not [string]::IsNullOrEmpty($candidateText)) {
    $lines.Add('') | Out-Null
    $lines.Add('Observed facts you may choose from when you write the interpretation:') | Out-Null
    $lines.Add($candidateText) | Out-Null
}
$lines.Add('') | Out-Null
$lines.Add('The interpretation is not written here. Write it yourself in the report.') | Out-Null
Set-TextFile -Path $textPath -Content ($lines.ToArray() -join "`n")

Write-Host ("Mission 1 wrote {0}" -f $textPath)
Write-Output ([pscustomobject]@{
    Ok       = $true
    Stamp    = $stamp
    JsonPath = $jsonPath
    TextPath = $textPath
    Result   = $result
})
