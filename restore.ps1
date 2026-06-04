param(
    [string]$BackupDir = "$PSScriptRoot",
    [switch]$DryRun,
    [switch]$Silent
)

$log = "$BackupDir\restore.log"

function Write-Log {
    param([string]$Message)
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message"
    if (-not $Silent) { Write-Host $line }
    Add-Content -Path $log -Value $line
}

function Ensure-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = [Security.Principal.WindowsPrincipal]$id
    if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        if (-not $DryRun) {
            Write-Host "Elevating to Administrator..."
            Start-Process powershell -Verb RunAs -ArgumentList @(
                "-ExecutionPolicy Bypass",
                "-NoProfile",
                "-File `"$($MyInvocation.MyCommand.Path)`"",
                "-BackupDir `"$BackupDir`"",
                $(if ($Silent) { "-Silent" }),
                $(if ($DryRun) { "-DryRun" })
            ) -Wait
            exit
        }
    }
}

function Test-File {
    param([string]$Path)
    return (Test-Path $Path) -and ((Get-Item $Path).Length -gt 0)
}

# ─── ELEVATE ──────────────────────────────────────────────────────
if (-not $DryRun) { Ensure-Admin }

Write-Log "========================================================"
Write-Log "  WINDOWS RESTORE - Fresh Install Setup"
Write-Log "  Backup: $BackupDir"
Write-Log "========================================================"
if ($DryRun) { Write-Log "  *** DRY RUN - no changes applied ***" }

# ══════════════════════════════════════════════════════════════════
# STEP 0: INSTALL PACKAGE MANAGERS
# ══════════════════════════════════════════════════════════════════
Write-Log "`n[0/8] Ensuring package managers are installed..."

# winget comes with Windows 10 1809+ / Windows 11
$wingetAvailable = $null -ne (Get-Command winget -ErrorAction SilentlyContinue)
if (-not $wingetAvailable -and -not $DryRun) {
    Write-Log "  winget not found. Installing App Installer from store..."
    try {
        $url = "https://www.nuget.org/api/v2/package/Microsoft.UI.Xaml/2.8.6"
        $tmp = "$env:TEMP\winrt.zip"
        # Try installing via Microsoft Store or download
        Start-Process "ms-windows-store://pdp/?productid=9NBLGGH4NNS1" -Wait
        Write-Log "  Please install App Installer from the store that opened."
        Write-Log "  After install, re-run this script."
    } catch { Write-Log "  Could not install winget automatically." }
}

if ($DryRun) { Write-Log "  [DRY RUN] Would install: winget, chocolatey (optional)" }

# ══════════════════════════════════════════════════════════════════
# STEP 1: RESTORE CONFIG FILES
# ══════════════════════════════════════════════════════════════════
Write-Log "`n[1/8] Restoring config files..."

# PowerShell profile
$p = "$BackupDir\configs\powershell\profile.ps1"
if (Test-File $p) {
    $dest = $PROFILE.CurrentUserCurrentHost
    $parent = Split-Path $dest -Parent
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    if (-not $DryRun) { Copy-Item $p -Dest $dest -Force; Write-Log "  PowerShell profile restored" }
    else { Write-Log "  [DRY RUN] Copy $p -> $dest" }
}

# Windows Terminal
$p = "$BackupDir\configs\terminal\settings.json"
if (Test-File $p) {
    $dirs = Get-ChildItem "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_*\LocalState" -ErrorAction SilentlyContinue
    if (-not $dirs -and $DryRun) {
        Write-Log "  [DRY RUN] Would restore terminal settings after Terminal is installed"
    }
    foreach ($d in $dirs) {
        if (-not $DryRun) { Copy-Item $p -Dest "$($d.FullName)\settings.json" -Force; Write-Log "  Terminal settings restored" }
        else { Write-Log "  [DRY RUN] Copy $p -> $($d.FullName)" }
    }
}

# VS Code
$vc = "$env:APPDATA\Code\User"
if (-not (Test-Path $vc)) { New-Item -ItemType Directory -Path $vc -Force | Out-Null }
$vsFiles = @(
    @{Src="$BackupDir\configs\vscode\settings.json"; Dst="$vc\settings.json"},
    @{Src="$BackupDir\configs\vscode\keybindings.json"; Dst="$vc\keybindings.json"}
)
foreach ($f in $vsFiles) {
    if (Test-File $f.Src) {
        if (-not $DryRun) { Copy-Item $f.Src -Dest $f.Dst -Force; Write-Log "  $(Split-Path $f.Dst -Leaf) restored" }
        else { Write-Log "  [DRY RUN] Copy $($f.Src) -> $($f.Dst)" }
    }
}
# snippets
$snippetsSrc = "$BackupDir\configs\vscode\snippets"
if (Test-Path $snippetsSrc) {
    if (-not $DryRun) {
        Copy-Item "$snippetsSrc\*" -Dest "$vc\snippets\" -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log "  VS Code snippets restored"
    } else { Write-Log "  [DRY RUN] Restore VS Code snippets" }
}

