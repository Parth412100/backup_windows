[CmdletBinding(DefaultParameterSetName='Help')]
param(
    [Parameter(ParameterSetName='Backup')][switch]$Backup,
    [Parameter(ParameterSetName='Restore')][switch]$Restore,
    [Parameter(ParameterSetName='Help')][switch]$Help,
    [switch]$IncludeWallpaper,
    [switch]$Silent,
    [switch]$SkipAniCli,
    [switch]$SkipMaelStream,
    [switch]$DryRun
)

$ErrorActionPreference = "Continue"

$repoDir = Split-Path $MyInvocation.MyCommand.Path -Parent
$backupScript = Join-Path $repoDir "backup.ps1"
$restoreScript = Join-Path $repoDir "restore.ps1"

function Write-Banner {
    $msg = @"
╔══════════════════════════════════════════════════╗
║        WINDOWS SETUP - Backup & Restore          ║
║      https://github.com/Parth412100/backup_windows ║
╚══════════════════════════════════════════════════╝
"@
    Write-Host $msg -ForegroundColor Cyan
}

function Invoke-Backup {
    Write-Host "`n=== RUNNING BACKUP ===" -ForegroundColor Green
    if (-not (Test-Path $backupScript)) {
        Write-Host "ERROR: backup.ps1 not found at $backupScript" -ForegroundColor Red
        exit 1
    }
    $args = @()
    if ($IncludeWallpaper) { $args += "-IncludeWallpaper" }
    & powershell -ExecutionPolicy Bypass -File $backupScript @args
    if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) {
        Write-Host "Backup completed with warnings." -ForegroundColor Yellow
    } else {
        Write-Host "`nBackup complete! You can now commit and push this folder to GitHub." -ForegroundColor Green
        Write-Host "On a fresh install, clone the repo and run:" -ForegroundColor Cyan
        Write-Host "  .\setup.ps1 -Restore" -ForegroundColor White
    }
}

function Invoke-Restore {
    Write-Host "`n=== RUNNING RESTORE ===" -ForegroundColor Green
    if (-not (Test-Path $restoreScript)) {
        Write-Host "ERROR: restore.ps1 not found at $restoreScript" -ForegroundColor Red
        exit 1
    }
    $args = @()
    if ($Silent) { $args += "-Silent" }
    if ($DryRun) { $args += "-DryRun" }
    if ($SkipAniCli) { $args += "-SkipAniCli" }
    if ($SkipMaelStream) { $args += "-SkipMaelStream" }
    & powershell -ExecutionPolicy Bypass -File $restoreScript @args
    if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) {
        Write-Host "Restore completed with warnings." -ForegroundColor Yellow
    } else {
        Write-Host "`nRestore complete! Some changes may need a reboot." -ForegroundColor Green
    }
}

Write-Banner

if ($Backup) { Invoke-Backup; exit }
if ($Restore) { Invoke-Restore; exit }

# No valid mode or -Help — show help
Write-Host @"

  ╔══════════════════════════════════════════════════╗
  ║  WINDOWS SETUP — Backup & Restore               ║
  ║  Save your PC setup. Restore after a clean wipe. ║
  ╚══════════════════════════════════════════════════╝

  WHAT DO YOU WANT TO DO?

  [B] Backup your current PC
      .\setup.ps1 -Backup
      Saves your settings, apps, themes, configs, etc.

  [R] Restore after a clean Windows install
      .\setup.ps1 -Restore
      Re-installs everything from your last backup.

  OPTIONS
      -IncludeWallpaper   (backup)   Save wallpaper image too
      -DryRun             (restore)  Preview without applying
      -Silent             (restore)  No screen output, just log
      -SkipAniCli         (restore)  Skip anime streaming setup
      -SkipMaelStream     (restore)  Skip torrent streaming setup

  FIRST TIME?
    1. Run .\setup.ps1 -Backup on your current machine
    2. Git commit & push to save it
    3. After wiping, clone and run .\setup.ps1 -Restore

"@
