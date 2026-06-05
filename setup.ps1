param(
    [Parameter(Mandatory, ParameterSetName='Backup')][switch]$Backup,
    [Parameter(Mandatory, ParameterSetName='Restore')][switch]$Restore,
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

# No mode specified — show help
Write-Host @"

USAGE
  .\setup.ps1 -Backup                 # Backup current machine config
  .\setup.ps1 -Restore                # Restore config on a fresh install

OPTIONS
  -IncludeWallpaper   (backup) Include wallpaper image (may be large)
  -Silent             (restore) Suppress console output
  -DryRun             (restore) Show what would be done without applying
  -SkipAniCli         (restore) Skip ani-cli/anime setup
  -SkipMaelStream     (restore) Skip MaelStream torrent CLI setup

EXAMPLES
  .\setup.ps1 -Backup
  .\setup.ps1 -Restore -SkipAniCli
  .\setup.ps1 -Restore -DryRun

"@
