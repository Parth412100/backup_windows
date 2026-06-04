# Windows Setup — Backup & Restore

One-command backup of your Windows config, apps, and settings. Restore everything on a fresh install in minutes.

## Quick Start

### Fresh install — one-liner
```powershell
git clone https://github.com/Parth412100/backup_windows.git; cd backup_windows; .\setup.ps1 -Restore
```

### Backup current machine
```powershell
.\setup.ps1 -Backup
```

### Backup your current machine
```powershell
.\setup.ps1 -Backup
```

### Restore on a fresh Windows install
```powershell
.\setup.ps1 -Restore
```

Both commands handle elevation automatically (run as Admin when needed).

## Prerequisites

- Windows 10 1809+ or Windows 11
- PowerShell 5.1+
- Git (for cloning)
- [winget](https://apps.microsoft.com/detail/9NBLGGH4NNS1) (App Installer)

## What gets backed up

| Category | Details |
|----------|---------|
| **Config files** | PowerShell profile, Windows Terminal, VS Code (settings, keybindings, snippets, extensions), Git config, SSH config |
| **Registry** | Explorer, taskbar, context menu, mouse, keyboard, notifications, privacy, search, start menu |
| **Environment** | User environment variables + PATH entries |
| **Packages** | winget export, Chocolatey list, Scoop export, installed programs list, Windows Features |
| **Startup** | Programs that auto-start via HKCU\Run |
| **Scheduled tasks** | Non-Microsoft scheduled tasks |
| **Power scheme** | Active power plan GUID + all powercfg settings |
| **Theme** | Dark/light mode, accent color, window metrics |
| **Wallpaper** | Optional (`-IncludeWallpaper`) — saves the image; otherwise saves the path |
| **Fonts** | Installed font list |
| **Defender** | Antivirus exclusion paths, extensions, and processes |
| **Hosts file** | `%windir%\System32\drivers\etc\hosts` |
| **Taskbar** | Icon size, alignment, Copilot/Widgets buttons |

## Restore includes

- All config files + registry settings
- App installation via winget (auto or from backup manifest)
- VS Code extensions
- PowerShell modules
- Environment variables + PATH
- Wallpaper
- Defender exclusions
- Hosts file
- Startup entries
- Power scheme
- **Optional**: ani-cli anime streaming CLI (skip with `-SkipAniCli`)

## Usage

```powershell
# Full backup (no wallpaper image)
.\setup.ps1 -Backup

# Full backup including wallpaper
.\setup.ps1 -Backup -IncludeWallpaper

# Full restore
.\setup.ps1 -Restore

# Restore without ani-cli setup
.\setup.ps1 -Restore -SkipAniCli

# Preview restore without applying changes
.\setup.ps1 -Restore -DryRun

# Silent restore (log only, no console output)
.\setup.ps1 -Restore -Silent
```

## Workflow

```
┌──────────────────────────────────────────────┐
│  1. Run on current machine:                  │
│     .\setup.ps1 -Backup                      │
│                                              │
│  2. Commit & push to GitHub:                 │
│     git add .                                │
│     git commit -m "backup YYYY-MM-DD"        │
│     git push                                 │
│                                              │
│  3. On fresh install, clone & restore:       │
│     git clone <repo-url>                     │
│     cd backup_windows                        │
│     .\setup.ps1 -Restore                     │
└──────────────────────────────────────────────┘
```

> **Tip**: Run the restore in steps by checking `restore.ps1` — you can comment out sections you don't need.

## File structure

```
backup_windows/
├── setup.ps1              # Master entry point
├── backup.ps1             # Backup script
├── restore.ps1            # Restore script
├── configs/               # Configuration files
│   ├── powershell/        # Profile, modules, repositories
│   ├── terminal/          # Windows Terminal settings
│   ├── vscode/            # VS Code settings + snippets
│   ├── git/               # .gitconfig, .gitignore_global
│   ├── ssh/               # SSH config, known_hosts
│   ├── startup.csv        # Startup programs
│   ├── theme.txt          # Dark/light mode
│   ├── accent_*.txt       # Accent color
│   ├── window_metrics.csv # Border width, title bar height
│   ├── fonts.csv          # Installed fonts list
│   ├── defender_exclusions.csv
│   └── hosts.backup       # Hosts file copy
├── env/                   # Environment variables + PATH
├── registry/              # Exported .reg files
├── packages/              # winget, choco, scoop exports
├── scheduled_tasks/       # User task definitions
└── restore_points/        # Registry snapshots before changes
```
