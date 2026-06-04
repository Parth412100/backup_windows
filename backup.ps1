param(
    [string]$BackupDir = "$PSScriptRoot",
    [switch]$IncludeWallpaper
)

$log = "$BackupDir\backup.log"
$manifestFile = "$BackupDir\manifest.txt"

function Write-Log {
    param([string]$Message)
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message"
    Write-Host $line
    Add-Content -Path $log -Value $line
}

@"
Windows Config Backup - Manifest
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Computer: $env:COMPUTERNAME
User: $env:USERNAME
OS: $(Get-CimInstance Win32_OperatingSystem | Select-Object -ExpandProperty Caption)

This backup can be restored on a fresh Windows install using:
    restore.ps1

Backup includes configs/registry/packages below.
"@ | Out-File $manifestFile -Encoding utf8

Write-Log "=== WINDOWS CONFIG BACKUP ==="
Write-Log "Backup to: $BackupDir"

# ─── 1. SYSTEM INFO ───────────────────────────────────────────────
@"
Hostname: $(hostname)
OS: $(Get-CimInstance Win32_OperatingSystem | Select-Object Caption, Version, OSArchitecture | Out-String).Trim()
Logged-in User: $env:USERNAME@$env:USERDOMAIN
"@ | Out-File "$BackupDir\system_info.txt" -Encoding utf8

# ─── 2. POWERSHELL PROFILE ───────────────────────────────────────
if (Test-Path $PROFILE.CurrentUserCurrentHost) {
    Copy-Item -Path $PROFILE.CurrentUserCurrentHost -Destination "$BackupDir\configs\powershell\profile.ps1" -Force
}
if (Test-Path $PROFILE.AllUsersCurrentHost) {
    Copy-Item -Path $PROFILE.AllUsersCurrentHost -Destination "$BackupDir\configs\powershell\profile_all_users.ps1" -Force
}
Get-InstalledModule | Select-Object Name, Version | Export-Csv "$BackupDir\configs\powershell\modules.csv" -NoTypeInformation
Get-PSRepository | Select-Object Name, SourceLocation, InstallationPolicy | Export-Csv "$BackupDir\configs\powershell\repositories.csv" -NoTypeInformation

# ─── 3. WINDOWS TERMINAL ─────────────────────────────────────────
$termPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_*\LocalState\settings.json"
$termFile = Get-ChildItem $termPath -ErrorAction SilentlyContinue
if ($termFile) {
    Copy-Item -Path $termFile.FullName -Destination "$BackupDir\configs\terminal\settings.json" -Force
}
# Windows Terminal Preview
$termPrev = Get-ChildItem "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_*\LocalState\settings.json" -ErrorAction SilentlyContinue
if ($termPrev) { Copy-Item -Path $termPrev.FullName -Destination "$BackupDir\configs\terminal\settings_preview.json" -Force }

