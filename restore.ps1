param(
    [string]$BackupDir = "$PSScriptRoot",
    [switch]$DryRun,
    [switch]$Silent,
    [switch]$SkipAniCli,
    [switch]$SkipMaelStream,
    [switch]$Resume
)

$log = "$BackupDir\restore.log"
$checkpointFile = "$BackupDir\.restore_checkpoint"

function Write-Log {
    param([string]$Message)
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message"
    if (-not $Silent) { Write-Host $line }
    Add-Content -Path $log -Value $line
}

function Invoke-WithTimeout {
    param([scriptblock]$ScriptBlock, [int]$TimeoutSeconds, [string]$Label = "Command")
    $job = Start-Job -ScriptBlock $ScriptBlock
    $job | Wait-Job -Timeout $TimeoutSeconds | Out-Null
    if ($job.State -eq 'Running') {
        Stop-Job $job
        Write-Log "  TIMEOUT: $Label timed out after ${TimeoutSeconds}s, skipping"
        Write-Log "  TIP: Check your internet connection or try running the step manually."
        return $null
    }
    $output = Receive-Job -Job $job -ErrorAction SilentlyContinue
    Remove-Job $job -ErrorAction SilentlyContinue
    $output
}

function Save-Checkpoint {
    param([string]$Step)
    if ($DryRun) { return }
    $completed = @()
    if (Test-Path $checkpointFile) {
        $completed = Get-Content $checkpointFile
    }
    if ($completed -notcontains $Step) {
        $completed += $Step
        $completed | Out-File $checkpointFile -Encoding utf8
    }
    Write-Log "  CHECKPOINT: $Step completed"
}

function Test-Checkpoint {
    param([string]$Step)
    if (-not $Resume) { return $false }
    if (-not (Test-Path $checkpointFile)) { return $false }
    $completed = Get-Content $checkpointFile
    return $completed -contains $Step
}

function Clear-Checkpoints {
    if (Test-Path $checkpointFile) {
        Remove-Item $checkpointFile -Force
    }
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
                $(if ($DryRun) { "-DryRun" }),
                $(if ($SkipAniCli) { "-SkipAniCli" }),
                $(if ($SkipMaelStream) { "-SkipMaelStream" }),
                $(if ($Resume) { "-Resume" })
            ) -Wait
            exit
        }
    }
}

function Test-File {
    param([string]$Path)
    return (Test-Path $Path) -and ((Get-Item $Path).Length -gt 0)
}

function Write-Troubleshoot {
    param([string]$Section, [string]$Hint)
    Write-Log "  TIP: $Hint"
}

# If starting fresh (not resume), clear old checkpoints
if (-not $Resume -and -not $DryRun) {
    Clear-Checkpoints
}

# ─── ELEVATE ──────────────────────────────────────────────────────
if (-not $DryRun) { Ensure-Admin }

Write-Log "========================================================"
Write-Log "  WINDOWS RESTORE - Fresh Install Setup"
Write-Log "  Backup: $BackupDir"
Write-Log "========================================================"
if ($DryRun) { Write-Log "  *** DRY RUN - no changes applied ***" }
if ($Resume) { Write-Log "  *** RESUME MODE - skipping completed steps ***" }

# ══════════════════════════════════════════════════════════════════
# STEP 0a: CREATE PRE-RESTORE SNAPSHOT
# ══════════════════════════════════════════════════════════════════
if (Test-Checkpoint "pre-snapshot") {
    Write-Log "`n[Pre] Snapshot already created, skipping (use -Resume)"
} else {
    Write-Log "`n[Pre] Creating pre-restore system snapshot..."
    $rpScript = "$BackupDir\create_restore_point.ps1"
    if (Test-Path $rpScript) {
        if (-not $DryRun) {
            try {
                & powershell -ExecutionPolicy Bypass -File $rpScript
                Write-Log "  Pre-restore snapshot saved to restore_points/"
                Save-Checkpoint "pre-snapshot"
            } catch {
                Write-Log "  WARNING: Snapshot failed: $($_.Exception.Message)"
                Write-Log "  TIP: Run manually: .\create_restore_point.ps1"
            }
        } else {
            Write-Log "  [DRY RUN] Would create pre-restore snapshot"
        }
    } else {
        Write-Log "  create_restore_point.ps1 not found, skipping snapshot"
    }
}