# Git
foreach ($f in @("$BackupDir\configs\git\.gitconfig", "$BackupDir\configs\git\.gitignore_global")) {
    if (Test-File $f) {
        $dest = "$env:USERPROFILE\$(Split-Path $f -Leaf)"
        if (-not $DryRun) { Copy-Item $f -Dest $dest -Force; Write-Log "  $(Split-Path $f -Leaf) restored" }
        else { Write-Log "  [DRY RUN] Copy $f -> $dest" }
    }
}

# SSH
$sshDir = "$env:USERPROFILE\.ssh"
if (-not (Test-Path $sshDir)) { New-Item -ItemType Directory -Path $sshDir -Force | Out-Null }
foreach ($f in @("$BackupDir\configs\ssh\config", "$BackupDir\configs\ssh\known_hosts")) {
    if (Test-File $f) {
        $dest = "$sshDir\$(Split-Path $f -Leaf)"
        if (-not $DryRun) { Copy-Item $f -Dest $dest -Force; Write-Log "  SSH $(Split-Path $f -Leaf) restored" }
        else { Write-Log "  [DRY RUN] Copy $f -> $dest" }
    }
}

# ══════════════════════════════════════════════════════════════════
# STEP 2: RESTORE REGISTRY SETTINGS (LOOK & FEEL)
# ══════════════════════════════════════════════════════════════════
Write-Log "`n[2/8] Restoring registry settings..."