# ─── 4. VS CODE ──────────────────────────────────────────────────
$vsc = "$env:APPDATA\Code\User"
if (Test-Path "$vsc\settings.json") { Copy-Item "$vsc\settings.json" -Dest "$BackupDir\configs\vscode\settings.json" -Force }
if (Test-Path "$vsc\keybindings.json") { Copy-Item "$vsc\keybindings.json" -Dest "$BackupDir\configs\vscode\keybindings.json" -Force }
if (Test-Path "$vsc\snippets") { Copy-Item "$vsc\snippets\*" -Dest "$BackupDir\configs\vscode\snippets\" -Recurse -Force }
try { code --list-extensions 2>$null | Out-File "$BackupDir\configs\vscode\extensions.txt" -Encoding utf8 } catch {}

# ─── 5. GIT ───────────────────────────────────────────────────────
if (Test-Path "$env:USERPROFILE\.gitconfig") { Copy-Item "$env:USERPROFILE\.gitconfig" -Dest "$BackupDir\configs\git\.gitconfig" -Force }
if (Test-Path "$env:USERPROFILE\.gitignore_global") { Copy-Item "$env:USERPROFILE\.gitignore_global" -Dest "$BackupDir\configs\git\.gitignore_global" -Force }

# ─── 6. SSH CONFIG ────────────────────────────────────────────────
$sshDir = "$env:USERPROFILE\.ssh"
if (Test-Path "$sshDir\config") { Copy-Item "$sshDir\config" -Dest "$BackupDir\configs\ssh\config" -Force }
if (Test-Path "$sshDir\known_hosts") { Copy-Item "$sshDir\known_hosts" -Dest "$BackupDir\configs\ssh\known_hosts" -Force }

# ─── 7. REGISTRY (EXPLORER / TASKBAR / THEMES / CONTEXT MENU / ETC) ──
$regHives = @(
    "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband"
    "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects2"
    "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent"
    "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\People"
    "HKCU\Software\Microsoft\Windows\CurrentVersion\FileExplorer"
    "HKCU\Control Panel\Desktop"
    "HKCU\Control Panel\Colors"
    "HKCU\Control Panel\Desktop\WindowMetrics"
    "HKCU\Software\Microsoft\Windows\CurrentVersion\Themes"
    "HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
    "HKCU\Software\Microsoft\Windows\CurrentVersion\ThemeManager"
    "HKCU\Software\Microsoft\Windows\CurrentVersion\Search"
    "HKCU\Software\Microsoft\Windows\CurrentVersion\Start"
    "HKCU\Software\Classes\*\shell"
    "HKCU\Software\Classes\Directory\Background\shell"
    "HKCU\Software\Classes\Drive\shell"
    "HKCU\Control Panel\Mouse"
    "HKCU\Control Panel\Keyboard"
    "HKCU\Software\Microsoft\Windows\CurrentVersion\Notifications"
    "HKCU\Software\Microsoft\Windows\CurrentVersion\Privacy"
)

foreach ($key in $regHives) {
    try {
        $testKey = $key -replace '^HKCU\\', 'HKCU:\' -replace '^HKLM\\', 'HKLM:\'
        if (Test-Path $testKey) {
            $file = "$BackupDir\registry\$($key.Replace('\','_').Replace(':','')).reg"
            reg export "`"$key`"" "$file" /y 2>$null
        }
    } catch {}
}

# ─── 8. ENVIRONMENT VARIABLES ────────────────────────────────────
Get-ChildItem Env: | Where-Object { $_.Name -notmatch '^(TEMP|TMP|Path)$' } |
    Select-Object Name, Value | Export-Csv "$BackupDir\env\user_env_vars.csv" -NoTypeInformation

$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
$sysPath  = [Environment]::GetEnvironmentVariable("Path", "Machine")
$userPath -split ';' | Where-Object { $_ } | Out-File "$BackupDir\env\user_path.txt" -Encoding utf8
$sysPath -split ';'  | Where-Object { $_ } | Out-File "$BackupDir\env\system_path.txt" -Encoding utf8

# ─── 9. PACKAGES ─────────────────────────────────────────────────
Write-Log "Exporting package lists..."

# winget
try { winget export -o "$BackupDir\packages\winget.json" --accept-source-agreements 2>$null } catch {}
# chocolatey
try { if (Get-Command choco -ErrorAction SilentlyContinue) { choco list -lo -r | Out-File "$BackupDir\packages\chocolatey.txt" -Encoding utf8 } } catch {}
# scoop
try { if (Get-Command scoop -ErrorAction SilentlyContinue) { scoop export | Out-File "$BackupDir\packages\scoop.json" -Encoding utf8 } } catch {}

# Installed programs (from registry uninstall keys)
$progs = @()
foreach ($path in @("HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
                    "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
                    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*")) {
    $progs += Get-ItemProperty $path -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -and $_.DisplayName -notmatch 'Update for|Security Update|Hotfix|KB\d+' } |
        Select-Object @{N='Name';E={$_.DisplayName}},
                      @{N='Version';E={$_.DisplayVersion}},
                      @{N='Publisher';E={$_.Publisher}},
                      @{N='UninstallString';E={$_.UninstallString}}
}
$progs | Sort-Object Name | Export-Csv "$BackupDir\packages\installed_programs.csv" -NoTypeInformation

# Windows Features
try { Get-WindowsOptionalFeature -Online | Where-Object State -eq Enabled | Select-Object FeatureName, State |
    Export-Csv "$BackupDir\packages\windows_features.csv" -NoTypeInformation } catch {}

# ─── 10. STARTUP PROGRAMS ─────────────────────────────────────────
$startupItem = Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -ErrorAction SilentlyContinue
if ($startupItem -and $startupItem.PSObject.Properties) {
    $startupItem.PSObject.Properties |
        Where-Object { $_.MemberType -eq 'NoteProperty' } |
        Select-Object @{N='Name';E={$_.Name}}, @{N='Command';E={$_.Value}} |
        Export-Csv "$BackupDir\configs\startup.csv" -NoTypeInformation
}

# ─── 11. SCHEDULED TASKS ─────────────────────────────────────────
try {
    Get-ScheduledTask | Where-Object { $_.TaskPath -notmatch '^\\Microsoft\\' } |
        Select-Object TaskName, TaskPath, State, Description |
        Export-Csv "$BackupDir\scheduled_tasks\user_tasks.csv" -NoTypeInformation
} catch {}

# ─── 12. POWER SCHEME ────────────────────────────────────────────
try {
    powercfg /query > "$BackupDir\configs\power_settings.txt" 2>$null
    powercfg /getactivescheme | Out-File "$BackupDir\configs\active_power_scheme.txt" -Encoding utf8
} catch {}

# ─── 13. THEME / COLOR / DARK MODE ──────────────────────────────
try {
    $p = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
    @"
AppsUseLightTheme=$(try {(Get-ItemProperty "$p" -Name AppsUseLightTheme).AppsUseLightTheme} catch {''})
SystemUsesLightTheme=$(try {(Get-ItemProperty "$p" -Name SystemUsesLightTheme).SystemUsesLightTheme} catch {''})
ColorPrevalence=$(try {(Get-ItemProperty "$p" -Name ColorPrevalence).ColorPrevalence} catch {''})
"@ | Out-File "$BackupDir\configs\theme.txt" -Encoding utf8

    $a = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent"
    $accent = (Get-ItemProperty "$a" -Name AccentColorMenu -ErrorAction SilentlyContinue).AccentColorMenu
    if ($accent) { "AccentColorMenu=$accent" | Out-File "$BackupDir\configs\accent_color.txt" -Encoding utf8 }

    # Also save the accent color palette
    $palette = (Get-ItemProperty "$a" -Name AccentPalette -ErrorAction SilentlyContinue).AccentPalette
    if ($palette) {
        $palette -join ',' | Out-File "$BackupDir\configs\accent_palette.txt" -Encoding ascii
    }

    # WindowMetrics (border width, title bar height etc)
    $wmData = Get-ItemProperty "HKCU:\Control Panel\Desktop\WindowMetrics" -ErrorAction SilentlyContinue
    if ($wmData -and $wmData.PSObject.Properties) {
        $wmData.PSObject.Properties |
            Where-Object { $_.MemberType -eq 'NoteProperty' } |
            Select-Object @{N='Name';E={$_.Name}}, @{N='Value';E={$_.Value}} |
            Export-Csv "$BackupDir\configs\window_metrics.csv" -NoTypeInformation
    }
} catch {}

# ─── 14. WALLPAPER (optional) ─────────────────────────────────────
if ($IncludeWallpaper) {
    try {
        $wp = (Get-ItemProperty "HKCU:\Control Panel\Desktop" -Name WallPaper -ErrorAction SilentlyContinue).WallPaper
        if ($wp -and (Test-Path $wp)) {
            $ext = [System.IO.Path]::GetExtension($wp)
            $size = (Get-Item $wp).Length
            if ($size -lt 5MB) {
                Copy-Item -Path $wp -Destination "$BackupDir\configs\wallpaper$ext" -Force
                Write-Log "  Wallpaper saved ($('{0:N1}' -f ($size/1MB)) MB)"
            } else {
                Write-Log "  Wallpaper too large ($('{0:N1}' -f ($size/1MB)) MB), skipping"
            }
        }
    } catch {}
} else {
    # Save wallpaper path as reference
    try {
        $wp = (Get-ItemProperty "HKCU:\Control Panel\Desktop" -Name WallPaper -ErrorAction SilentlyContinue).WallPaper
        if ($wp) { "WallpaperPath=$wp" | Out-File "$BackupDir\configs\wallpaper_path.txt" -Encoding utf8 }
    } catch {}
}

# ─── 15. FONTS LIST ──────────────────────────────────────────────
try {
    $fontData = Get-ItemProperty "HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Fonts" -ErrorAction SilentlyContinue
    if ($fontData -and $fontData.PSObject.Properties) {
        $fontData.PSObject.Properties |
            Where-Object { $_.MemberType -eq 'NoteProperty' } |
            Select-Object @{N='FontName';E={$_.Name}}, @{N='FontFile';E={$_.Value}} |
            Export-Csv "$BackupDir\configs\fonts.csv" -NoTypeInformation
    }
} catch {}

# ─── 16. DEFENDER EXCLUSIONS ─────────────────────────────────────
try {
    Get-MpPreference | Select-Object ExclusionPath, ExclusionExtension, ExclusionProcess |
        Export-Csv "$BackupDir\configs\defender_exclusions.csv" -NoTypeInformation
} catch {}

# ─── 17. HOSTS FILE ──────────────────────────────────────────────
$hosts = "$env:windir\System32\drivers\etc\hosts"
if (Test-Path $hosts) { Copy-Item $hosts -Dest "$BackupDir\configs\hosts.backup" -Force }

# ─── 18. TASKBAR / EXPLORER MISC ────────────────────────────────
# Save taskbar icon sizes and other settings
try {
    $e = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    $taskbarSettings = @{}
    @('TaskbarSi', 'TaskbarAl', 'ShowTaskViewButton', 'ShowCopilotButton', 'TaskbarMn', 'TaskbarDa') | ForEach-Object {
        $val = (Get-ItemProperty "$e" -Name $_ -ErrorAction SilentlyContinue).$_
        if ($null -ne $val) { $taskbarSettings[$_] = $val }
    }
    $taskbarSettings | Export-CliXml "$BackupDir\configs\taskbar_settings.xml"
} catch {}

# ─── SUMMARY ──────────────────────────────────────────────────────
$size = (Get-ChildItem -Recurse $BackupDir -File | Measure-Object -Property Length -Sum).Sum
Write-Log "=== BACKUP COMPLETE ==="
Write-Log "Size: $('{0:N2}' -f ($size/1MB)) MB (no photos/videos included)"
Write-Log "Manifest: $manifestFile"
Write-Log ""
Write-Log "On a FRESH WINDOWS INSTALL, copy this folder and run:"
Write-Log "    PowerShell -ExecutionPolicy Bypass -File restore.ps1"
