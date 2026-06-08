param(
    [string]$RestorePointDir = "$PSScriptRoot\restore_points"
)

$ts = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$snapDir = "$RestorePointDir\snapshot_$ts"
New-Item -ItemType Directory -Path $snapDir -Force | Out-Null

Write-Host "Creating restore point snapshot at: $snapDir"

$regRoots = @(
    'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer'
    'HKCU\Control Panel\Desktop'
    'HKCU\Control Panel\Colors'
    'HKCU\Control Panel\Mouse'
    'HKCU\Control Panel\Keyboard'
    'HKCU\Software\Microsoft\Windows\CurrentVersion\Themes'
    'HKCU\Software\Microsoft\Windows\CurrentVersion\Search'
    'HKCU\Software\Microsoft\Windows\CurrentVersion\Start'
    'HKCU\Software\Microsoft\Windows\CurrentVersion\Notifications'
    'HKCU\Software\Microsoft\Windows\CurrentVersion\Privacy'
    'HKCU\Software\Microsoft\Windows\CurrentVersion\Run'
)

foreach ($key in $regRoots) {
    $file = "$snapDir\$($key.Replace('\','_').Replace(':','')).reg"
    try {
        reg export "$key" "$file" /y 2>$null | Out-Null
        Write-Host "  Exported: $key"
    } catch {
        Write-Host "  Skipped: $key (not found)"
    }
}

# Environment variables
Get-ChildItem Env: | Select-Object Name, Value | Export-Csv "$snapDir\env_vars_snapshot.csv" -NoTypeInformation

# Top processes
Get-Process | Select-Object Name, CPU, WorkingSet64, StartTime |
    Sort-Object WorkingSet64 -Descending | Select-Object -First 50 |
    Export-Csv "$snapDir\processes_top50.csv" -NoTypeInformation

# Running services
Get-Service | Where-Object { $_.Status -eq 'Running' } |
    Select-Object Name, DisplayName, StartType |
    Export-Csv "$snapDir\running_services.csv" -NoTypeInformation

# Network config
ipconfig /all | Out-File "$snapDir\network_config.txt" -Encoding utf8

# Disk info
Get-PSDrive -PSProvider FileSystem | Select-Object Name, Root, Used, Free |
    Export-Csv "$snapDir\disk_info.csv" -NoTypeInformation

# Snapshot metadata
$osInfo = Get-CimInstance Win32_OperatingSystem
$meta = @"
RESTORE POINT SNAPSHOT
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Computer: $env:COMPUTERNAME
User: $env:USERNAME
OS: $($osInfo.Caption)
Build: $($osInfo.Version)

This snapshot captures the system state BEFORE any restore operation.
It can be used to revert back if needed.

Contents:
- Registry exports (Explorer, Desktop, Themes, Search, Start, Notifications, Privacy, Run)
- Environment variables
- Top 50 running processes by memory
- Running services list
- Network configuration (ipconfig /all)
- Disk information
"@
$meta | Out-File "$snapDir\README.txt" -Encoding utf8

$count = (Get-ChildItem $snapDir -File).Count
Write-Host "Restore point created: $snapDir ($count files)"
Write-Host ""