$regFiles = Get-ChildItem "$BackupDir\registry\*.reg" -ErrorAction SilentlyContinue
if ($regFiles) {
    foreach ($reg in $regFiles) {
        if (-not $DryRun) {
            reg import "`"$($reg.FullName)`"" 2>$null | Out-Null
            Write-Host "     $($reg.Name)... " -NoNewline
        }
    }
    Write-Log "  $($regFiles.Count) registry files imported"
} else {
    Write-Log "  No registry backup found"
}

# Apply theme settings individually (more reliable)
$themeFile = "$BackupDir\configs\theme.txt"
if (Test-File $themeFile) {
    $themes = Get-Content $themeFile | ForEach-Object {
        $parts = $_ -split '='
        if ($parts.Count -eq 2) { @{$parts[0].Trim() = $parts[1].Trim()} }
    }
    if (-not $DryRun) {
        foreach ($t in $themes) {
            foreach ($k in $t.Keys) {
                $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
                Set-ItemProperty -Path $path -Name $k -Value ([int]$t[$k]) -ErrorAction SilentlyContinue
            }
        }
        Write-Log "  Theme (dark/light) restored"
    } else { Write-Log "  [DRY RUN] Restore theme settings" }
}

# Accent color
$acc = "$BackupDir\configs\accent_color.txt"
if (Test-File $acc) {
    $ac = Get-Content $acc
    if ($ac -match 'AccentColorMenu=(\d+)') {
        if (-not $DryRun) {
            Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent" -Name AccentColorMenu -Value ([int]$matches[1]) -ErrorAction SilentlyContinue
            Write-Log "  Accent color restored"
        } else { Write-Log "  [DRY RUN] Restore accent color" }
    }
}

# Taskbar settings
$taskbarFile = "$BackupDir\configs\taskbar_settings.xml"
if (Test-Path $taskbarFile) {
    if (-not $DryRun) {
        $tb = Import-CliXml $taskbarFile
        $ePath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        foreach ($k in $tb.Keys) {
            Set-ItemProperty -Path $ePath -Name $k -Value $tb[$k] -ErrorAction SilentlyContinue
        }
        Write-Log "  Taskbar settings restored"
    } else { Write-Log "  [DRY RUN] Restore taskbar settings" }
}

# Window metrics
$wmFile = "$BackupDir\configs\window_metrics.csv"
if (Test-Path $wmFile) {
    if (-not $DryRun) {
        $wm = Import-Csv $wmFile
        $wmPath = "HKCU:\Control Panel\Desktop\WindowMetrics"
        foreach ($e in $wm) {
            Set-ItemProperty -Path $wmPath -Name $e.Name -Value $e.Value -ErrorAction SilentlyContinue
        }
        Write-Log "  Window metrics restored"
    } else { Write-Log "  [DRY RUN] Restore window metrics" }
}

# ══════════════════════════════════════════════════════════════════
# STEP 3: INSTALL APPS (winget)
# ══════════════════════════════════════════════════════════════════
Write-Log "`n[3/8] Installing applications from backup..."

$wf = "$BackupDir\packages\winget.json"
if (Test-File $wf) {
    if (-not $DryRun) {
        Write-Host "  Installing apps via winget (this may take a while)..."
        winget import -i "$wf" --accept-source-agreements --accept-package-agreements 2>&1 | ForEach-Object { Write-Host "     $_" }
        Write-Log "  Winget packages installed"
    } else {
        Write-Log "  [DRY RUN] Would run: winget import -i `"$wf`""
    }
} else {
    Write-Log "  No winget package list found"

    # Offer to install common apps from a curated list if no backup exists
    if (-not $DryRun) {
        Write-Host ""
        Write-Host "  No app backup found. Install common apps? (y/n) " -NoNewline
        $resp = Read-Host
        if ($resp -eq 'y') {
            $commonApps = @(
                "Microsoft.DevHome",
                "Microsoft.WindowsTerminal",
                "Microsoft.PowerToys",
                "Microsoft.VisualStudioCode",
                "Git.Git",
                "7zip.7zip",
                "Google.Chrome",
                "Mozilla.Firefox",
                "Spotify.Spotify",
                "VideoLAN.VLC",
                "OBSProject.OBSStudio",
                "Discord.Discord",
                "Slack.Slack",
                "Notepad++.Notepad++",
                "GIMP.GIMP",
                "ShareX.ShareX",
                "UnityTechnologies.UnityHub",
                "WinDirStat.WinDirStat",
                "Greenshot.Greenshot",
                "Figma.Figma"
            )
            foreach ($app in $commonApps) {
                Write-Host "     Installing: $app"
                winget install --id $app --accept-source-agreements --accept-package-agreements 2>$null
            }
            Write-Log "  Common apps installed"
        }
    }
}

# ══════════════════════════════════════════════════════════════════
# STEP 4: VS CODE EXTENSIONS
# ══════════════════════════════════════════════════════════════════
Write-Log "`n[4/8] Restoring VS Code extensions..."

$extFile = "$BackupDir\configs\vscode\extensions.txt"
if (Test-File $extFile -and (Get-Command code -ErrorAction SilentlyContinue)) {
    $exts = Get-Content $extFile | Where-Object { $_ }
    if ($exts.Count -gt 0) {
        if (-not $DryRun) {
            foreach ($ext in $exts) {
                Write-Host "     $ext..."
                code --install-extension $ext --force 2>$null
            }
            Write-Log "  $($exts.Count) VS Code extensions installed"
        } else { Write-Log "  [DRY RUN] Would install $($exts.Count) extensions" }
    }
} else {
    Write-Log "  No extensions list or code CLI not found, skipping"
}

# ══════════════════════════════════════════════════════════════════
# STEP 5: POWERSHELL MODULES
# ══════════════════════════════════════════════════════════════════
Write-Log "`n[5/8] Restoring PowerShell modules..."

$modFile = "$BackupDir\configs\powershell\modules.csv"
if (Test-Path $modFile) {
    $mods = Import-Csv $modFile
    if (-not $DryRun) {
        foreach ($m in $mods) {
            Write-Host "     $($m.Name) $($m.Version)..."
            Install-Module -Name $m.Name -RequiredVersion $m.Version -Force -SkipPublisherCheck -ErrorAction SilentlyContinue
        }
        Write-Log "  PowerShell modules restored"
    } else { Write-Log "  [DRY RUN] Would install $($mods.Count) modules" }
} else {
    Write-Log "  No module list found, skipping"
}

# ══════════════════════════════════════════════════════════════════
# STEP 6: ENVIRONMENT VARIABLES
# ══════════════════════════════════════════════════════════════════
Write-Log "`n[6/8] Restoring environment variables..."

$envFile = "$BackupDir\env\user_env_vars.csv"
if (Test-Path $envFile) {
    $envVars = Import-Csv $envFile
    if (-not $DryRun) {
        foreach ($v in $envVars) {
            if ($v.Name -and $v.Value) {
                [Environment]::SetEnvironmentVariable($v.Name, $v.Value, "User")
            }
        }
        Write-Log "  $($envVars.Count) environment variables restored"
    } else { Write-Log "  [DRY RUN] Would restore $($envVars.Count) env vars" }
}

# Restore user PATH
$upf = "$BackupDir\env\user_path.txt"
if (Test-Path $upf) {
    $paths = Get-Content $upf | Where-Object { $_ }
    if ($paths.Count -gt 0) {
        if (-not $DryRun) {
            [Environment]::SetEnvironmentVariable("Path", ($paths -join ';'), "User")
            Write-Log "  User PATH restored ($($paths.Count) entries)"
        } else { Write-Log "  [DRY RUN] Would restore user PATH" }
    }
}

# ══════════════════════════════════════════════════════════════════
# STEP 7: RESTORE WALLPAPER
# ══════════════════════════════════════════════════════════════════
Write-Log "`n[7/8] Restoring wallpaper..."

$wallpaperFiles = Get-ChildItem "$BackupDir\configs\wallpaper.*" -ErrorAction SilentlyContinue
if ($wallpaperFiles) {
    if (-not $DryRun) {
        $wp = $wallpaperFiles[0].FullName
        try {
            Add-Type -TypeDefinition @"
using System.Runtime.InteropServices;
public class Wallpaper {
    [DllImport("user32.dll", CharSet=CharSet.Auto)]
    public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
"@
            [Wallpaper]::SystemParametersInfo(20, 0, $wp, 2) | Out-Null
            Write-Log "  Wallpaper restored"
        } catch { Write-Log "  Wallpaper restore failed" }
    } else { Write-Log "  [DRY RUN] Would set wallpaper" }
} else {
    $wpPathFile = "$BackupDir\configs\wallpaper_path.txt"
    if (Test-Path $wpPathFile) {
        $wpPath = (Get-Content $wpPathFile) -replace 'WallpaperPath=',''
        Write-Log "  Wallpaper path was: $wpPath (not backed up, use -IncludeWallpaper on backup)"
    }
}

# ══════════════════════════════════════════════════════════════════
# STEP 8: ADDITIONAL MISC RESTORE
# ══════════════════════════════════════════════════════════════════
Write-Log "`n[8/8] Additional restore steps..."

# Hosts file
$hostsBackup = "$BackupDir\configs\hosts.backup"
if (Test-File $hostsBackup) {
    if (-not $DryRun) {
        Copy-Item $hostsBackup -Dest "$env:windir\System32\drivers\etc\hosts" -Force -ErrorAction SilentlyContinue
        Write-Log "  Hosts file restored"
    } else { Write-Log "  [DRY RUN] Restore hosts file" }
}

# Startup entries
$startupFile = "$BackupDir\configs\startup.csv"
if (Test-Path $startupFile) {
    $entries = Import-Csv $startupFile
    if (-not $DryRun) {
        foreach ($e in $entries) {
            Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name $e.Name -Value $e.Command -ErrorAction SilentlyContinue
        }
        Write-Log "  Startup entries restored"
    } else { Write-Log "  [DRY RUN] Restore $($entries.Count) startup entries" }
}

# Power scheme
$psf = "$BackupDir\configs\active_power_scheme.txt"
if (Test-Path $psf) {
    $content = Get-Content $psf | Where-Object { $_ -match '\(([a-fA-F0-9-]{36})\)' }
    if ($content) {
        $guid = $matches[1]
        if (-not $DryRun) {
            powercfg /setactive $guid 2>$null
            Write-Log "  Power scheme restored"
        } else { Write-Log "  [DRY RUN] powercfg /setactive $guid" }
    }
}

# Defender exclusions
$defFile = "$BackupDir\configs\defender_exclusions.csv"
if (Test-Path $defFile) {
    $exclusions = Import-Csv $defFile
    if (-not $DryRun -and $exclusions) {
        foreach ($ex in $exclusions) {
            if ($ex.ExclusionPath) { Add-MpPreference -ExclusionPath $ex.ExclusionPath -ErrorAction SilentlyContinue }
        }
        Write-Log "  Defender exclusions restored"
    } else { Write-Log "  [DRY RUN] Restore defender exclusions" }
}

# ══════════════════════════════════════════════════════════════════
# FINAL SUMMARY
# ══════════════════════════════════════════════════════════════════
Write-Log ""
Write-Log "========================================================"
Write-Log "  RESTORE COMPLETE!"
Write-Log "========================================================"
Write-Log "  Log: $log"
if (-not $DryRun) {
    Write-Log "  Some changes need a reboot or logoff to take effect."
    Write-Log "  Run this to restart Explorer:  taskkill /f /im explorer.exe & start explorer"
}
Write-Log ""
Write-Log "  To re-run on a different machine, just copy the"
Write-Log "  backup_windows folder and run restore.ps1 as Admin."
