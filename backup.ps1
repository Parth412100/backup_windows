param(
    [string]$BackupDir = "$PSScriptRoot",
    [switch]$IncludeWallpaper
)

$log = "$BackupDir\backup.log"
$manifestFile = "$BackupDir\manifest.txt"
$checkpointFile = "$BackupDir\.backup_checkpoint"

function Write-Log {
    param([string]$Message)
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message"
    Write-Host $line
    Add-Content -Path $log -Value $line
}

function Invoke-WithTimeout {
    param([scriptblock]$ScriptBlock, [int]$TimeoutSeconds, [string]$Label = "Command")
    $job = Start-Job -ScriptBlock $ScriptBlock
    $job | Wait-Job -Timeout $TimeoutSeconds | Out-Null
    if ($job.State -eq 'Running') {
        Stop-Job $job
        Write-Log "  TIMEOUT: $Label timed out after ${TimeoutSeconds}s, skipping"
        Write-Log "  TIP: Check your internet connection or run the step manually."
        return $null
    }
    $output = Receive-Job -Job $job -ErrorAction SilentlyContinue
    Remove-Job $job -ErrorAction SilentlyContinue
    $output
}

function Save-Checkpoint {
    param([string]$Step)
    $completed = @()
    if (Test-Path $checkpointFile) {
        $completed = Get-Content $checkpointFile
    }
    if ($completed -notcontains $Step) {
        $completed += $Step
        $completed | Out-File $checkpointFile -Encoding utf8
    }
}

function Test-Checkpoint {
    param([string]$Step)
    if (-not (Test-Path $checkpointFile)) { return $false }
    $completed = Get-Content $checkpointFile
    return $completed -contains $Step
}

function Clear-Checkpoints {
    if (Test-Path $checkpointFile) {
        Remove-Item $checkpointFile -Force
    }
}

# Clear old checkpoints at start of fresh backup
Clear-Checkpoints

$manifest = @"
Windows Config Backup - Manifest
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Computer: $env:COMPUTERNAME
User: $env:USERNAME
OS: $(Get-CimInstance Win32_OperatingSystem | Select-Object -ExpandProperty Caption)

This backup can be restored on a fresh Windows install using:
    restore.ps1

Backup includes configs/registry/packages below.
"@
$manifest | Out-File $manifestFile -Encoding utf8

Write-Log "=== WINDOWS CONFIG BACKUP ==="
Write-Log "Backup to: $BackupDir"

# ─── 1. SYSTEM INFO ───────────────────────────────────────────────
if (Test-Checkpoint "sysinfo") {
    Write-Log "[1/18] System info already saved, skipping"
} else {
    Write-Log "[1/18] Saving system info..."
    try {
        $osInfo = Get-CimInstance Win32_OperatingSystem | Select-Object Caption, Version, OSArchitecture
        @"
Hostname: $(hostname)
OS: $($osInfo.Caption) $($osInfo.Version) $($osInfo.OSArchitecture)
Logged-in User: $env:USERNAME@$env:USERDOMAIN
"@ | Out-File "$BackupDir\system_info.txt" -Encoding utf8
        Save-Checkpoint "sysinfo"
    } catch { Write-Log "  WARNING: System info failed: $($_.Exception.Message)" }
}

# ─── 2. POWERSHELL PROFILE ───────────────────────────────────────
if (Test-Checkpoint "psprofile") {
    Write-Log "[2/18] PowerShell profile already saved, skipping"
} else {
    Write-Log "[2/18] Saving PowerShell profile..."
    try {
        if (Test-Path $PROFILE.CurrentUserCurrentHost) {
            Copy-Item -Path $PROFILE.CurrentUserCurrentHost -Destination "$BackupDir\configs\powershell\profile.ps1" -Force
        }
        if (Test-Path $PROFILE.AllUsersCurrentHost) {
            Copy-Item -Path $PROFILE.AllUsersCurrentHost -Destination "$BackupDir\configs\powershell\profile_all_users.ps1" -Force
        }
        try { Get-InstalledModule | Select-Object Name, Version | Export-Csv "$BackupDir\configs\powershell\modules.csv" -NoTypeInformation } catch {}
        try { Get-PSRepository | Select-Object Name, SourceLocation, InstallationPolicy | Export-Csv "$BackupDir\configs\powershell\repositories.csv" -NoTypeInformation } catch {}
        Save-Checkpoint "psprofile"
    } catch { Write-Log "  WARNING: PowerShell profile backup failed: $($_.Exception.Message)" }
}