# ══════════════════════════════════════════════════════════════════
# STEP 0: INSTALL PACKAGE MANAGERS
# ══════════════════════════════════════════════════════════════════
if (Test-Checkpoint "step0") {
    Write-Log "`n[0/9] Package managers already verified, skipping"
} else {
    Write-Log "`n[0/9] Ensuring package managers are installed..."
    try {
        $wingetAvailable = $null -ne (Get-Command winget -ErrorAction SilentlyContinue)
        if (-not $wingetAvailable -and -not $DryRun) {
            Write-Log "  winget not found. Please install App Installer from:"
            Write-Log "  https://apps.microsoft.com/detail/9NBLGGH4NNS1"
            Write-Log "  or run: winget install Microsoft.AppInstaller"
            Write-Log "  TIP: winget comes with Windows 10 1809+ and Windows 11. Update Windows if missing."
        }
        if (-not $DryRun) { Save-Checkpoint "step0" }
    } catch {
        Write-Log "  WARNING: Package manager check failed: $($_.Exception.Message)"
    }
}

# ══════════════════════════════════════════════════════════════════
# STEP 1: RESTORE CONFIG FILES
# ══════════════════════════════════════════════════════════════════
if (Test-Checkpoint "step1") {
    Write-Log "`n[1/9] Config files already restored, skipping"
} else {
    Write-Log "`n[1/9] Restoring config files..."
    try {
        $configOk = $true

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
        $termPairs = @(
            @{Src="settings.json"; Pattern="Microsoft.WindowsTerminal_*"}
            @{Src="settings_preview.json"; Pattern="Microsoft.WindowsTerminalPreview_*"}
        )
        foreach ($tp in $termPairs) {
            $p = "$BackupDir\configs\terminal\$($tp.Src)"
            if (Test-File $p) {
                $dirs = Get-ChildItem "$env:LOCALAPPDATA\Packages\$($tp.Pattern)\LocalState" -ErrorAction SilentlyContinue
                foreach ($d in $dirs) {
                    if (-not $DryRun) { Copy-Item $p -Dest "$($d.FullName)\settings.json" -Force; Write-Log "  Terminal $($tp.Src) restored" }
                    else { Write-Log "  [DRY RUN] Copy $p -> $($d.FullName)" }
                }
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

        if (-not $DryRun) { Save-Checkpoint "step1" }
    } catch {
        Write-Log "  ERROR restoring config files: $($_.Exception.Message)"
        Write-Log "  TIP: Manually copy configs from $BackupDir\configs\ to the right locations."
        Write-Troubleshoot "Config files" "Check paths in configs\ folder exist and have content."
    }
}

# ══════════════════════════════════════════════════════════════════
# STEP 2: RESTORE REGISTRY SETTINGS (LOOK & FEEL)
# ══════════════════════════════════════════════════════════════════
if (Test-Checkpoint "step2") {
    Write-Log "`n[2/9] Registry settings already restored, skipping"
} else {
    Write-Log "`n[2/9] Restoring registry settings..."
    try {
        $regFiles = Get-ChildItem "$BackupDir\registry\*.reg" -ErrorAction SilentlyContinue
        if ($regFiles) {
            foreach ($reg in $regFiles) {
                if (-not $DryRun) {
                    reg import "`"$($reg.FullName)`"" 2>$null | Out-Null
                }
            }
            Write-Log "  $($regFiles.Count) registry files imported"
        } else {
            Write-Log "  No registry backup found"
        }

        # Theme settings
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
        $taskbarFile = "$BackupDir\configs\taskbar_settings.json"
        if (Test-Path $taskbarFile) {
            if (-not $DryRun) {
                $tb = Get-Content $taskbarFile | ConvertFrom-Json
                $ePath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
                $tb.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS[A-Z]' } | ForEach-Object {
                    Set-ItemProperty -Path $ePath -Name $_.Name -Value $_.Value -ErrorAction SilentlyContinue
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

        if (-not $DryRun) { Save-Checkpoint "step2" }
    } catch {
        Write-Log "  ERROR restoring registry: $($_.Exception.Message)"
        Write-Log "  TIP: Run regedit and manually import .reg files from registry\ folder."
        Write-Troubleshoot "Registry" "Run as Admin is required for registry changes."
    }
}

# ══════════════════════════════════════════════════════════════════
# STEP 3: INSTALL APPS (winget)
# ══════════════════════════════════════════════════════════════════
if (Test-Checkpoint "step3") {
    Write-Log "`n[3/9] Apps already installed, skipping"
} else {
    Write-Log "`n[3/9] Installing applications from backup..."
    try {
        $wf = "$BackupDir\packages\winget.json"
        $wfExtra = "$BackupDir\packages\winget_extras.json"
        if (Test-File $wf) {
            if (-not $DryRun) {
                Write-Host "  Installing apps via winget (this may take a while)..."
                $mainResult = Invoke-WithTimeout { winget import -i "$wf" --accept-source-agreements --accept-package-agreements 2>&1 } 1800 "winget import (main)"
                if ($null -ne $mainResult) { $mainResult | ForEach-Object { Write-Host "     $_" } }
                if (Test-Path $wfExtra) {
                    $extraResult = Invoke-WithTimeout { winget import -i "$wfExtra" --accept-source-agreements --accept-package-agreements 2>&1 } 600 "winget import (extras)"
                    if ($null -ne $extraResult) { $extraResult | ForEach-Object { Write-Host "     $_" } }
                }
                Write-Log "  Winget packages installed"
            } else {
                Write-Log "  [DRY RUN] Would run: winget import -i `"$wf`""
                if (Test-Path $wfExtra) { Write-Log "  [DRY RUN] Also import winget_extras.json" }
            }
        } else {
            Write-Log "  No winget package list found"
            if (-not $DryRun -and -not $Silent) {
                Write-Host ""
                Write-Host "  No app backup found. Install common apps? (y/n) " -NoNewline
                $resp = Read-Host
                if ($resp -eq 'y') {
                    $commonApps = @(
                        "Microsoft.WindowsTerminal"
                        "Microsoft.PowerToys"
                        "Microsoft.VisualStudioCode"
                        "Git.Git"
                        "7zip.7zip"
                        "Google.Chrome"
                        "VideoLAN.VLC"
                        "Notepad++.Notepad++"
                        "Discord.Discord"
                    )
                    foreach ($app in $commonApps) {
                        Write-Host "     $app..."
                        Invoke-WithTimeout { winget install --id $app --accept-source-agreements --accept-package-agreements 2>$null } 300 "winget install $app" | Out-Null
                    }
                    Write-Log "  Common apps installed"
                }
            }
        }
        if (-not $DryRun) { Save-Checkpoint "step3" }
    } catch {
        Write-Log "  ERROR installing apps: $($_.Exception.Message)"
        Write-Log "  TIP: Run winget manually: winget import -i packages\winget.json"
        Write-Troubleshoot "App install" "Check internet connection. Some apps may need manual install."
    }
}

# ══════════════════════════════════════════════════════════════════
# STEP 4: VS CODE EXTENSIONS
# ══════════════════════════════════════════════════════════════════
if (Test-Checkpoint "step4") {
    Write-Log "`n[4/9] VS Code extensions already installed, skipping"
} else {
    Write-Log "`n[4/9] Restoring VS Code extensions..."
    try {
        $extFile = "$BackupDir\configs\vscode\extensions.txt"
        if (Test-File $extFile -and (Get-Command code -ErrorAction SilentlyContinue)) {
            $exts = Get-Content $extFile | Where-Object { $_ }
            if ($exts.Count -gt 0) {
                if (-not $DryRun) {
                    foreach ($ext in $exts) {
                        Write-Host "     $ext..."
                        Invoke-WithTimeout { code --install-extension $ext --force 2>$null } 60 "VS Code extension: $ext" | Out-Null
                    }
                    Write-Log "  $($exts.Count) VS Code extensions installed"
                } else { Write-Log "  [DRY RUN] Would install $($exts.Count) extensions" }
            }
        } else {
            Write-Log "  No extensions list or code CLI not found, skipping"
            Write-Log "  TIP: Install VS Code first, then re-run with -Resume"
        }
        if (-not $DryRun) { Save-Checkpoint "step4" }
    } catch {
        Write-Log "  ERROR installing VS Code extensions: $($_.Exception.Message)"
        Write-Troubleshoot "VS Code" "Install manually from extensions.txt"
    }
}

# ══════════════════════════════════════════════════════════════════
# STEP 5: POWERSHELL MODULES
# ══════════════════════════════════════════════════════════════════
if (Test-Checkpoint "step5") {
    Write-Log "`n[5/9] PowerShell modules already restored, skipping"
} else {
    Write-Log "`n[5/9] Restoring PowerShell modules..."
    try {
        $modFile = "$BackupDir\configs\powershell\modules.csv"
        if (Test-Path $modFile) {
            $mods = Import-Csv $modFile
            if (-not $DryRun) {
                Invoke-WithTimeout { Install-PackageProvider -Name NuGet -Force -ErrorAction SilentlyContinue } 60 "NuGet provider" | Out-Null
                foreach ($m in $mods) {
                    Write-Host "     $($m.Name) $($m.Version)..."
                    Invoke-WithTimeout { Install-Module -Name $m.Name -RequiredVersion $m.Version -Force -SkipPublisherCheck -ErrorAction SilentlyContinue } 120 "Install-Module $($m.Name)" | Out-Null
                }
                Write-Log "  PowerShell modules restored"
            } else { Write-Log "  [DRY RUN] Would install $($mods.Count) modules" }
        } else {
            Write-Log "  No module list found, skipping"
        }
        if (-not $DryRun) { Save-Checkpoint "step5" }
    } catch {
        Write-Log "  ERROR restoring PowerShell modules: $($_.Exception.Message)"
        Write-Troubleshoot "PS Modules" "Run: Install-Module -Name <name> -Force -SkipPublisherCheck"
    }
}

# ══════════════════════════════════════════════════════════════════
# STEP 6: ENVIRONMENT VARIABLES
# ══════════════════════════════════════════════════════════════════
if (Test-Checkpoint "step6") {
    Write-Log "`n[6/9] Environment variables already restored, skipping"
} else {
    Write-Log "`n[6/9] Restoring environment variables..."
    try {
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
        if (-not $DryRun) { Save-Checkpoint "step6" }
    } catch {
        Write-Log "  ERROR restoring environment variables: $($_.Exception.Message)"
        Write-Troubleshoot "Environment" "Manually set env vars from env\ folder files."
    }
}

# ══════════════════════════════════════════════════════════════════
# STEP 7: RESTORE WALLPAPER
# ══════════════════════════════════════════════════════════════════
if (Test-Checkpoint "step7") {
    Write-Log "`n[7/9] Wallpaper already restored, skipping"
} else {
    Write-Log "`n[7/9] Restoring wallpaper..."
    try {
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
        if (-not $DryRun) { Save-Checkpoint "step7" }
    } catch {
        Write-Log "  WARNING: Wallpaper restore failed: $($_.Exception.Message)"
    }
}

# ══════════════════════════════════════════════════════════════════
# STEP 8: ADDITIONAL MISC RESTORE
# ══════════════════════════════════════════════════════════════════
if (Test-Checkpoint "step8") {
    Write-Log "`n[8/9] Additional items already restored, skipping"
} else {
    Write-Log "`n[8/9] Additional restore steps..."
    try {
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
                    $val = $ex.Value
                    if ($val) {
                        switch ($ex.Type) {
                            'Path'      { Add-MpPreference -ExclusionPath $val -ErrorAction SilentlyContinue }
                            'Extension' { Add-MpPreference -ExclusionExtension $val -ErrorAction SilentlyContinue }
                            'Process'   { Add-MpPreference -ExclusionProcess $val -ErrorAction SilentlyContinue }
                        }
                    }
                }
                Write-Log "  Defender exclusions restored"
            } else { Write-Log "  [DRY RUN] Restore defender exclusions" }
        }
        if (-not $DryRun) { Save-Checkpoint "step8" }
    } catch {
        Write-Log "  WARNING: Additional restore had issues: $($_.Exception.Message)"
        Write-Troubleshoot "Misc restore" "Check hosts.backup, startup.csv, power_settings.txt exist."
    }
}

# ══════════════════════════════════════════════════════════════════
# STEP 9: SET UP ANI-CLI (optional)
# ══════════════════════════════════════════════════════════════════
if (-not $SkipAniCli) {
    if (Test-Checkpoint "step9") {
        Write-Log "`n[9/10] ani-cli already set up, skipping"
    } else {
        Write-Log "`n[9/10] Setting up ani-cli..."
        if (-not $DryRun) {
            try {
                if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
                    Write-Host "  Installing Scoop..."
                    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
                    $scoopResult = Invoke-WithTimeout { Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression } 60 "scoop install"
                    if ($null -ne $scoopResult) { Write-Log "  Scoop installed" } else { Write-Log "  Scoop install timed out, skipping" }
                } else {
                    Write-Log "  Scoop already installed"
                }

                $env:Path = [Environment]::GetEnvironmentVariable("Path","User") + ";" + [Environment]::GetEnvironmentVariable("Path","Machine")

                Invoke-WithTimeout { scoop bucket add extras 2>$null } 30 "scoop bucket add extras" | Out-Null

                Write-Host "  Installing fzf, ffmpeg, aria2, yt-dlp..."
                Invoke-WithTimeout { scoop install fzf ffmpeg aria2 yt-dlp 2>$null } 120 "scoop install deps" | Out-Null
                Write-Log "  ani-cli dependencies installed"

                if (-not (Get-Command mpv -ErrorAction SilentlyContinue)) {
                    Write-Host "  Installing mpv..."
                    Invoke-WithTimeout { winget install "mpv-player.mpv-CI.MSVC" --accept-source-agreements 2>$null } 300 "winget install mpv" | Out-Null
                    Write-Log "  mpv installed via winget"
                }

                $gitBash = if (Test-Path "C:\Program Files\Git\usr\bin\bash.exe") {
                    "C:\Program Files\Git\usr\bin\bash.exe"
                } elseif (Test-Path "C:\Program Files\Git\bin\bash.exe") {
                    "C:\Program Files\Git\bin\bash.exe"
                } else { $null }

                if (-not $gitBash) {
                    Write-Log "  Git Bash not found, installing Git for Windows..."
                    Invoke-WithTimeout { winget install Git.Git --accept-source-agreements --accept-package-agreements 2>$null } 300 "winget install Git" | Out-Null
                    $gitBash = "C:\Program Files\Git\usr\bin\bash.exe"
                }

                $aniCliDir = "$env:USERPROFILE\.ani-cli"
                if (-not (Test-Path "$aniCliDir\ani-cli")) {
                    New-Item -ItemType Directory -Path $aniCliDir -Force | Out-Null
                    $cloneResult = Invoke-WithTimeout { git clone https://github.com/pystardust/ani-cli.git $aniCliDir 2>$null } 120 "git clone ani-cli"
                    if ($null -ne $cloneResult) { Write-Log "  ani-cli cloned" } else { Write-Log "  ani-cli clone timed out, skipping" }
                } else { Write-Log "  ani-cli already cloned" }

                $fakeBin = "$aniCliDir\fake-bin"
                New-Item -ItemType Directory -Path $fakeBin -Force | Out-Null
                @'
#!/usr/bin/env bash
head -n 1
'@ | Out-File "$fakeBin\fzf" -Encoding ascii -Force

                $msysDir = $aniCliDir -replace '^([A-Z]):', '/$1' -replace '\\', '/'
                $msysScoop = $env:USERPROFILE -replace '^([A-Z]):', '/$1' -replace '\\', '/'
                @"
#!/usr/bin/env bash
export PATH="${fakeBin}:`$PATH"
export PATH="`$PATH:${msysScoop}/scoop/shims"
ANI_CLI_DOWNLOAD_DIR="`${1:-.}" $msysDir/ani-cli "`${@:2}"
"@ | Out-File "$aniCliDir\run-ani.sh" -Encoding ascii -Force

                $wrapper = "$env:USERPROFILE\scoop\shims\ani-cli.cmd"
                $msysPath = $aniCliDir -replace '\\', '/'
                $drive = ($aniCliDir -replace '^([A-Z]):.*', '/$1').ToLower()
                $rest = $aniCliDir -replace '^[A-Z]:', '' -replace '\\', '/'
                $bashPath = "$drive$rest"
                @"
@echo off
"$gitBash" -l -c "$bashPath/ani-cli" %*
"@ | Out-File $wrapper -Encoding ascii -Force

                Write-Log "  ani-cli setup complete!"
                Save-Checkpoint "step9"
            } catch {
                Write-Log "  WARNING: ani-cli setup failed: $($_.Exception.Message)"
                Write-Log "  TIP: Re-run with -SkipAniCli to skip this step."
            }
        } else {
            Write-Log "  [DRY RUN] Would install: scoop, fzf, ffmpeg, aria2, yt-dlp, mpv, ani-cli"
        }
    }
} else {
    Write-Log "`n[9/10] ani-cli skipped (-SkipAniCli)"
}

# ══════════════════════════════════════════════════════════════════
# STEP 10: SET UP MAELSTREAM (optional)
# ══════════════════════════════════════════════════════════════════
if (-not $SkipMaelStream) {
    if (Test-Checkpoint "step10") {
        Write-Log "`n[10/10] MaelStream already set up, skipping"
    } else {
        Write-Log "`n[10/10] Setting up MaelStream..."
        if (-not $DryRun) {
            try {
                $maelDir = "$env:USERPROFILE\.maelstream"
                if (-not (Test-Path "$maelDir\watch.ps1")) {
                    New-Item -ItemType Directory -Path $maelDir -Force | Out-Null
                    $cloneResult = Invoke-WithTimeout { git clone https://github.com/Parth412100/MaelStream.git $maelDir 2>$null } 120 "git clone MaelStream"
                    if ($null -ne $cloneResult) {
                        Write-Log "  MaelStream cloned to $maelDir"
                        Push-Location $maelDir
                        $npmResult = Invoke-WithTimeout { npm install 2>$null } 120 "npm install MaelStream"
                        if ($null -ne $npmResult) {
                            Write-Log "  MaelStream dependencies installed"
                        } else { Write-Log "  npm install timed out, skipping" }
                        Pop-Location
                    } else { Write-Log "  MaelStream clone timed out, skipping" }
                } else {
                    Write-Log "  MaelStream already cloned, pulling latest..."
                    Push-Location $maelDir
                    git pull 2>$null
                    npm install 2>$null | Out-Null
                    Pop-Location
                    Write-Log "  MaelStream updated"
                }
                $scriptDir = Split-Path -Parent $PSCommandPath
                $wrapper = "$scriptDir\maelstream.cmd"
                @"
@echo off
cd /d "$maelDir"
pwsh -NoProfile -ExecutionPolicy Bypass -File ".\watch.ps1" %*
"@ | Out-File $wrapper -Encoding ascii -Force
                Write-Log "  MaelStream setup complete!"
                Save-Checkpoint "step10"
            } catch {
                Write-Log "  WARNING: MaelStream setup failed: $($_.Exception.Message)"
                Write-Log "  TIP: Re-run with -SkipMaelStream to skip, or install manually."
            }
        } else {
            Write-Log "  [DRY RUN] Would clone MaelStream + npm install"
        }
    }
} else {
    Write-Log "`n[10/10] MaelStream skipped (-SkipMaelStream)"
}

# ══════════════════════════════════════════════════════════════════
# FINAL SUMMARY
# ══════════════════════════════════════════════════════════════════
Write-Log ""
Write-Log "========================================================"
Write-Log "  RESTORE COMPLETE!"
Write-Log "========================================================"
Write-Log "  Log: $log"
if ($Resume) {
    Write-Log "  Checkpoint file: $checkpointFile"
    Write-Log "  Run without -Resume next time for a full restore."
}
if (-not $DryRun) {
    Write-Log "  Some changes need a reboot or logoff to take effect."
    Write-Log "  Run this to restart Explorer:  taskkill /f /im explorer.exe & start explorer"
}
$manualFile = "$BackupDir\packages\manual_install.txt"
if (Test-Path $manualFile) {
    $manualCount = (Get-Content $manualFile | Where-Object { $_ -match '^- ' }).Count
    if ($manualCount -gt 0) {
        Write-Log "  $manualCount programs need manual install"
        Write-Log "  See: packages\manual_install.txt"
    }
}
if (-not $DryRun) {
    Write-Log ""
    Write-Log "  If any step failed, fix the issue and re-run with:"
    Write-Log "    .\setup.ps1 -Restore -Resume"
    Write-Log "  This skips already-completed steps."
}
Write-Log ""
Write-Log "  To re-run on a different machine, just copy the"
Write-Log "  backup_windows folder and run restore.ps1 as Admin."