# ─── 3. WINDOWS TERMINAL ─────────────────────────────────────────
if (Test-Checkpoint "terminal") {
    Write-Log "[3/18] Windows Terminal settings already saved, skipping"
} else {
    Write-Log "[3/18] Saving Windows Terminal settings..."
    try {
        $termPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_*\LocalState\settings.json"
        $termFile = Get-ChildItem $termPath -ErrorAction SilentlyContinue
        if ($termFile) {
            Copy-Item -Path $termFile.FullName -Destination "$BackupDir\configs\terminal\settings.json" -Force
        }
        $termPrev = Get-ChildItem "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_*\LocalState\settings.json" -ErrorAction SilentlyContinue
        if ($termPrev) { Copy-Item -Path $termPrev.FullName -Destination "$BackupDir\configs\terminal\settings_preview.json" -Force }
        Save-Checkpoint "terminal"
    } catch { Write-Log "  WARNING: Terminal backup failed: $($_.Exception.Message)" }
}

# ─── 4. VS CODE ──────────────────────────────────────────────────
if (Test-Checkpoint "vscode") {
    Write-Log "[4/18] VS Code settings already saved, skipping"
} else {
    Write-Log "[4/18] Saving VS Code settings..."
    try {
        $vsc = "$env:APPDATA\Code\User"
        if (Test-Path "$vsc\settings.json") { Copy-Item "$vsc\settings.json" -Dest "$BackupDir\configs\vscode\settings.json" -Force }
        if (Test-Path "$vsc\keybindings.json") { Copy-Item "$vsc\keybindings.json" -Dest "$BackupDir\configs\vscode\keybindings.json" -Force }
        if (Test-Path "$vsc\snippets") { Copy-Item "$vsc\snippets\*" -Dest "$BackupDir\configs\vscode\snippets\" -Recurse -Force }
        try { $extOutput = Invoke-WithTimeout { code --list-extensions 2>$null } 30 "VS Code extensions"; if ($null -ne $extOutput) { $extOutput | Out-File "$BackupDir\configs\vscode\extensions.txt" -Encoding utf8 } } catch {}
        Save-Checkpoint "vscode"
    } catch { Write-Log "  WARNING: VS Code backup failed: $($_.Exception.Message)" }
}

# ─── 5. GIT ───────────────────────────────────────────────────────
if (Test-Checkpoint "git") {
    Write-Log "[5/18] Git config already saved, skipping"
} else {
    Write-Log "[5/18] Saving Git config..."
    try {
        if (Test-Path "$env:USERPROFILE\.gitconfig") { Copy-Item "$env:USERPROFILE\.gitconfig" -Dest "$BackupDir\configs\git\.gitconfig" -Force }
        if (Test-Path "$env:USERPROFILE\.gitignore_global") { Copy-Item "$env:USERPROFILE\.gitignore_global" -Dest "$BackupDir\configs\git\.gitignore_global" -Force }
        Save-Checkpoint "git"
    } catch { Write-Log "  WARNING: Git backup failed: $($_.Exception.Message)" }
}

# ─── 6. SSH CONFIG ────────────────────────────────────────────────
if (Test-Checkpoint "ssh") {
    Write-Log "[6/18] SSH config already saved, skipping"
} else {
    Write-Log "[6/18] Saving SSH config..."
    try {
        $sshDir = "$env:USERPROFILE\.ssh"
        if (Test-Path "$sshDir\config") { Copy-Item "$sshDir\config" -Dest "$BackupDir\configs\ssh\config" -Force }
        if (Test-Path "$sshDir\known_hosts") { Copy-Item "$sshDir\known_hosts" -Dest "$BackupDir\configs\ssh\known_hosts" -Force }
        Save-Checkpoint "ssh"
    } catch { Write-Log "  WARNING: SSH backup failed: $($_.Exception.Message)" }
}

# ─── 7. REGISTRY ──────────────────────────────────────────────────
if (Test-Checkpoint "registry") {
    Write-Log "[7/18] Registry already saved, skipping"
} else {
    Write-Log "[7/18] Saving registry settings..."
    $regHives = @(
        "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband"
        "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent"
        "HKCU\Control Panel\Desktop"
        "HKCU\Control Panel\Colors"
        "HKCU\Control Panel\Desktop\WindowMetrics"
        "HKCU\Software\Microsoft\Windows\CurrentVersion\Themes"
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
    $regCount = 0
    foreach ($key in $regHives) {
        try {
            $testKey = $key -replace '^HKCU\\', 'HKCU:\' -replace '^HKLM\\', 'HKLM:\'
            if (Test-Path $testKey) {
                $file = "$BackupDir\registry\$($key.Replace('\','_').Replace(':','')).reg"
                Invoke-WithTimeout { reg export "`"$key`"" "$file" /y 2>$null } 15 "reg export" | Out-Null
                $regCount++
            }
        } catch {}
    }
    Write-Log "  $regCount registry keys exported"
    Save-Checkpoint "registry"
}

# ─── 8. ENVIRONMENT VARIABLES ────────────────────────────────────
if (Test-Checkpoint "env") {
    Write-Log "[8/18] Environment variables already saved, skipping"
} else {
    Write-Log "[8/18] Saving environment variables..."
    try {
        Get-ChildItem Env: | Where-Object { $_.Name -notmatch '^(TEMP|TMP|Path|VSCODE_GIT_|OPENCODE_|CHROME_CRASHPAD_|SESSIONNAME)$' } |
            Select-Object Name, Value | Export-Csv "$BackupDir\env\user_env_vars.csv" -NoTypeInformation
        $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
        $sysPath  = [Environment]::GetEnvironmentVariable("Path", "Machine")
        $userPath -split ';' | Where-Object { $_ } | Out-File "$BackupDir\env\user_path.txt" -Encoding utf8
        $sysPath -split ';'  | Where-Object { $_ } | Out-File "$BackupDir\env\system_path.txt" -Encoding utf8
        Save-Checkpoint "env"
    } catch { Write-Log "  WARNING: Environment backup failed: $($_.Exception.Message)" }
}

# ─── 9. PACKAGES ─────────────────────────────────────────────────
if (Test-Checkpoint "packages") {
    Write-Log "[9/18] Package lists already exported, skipping"
} else {
    Write-Log "[9/18] Exporting package lists..."
    try {
        Invoke-WithTimeout { winget export -o "$BackupDir\packages\winget.json" --accept-source-agreements 2>$null } 120 "winget export" | Out-Null
        Write-Log "  winget export complete"
    } catch { Write-Log "  WARNING: winget export failed. TIP: Run: winget export -o packages\winget.json" }
    try { if (Get-Command choco -ErrorAction SilentlyContinue) { Invoke-WithTimeout { choco list -lo -r } 60 "choco list" | Out-File "$BackupDir\packages\chocolatey.txt" -Encoding utf8 } } catch {}
    try { if (Get-Command scoop -ErrorAction SilentlyContinue) { Invoke-WithTimeout { scoop export } 60 "scoop export" | Out-File "$BackupDir\packages\scoop.json" -Encoding utf8 } } catch {}

    try {
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
    } catch { Write-Log "  WARNING: Installed programs list failed" }

    # Match to winget IDs
    try {
        $existingIds = @()
        $wingetJsonPath = "$BackupDir\packages\winget.json"
        if (Test-Path $wingetJsonPath) {
            $wingetData = Get-Content $wingetJsonPath -Raw | ConvertFrom-Json
            $existingIds = $wingetData.Sources.Packages.PackageIdentifier
        }
        $knownMap = @{
            'qBittorrent' = 'qBittorrent.qBittorrent'; 'WinDirStat' = 'WinDirStat.WinDirStat'
            'Microsoft Edge' = 'Microsoft.Edge'; 'MSN Weather' = 'Microsoft.BingWeather'
            'Microsoft Clipchamp' = 'Microsoft.Clipchamp'; 'Windows Notepad' = 'Microsoft.WindowsNotepad'
            'Windows Camera' = 'Microsoft.WindowsCamera'; 'Microsoft Photos' = 'Microsoft.Windows.Photos'
            'Microsoft Sticky Notes' = 'Microsoft.MicrosoftStickyNotes'; 'Windows Clock' = 'Microsoft.WindowsAlarms'
            'Snipping Tool' = 'Microsoft.ScreenSketch'; 'Paint' = 'Microsoft.Paint'
            'Phone Link' = 'Microsoft.YourPhone'; 'PC Manager' = 'Microsoft.PCManager'
            'ChatGPT' = 'OpenAI.ChatGPT'; 'Discord' = 'Discord.Discord'
            'Mozilla Firefox' = 'Mozilla.Firefox'; 'Google Chrome' = 'Google.Chrome'
            '7-Zip' = '7zip.7zip'; 'PowerToys' = 'Microsoft.PowerToys'
            'Spotify' = 'Spotify.Spotify'; 'ShareX' = 'ShareX.ShareX'
            'OBS Studio' = 'OBSProject.OBSStudio'; 'Docker Desktop' = 'Docker.DockerDesktop'
            'Postman' = 'Postman.Postman'; 'Figma' = 'Figma.Figma'
            'Slack' = 'SlackTechnologies.Slack'; 'Zoom' = 'Zoom.Zoom'
            'Wireshark' = 'WiresharkFoundation.Wireshark'; 'ffmpeg' = 'FFmpeg.FFmpeg'
            'mpv' = 'mpv-player.mpv-CI.MSVC'; 'GIMP' = 'GIMP.GIMP'
            'Inkscape' = 'Inkscape.Inkscape'; 'Blender' = 'BlenderFoundation.Blender'
            'Audacity' = 'Audacity.Audacity'; 'VLC' = 'VideoLAN.VLC'
            'Everything' = 'voidtools.Everything'; 'Greenshot' = 'Greenshot.Greenshot'
            'CPU-Z' = 'CPUID.CPU-Z'; 'GPU-Z' = 'TechPowerUp.GPU-Z'
            'HWMonitor' = 'CPUID.HWMonitor'; 'Rufus' = 'Rufus.Rufus'
            'BalenaEtcher' = 'Balena.Etcher'; 'Adobe Acrobat' = 'Adobe.Acrobat.Reader.64-bit'
        }
        $wingetExtras = @(); $matchedIds = @{}; $manualOnly = @()
        foreach ($p in $progs) {
            $name = $p.Name.Trim(); $lowerName = $name.ToLower()
            $cleanName = $name -replace ' \(64-bit\)$| \(x64\)$| \(x86\)$| version .*$| \d+\.\d+.*$', ''
            $alreadyExported = $false
            foreach ($id in $existingIds) {
                $idSlug = $id.Split('.')[-1].ToLower()
                $nameFlat = $lowerName -replace '[^a-zA-Z0-9]', ''
                $idFlat = $idSlug -replace '[^a-zA-Z0-9]', ''
                if ($nameFlat -eq $idFlat -or $nameFlat -match [regex]::Escape($idFlat)) { $alreadyExported = $true; break }
            }
            if ($alreadyExported) { continue }
            if ($lowerName -match '^(nvidia |acer |nitrosense|microsoft visual (c|c\+\+|studio )|vs_|windows (sdk|app |advanced|security|package )|sql server|ue4 |ue |launcher prerequisites|mozilla maintenance|github lfs|entity framework|kits configuration|redlauncher|nvcpl|gdr \d+ for sql|one.?note|speech pack|intel|dts |cross device|android |play store|google$|google (partner|play )|photopea|youtube|drive$|linkedin$|whatsapp$|epub|pptx|ePub File)') { $manualOnly += $name; continue }
            if ($lowerName -match '^python \d.*(core interpreter|add to path|development|libraries|documentation|executables|pip bootstrap|standard library|tcl|test suite|utility)') { continue }
            $cleanLower = $cleanName.ToLower()
            if ($cleanLower -match '^python \d+\.\d+\.\d+$') {
                $ver = ($cleanName -split ' ')[1]; $major = ($ver -split '\.')[0]; $id = "Python.Python.$major"
                if (-not $matchedIds.ContainsKey($id)) { $matchedIds[$id] = $true; $wingetExtras += $id; Write-Log "  Matched: $cleanName -> $id" }
                continue
            }
            $found = $false
            foreach ($key in $knownMap.Keys) {
                if ($cleanName -match [regex]::Escape($key) -or $key -match [regex]::Escape($cleanName)) {
                    $id = $knownMap[$key]
                    if (-not $matchedIds.ContainsKey($id)) { $matchedIds[$id] = $true; $wingetExtras += $id; Write-Log "  Matched: $cleanName -> $id"; $found = $true; break }
                }
            }
            if ($found) { continue }
            try {
                $searchResult = Invoke-WithTimeout { winget search --name "`"$cleanName`"" --exact --accept-source-agreements 2>$null } 30 "winget search: $cleanName"
                if ($null -ne $searchResult -and $searchResult -match [regex]::Escape($cleanName)) {
                    $lines = $searchResult -split "`n" | Where-Object { $_ -match '\S' }
                    if ($lines.Count -ge 3) {
                        $headerLine = $lines[1]; $idStart = $headerLine.IndexOf('Id'); $firstResult = $lines[2]
                        if ($idStart -ge 0 -and $firstResult.Length -gt $idStart) {
                            $foundId = $firstResult.Substring($idStart).Trim().Split(' ')[0]
                            if ($foundId -and $foundId.Contains('.')) {
                                if (-not $matchedIds.ContainsKey($foundId)) { $matchedIds[$foundId] = $true; $wingetExtras += $foundId; Write-Log "  Matched: $cleanName -> $foundId"; $found = $true }
                            }
                        }
                    }
                }
            } catch {}
            if (-not $found) { $manualOnly += $name }
        }
        if ($wingetExtras.Count -gt 0) {
            $extrasJson = @{
                '$schema' = 'https://aka.ms/winget-packages.schema.2.0.json'
                CreationDate = (Get-Date).ToUniversalTime().ToString('o')
                Sources = @(@{
                    Packages = $wingetExtras | ForEach-Object { @{PackageIdentifier = $_} }
                    SourceDetails = @{ Argument = 'https://cdn.winget.microsoft.com/cache'; Identifier = 'Microsoft.Winget.Source_8wekyb3d8bbwe'; Name = 'winget'; Type = 'Microsoft.PreIndexed.Package' }
                })
                WinGetVersion = '1.28.240'
            }
            $extrasJson | ConvertTo-Json -Depth 4 | Out-File "$BackupDir\packages\winget_extras.json" -Encoding utf8
            Write-Log "  $($wingetExtras.Count) additional winget IDs matched"
        }
        if ($manualOnly.Count -gt 0) {
            @"
MANUAL INSTALL CHECKLIST
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Computer: $env:COMPUTERNAME

These programs could not be automatically matched to a winget ID.
Install them manually after restore.

$($manualOnly | Sort-Object | ForEach-Object { "- $_" } | Out-String)
"@ | Out-File "$BackupDir\packages\manual_install.txt" -Encoding utf8
            Write-Log "  $($manualOnly.Count) programs need manual install (see packages\manual_install.txt)"
        }
    } catch { Write-Log "  Winget matching skipped: $($_.Exception.Message)" }

    try { Get-WindowsOptionalFeature -Online | Where-Object State -eq Enabled | Select-Object FeatureName, State |
        Export-Csv "$BackupDir\packages\windows_features.csv" -NoTypeInformation } catch {}
    Save-Checkpoint "packages"
}

# ─── 10. STARTUP PROGRAMS ─────────────────────────────────────────
if (Test-Checkpoint "startup") {
    Write-Log "[10/18] Startup programs already saved, skipping"
} else {
    Write-Log "[10/18] Saving startup programs..."
    try {
        $startupItem = Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -ErrorAction SilentlyContinue
        if ($startupItem -and $startupItem.PSObject.Properties) {
            $startupItem.PSObject.Properties |
                Where-Object { $_.MemberType -eq 'NoteProperty' -and $_.Name -notmatch '^PS[A-Z]' } |
                Select-Object @{N='Name';E={$_.Name}}, @{N='Command';E={$_.Value}} |
                Export-Csv "$BackupDir\configs\startup.csv" -NoTypeInformation
        }
        Save-Checkpoint "startup"
    } catch { Write-Log "  WARNING: Startup backup failed" }
}

# ─── 11. SCHEDULED TASKS ─────────────────────────────────────────
if (Test-Checkpoint "tasks") {
    Write-Log "[11/18] Scheduled tasks already saved, skipping"
} else {
    Write-Log "[11/18] Saving scheduled tasks..."
    try {
        Get-ScheduledTask | Where-Object { $_.TaskPath -notmatch '^\\Microsoft\\' } |
            Select-Object TaskName, TaskPath, State, Description |
            Export-Csv "$BackupDir\scheduled_tasks\user_tasks.csv" -NoTypeInformation
        Save-Checkpoint "tasks"
    } catch { Write-Log "  WARNING: Scheduled tasks backup failed" }
}

# ─── 12. POWER SCHEME ────────────────────────────────────────────
if (Test-Checkpoint "power") {
    Write-Log "[12/18] Power scheme already saved, skipping"
} else {
    Write-Log "[12/18] Saving power scheme..."
    try {
        Invoke-WithTimeout { powercfg /query 2>$null } 15 "powercfg /query" | Out-File "$BackupDir\configs\power_settings.txt" -Encoding utf8
        Invoke-WithTimeout { powercfg /getactivescheme 2>$null } 10 "powercfg /getactivescheme" | Out-File "$BackupDir\configs\active_power_scheme.txt" -Encoding utf8
        Save-Checkpoint "power"
    } catch { Write-Log "  WARNING: Power scheme backup failed" }
}

# ─── 13. THEME / COLOR / DARK MODE ──────────────────────────────
if (Test-Checkpoint "theme") {
    Write-Log "[13/18] Theme settings already saved, skipping"
} else {
    Write-Log "[13/18] Saving theme settings..."
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
        $palette = (Get-ItemProperty "$a" -Name AccentPalette -ErrorAction SilentlyContinue).AccentPalette
        if ($palette) { $palette -join ',' | Out-File "$BackupDir\configs\accent_palette.txt" -Encoding ascii }
        $wmData = Get-ItemProperty "HKCU:\Control Panel\Desktop\WindowMetrics" -ErrorAction SilentlyContinue
        if ($wmData -and $wmData.PSObject.Properties) {
            $wmData.PSObject.Properties | Where-Object { $_.MemberType -eq 'NoteProperty' -and $_.Name -notmatch '^PS[A-Z]' } |
                Select-Object @{N='Name';E={$_.Name}}, @{N='Value';E={$_.Value}} |
                Export-Csv "$BackupDir\configs\window_metrics.csv" -NoTypeInformation
        }
        Save-Checkpoint "theme"
    } catch { Write-Log "  WARNING: Theme backup failed: $($_.Exception.Message)" }
}

# ─── 14. WALLPAPER (optional) ─────────────────────────────────────
if (Test-Checkpoint "wallpaper") {
    Write-Log "[14/18] Wallpaper already saved, skipping"
} else {
    Write-Log "[14/18] Saving wallpaper..."
    try {
        if ($IncludeWallpaper) {
            $wp = (Get-ItemProperty "HKCU:\Control Panel\Desktop" -Name WallPaper -ErrorAction SilentlyContinue).WallPaper
            if ($wp -and (Test-Path $wp)) {
                $ext = [System.IO.Path]::GetExtension($wp)
                $size = (Get-Item $wp).Length
                if ($size -lt 5MB) {
                    Copy-Item -Path $wp -Destination "$BackupDir\configs\wallpaper$ext" -Force
                    Write-Log "  Wallpaper saved ($('{0:N1}' -f ($size/1MB)) MB)"
                } else { Write-Log "  Wallpaper too large, saving path only" }
            }
        } else {
            $wp = (Get-ItemProperty "HKCU:\Control Panel\Desktop" -Name WallPaper -ErrorAction SilentlyContinue).WallPaper
            if ($wp) { "WallpaperPath=$wp" | Out-File "$BackupDir\configs\wallpaper_path.txt" -Encoding utf8 }
        }
        Save-Checkpoint "wallpaper"
    } catch { Write-Log "  WARNING: Wallpaper backup failed" }
}

# ─── 15. FONTS LIST ──────────────────────────────────────────────
if (Test-Checkpoint "fonts") {
    Write-Log "[15/18] Fonts list already saved, skipping"
} else {
    Write-Log "[15/18] Saving fonts list..."
    try {
        $fontData = Get-ItemProperty "HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Fonts" -ErrorAction SilentlyContinue
        if ($fontData -and $fontData.PSObject.Properties) {
            $fontData.PSObject.Properties |
                Where-Object { $_.MemberType -eq 'NoteProperty' -and $_.Name -notmatch '^PS[A-Z]' } |
                Select-Object @{N='FontName';E={$_.Name}}, @{N='FontFile';E={$_.Value}} |
                Export-Csv "$BackupDir\configs\fonts.csv" -NoTypeInformation
        }
        Save-Checkpoint "fonts"
    } catch { Write-Log "  WARNING: Fonts backup failed" }
}

# ─── 16. DEFENDER EXCLUSIONS ─────────────────────────────────────
if (Test-Checkpoint "defender") {
    Write-Log "[16/18] Defender exclusions already saved, skipping"
} else {
    Write-Log "[16/18] Saving Defender exclusions..."
    try {
        $mpPref = Get-MpPreference -ErrorAction SilentlyContinue
        if ($mpPref) {
            $exclusions = @()
            foreach ($path in $mpPref.ExclusionPath) { $exclusions += [PSCustomObject]@{Type='Path';Value=$path} }
            foreach ($ext in $mpPref.ExclusionExtension) { $exclusions += [PSCustomObject]@{Type='Extension';Value=$ext} }
            foreach ($proc in $mpPref.ExclusionProcess) { $exclusions += [PSCustomObject]@{Type='Process';Value=$proc} }
            $exclusions | Export-Csv "$BackupDir\configs\defender_exclusions.csv" -NoTypeInformation
        }
        Save-Checkpoint "defender"
    } catch { Write-Log "  WARNING: Defender backup failed" }
}

# ─── 17. HOSTS FILE ──────────────────────────────────────────────
if (Test-Checkpoint "hosts") {
    Write-Log "[17/18] Hosts file already saved, skipping"
} else {
    Write-Log "[17/18] Saving hosts file..."
    try {
        $hosts = "$env:windir\System32\drivers\etc\hosts"
        if (Test-Path $hosts) { Copy-Item $hosts -Dest "$BackupDir\configs\hosts.backup" -Force }
        Save-Checkpoint "hosts"
    } catch { Write-Log "  WARNING: Hosts backup failed" }
}

# ─── 18. TASKBAR ─────────────────────────────────────────────────
if (Test-Checkpoint "taskbar") {
    Write-Log "[18/18] Taskbar settings already saved, skipping"
} else {
    Write-Log "[18/18] Saving taskbar settings..."
    try {
        $e = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        $taskbarSettings = @{}
        @('TaskbarSi', 'TaskbarAl', 'ShowTaskViewButton', 'ShowCopilotButton', 'TaskbarMn', 'TaskbarDa') | ForEach-Object {
            $val = (Get-ItemProperty "$e" -Name $_ -ErrorAction SilentlyContinue).$_
            if ($null -ne $val) { $taskbarSettings[$_] = $val }
        }
        $taskbarSettings | ConvertTo-Json | Out-File "$BackupDir\configs\taskbar_settings.json" -Encoding utf8
        Save-Checkpoint "taskbar"
    } catch { Write-Log "  WARNING: Taskbar backup failed" }
}

# ─── SUMMARY ──────────────────────────────────────────────────────
Clear-Checkpoints
$size = (Get-ChildItem -Recurse $BackupDir -File | Measure-Object -Property Length -Sum).Sum
Write-Log "=== BACKUP COMPLETE ==="
Write-Log "Size: $('{0:N2}' -f ($size/1MB)) MB (no photos/videos included)"
Write-Log "Manifest: $manifestFile"
Write-Log ""
Write-Log "On a FRESH WINDOWS INSTALL, copy this folder and run:"
Write-Log "    PowerShell -ExecutionPolicy Bypass -File restore.ps1"
