# Windows Setup — Backup & Restore

One-command backup of your Windows config, apps, and settings.  
Restore everything on a fresh install in minutes. No manual setup needed.

## What is this?

This tool saves your Windows personalization (theme, taskbar, registry settings),
installed apps, environment variables, config files, and more — so if you ever
wipe your PC or get a new one, you can restore everything exactly as it was
with a single command.

---

## Quick Start

### 🖥️ I just wiped my PC — how do I get everything back?

1. Install Git from https://git-scm.com (if not already installed)
2. Open **PowerShell as Administrator** (right-click Start → Terminal (Admin))
3. Run this:

```powershell
git clone https://github.com/Parth412100/backup_windows.git
cd backup_windows
.\setup.ps1 -Restore
```

That's it. The script will install all your apps, restore settings, themes,
wallpaper, and more automatically.

### 📦 I'm on my current PC — how do I save my setup?

```powershell
.\setup.ps1 -Backup
```

Then commit and push to GitHub (see Workflow below).

---

## Prerequisites

- **Windows 10** (1809+) or **Windows 11**
- **PowerShell 5.1+** (comes with Windows)
- **Git** — [Download here](https://git-scm.com) if you don't have it
- **winget** — comes with Windows, but if missing install
  [App Installer](https://apps.microsoft.com/detail/9NBLGGH4NNS1)

---

## What gets backed up?

| Category | What's saved |
|----------|-------------|
| **Config files** | PowerShell profile, Windows Terminal, VS Code (settings, keybindings, snippets, extensions), Git config, SSH config |
| **Registry** | Explorer, taskbar, context menu, mouse, keyboard, notifications, privacy, search, start menu |
| **Environment** | Your user environment variables and PATH |
| **Apps & packages** | winget export, Chocolatey list, Scoop export, full installed programs list, Windows Features |
| **Startup** | Programs that auto-start when you log in |
| **Scheduled tasks** | Your non-Microsoft scheduled tasks |
| **Power scheme** | Active power plan and all power settings |
| **Theme** | Dark/light mode, accent color, window metrics |
| **Wallpaper** | Saves the path by default, or the image itself with `-IncludeWallpaper` |
| **Fonts** | List of installed fonts |
| **Defender** | Antivirus exclusion paths, extensions, and processes |
| **Hosts file** | `C:\Windows\System32\drivers\etc\hosts` |
| **Taskbar** | Icon size, alignment, Copilot/Widgets buttons |

## What gets restored?

Everything from backup plus:

- All config files + registry settings
- App installation via winget
- VS Code extensions
- PowerShell modules
- Environment variables + PATH
- Wallpaper
- Defender exclusions
- Hosts file
- Startup entries
- Power scheme
- **Optional**: ani-cli (anime streaming CLI) and MaelStream (torrent streaming)

---

## All Commands

### Backup

```powershell
.\setup.ps1 -Backup                   # Full backup (no wallpaper image)
.\setup.ps1 -Backup -IncludeWallpaper # Include wallpaper image
```

### Restore

```powershell
.\setup.ps1 -Restore                # Full restore
.\setup.ps1 -Restore -DryRun        # Preview only — don't apply anything
.\setup.ps1 -Restore -Silent        # No console output, just logging
.\setup.ps1 -Restore -SkipAniCli    # Skip ani-cli anime setup
.\setup.ps1 -Restore -SkipMaelStream # Skip MaelStream torrent setup
```

---

## Workflow

```
┌─────────────────────────────────────────────────────┐
│  1. On your current PC:                             │
│     .\setup.ps1 -Backup                             │
│                                                     │
│  2. Save to GitHub:                                 │
│     git add .                                       │
│     git commit -m "backup 2026-06-08"               │
│     git push                                        │
│                                                     │
│  3. After wiping or on a new PC:                    │
│     git clone https://github.com/Parth412100/backup_windows.git
│     cd backup_windows                               │
│     .\setup.ps1 -Restore                            │
└─────────────────────────────────────────────────────┘
```

> **Tip**: Run the restore in steps by opening `restore.ps1` in a text editor
> — you can comment out sections you don't need.

---

## FAQ — for beginners

### Do I need to install anything first?
Just **Git** if you don't have it. Windows already has PowerShell and winget.
Download Git: https://git-scm.com

### How do I open PowerShell as Administrator?
- Press `Windows key`, type `PowerShell`
- Right-click **PowerShell** → **Run as administrator**

### Will this delete my files?
No. The restore script **adds** settings and installs apps. It does not delete
your documents, photos, or any personal files.

### What if something goes wrong?
Run with `-DryRun` first to preview everything:
```powershell
.\setup.ps1 -Restore -DryRun
```
This shows what would happen without making any changes.

### Can I undo the restore?
The `restore_points/` folder contains a snapshot of your registry and system
state taken during the last backup. You can import the `.reg` files to revert
registry changes, but the easiest way is to just run backup again after
setting things up the way you like.

### Do I need to run this every day?
No. Just run `-Backup` whenever you make significant changes (installed new
apps, changed settings, customized themes, etc.).

---

## File structure

```
backup_windows/
├── setup.ps1               # Master entry point (run this)
├── backup.ps1              # Backup script
├── restore.ps1             # Restore script
├── create_restore_point.ps1 # Creates system state snapshots
├── configs/                # Your configuration files
│   ├── powershell/         # PowerShell profile, modules
│   ├── terminal/           # Windows Terminal settings
│   ├── vscode/             # VS Code settings, keybindings, snippets
│   ├── git/                # .gitconfig, .gitignore_global
│   ├── ssh/                # SSH config, known_hosts
│   ├── startup.csv         # Startup programs list
│   ├── theme.txt           # Dark/light mode setting
│   ├── accent_color.txt    # Accent color
│   ├── window_metrics.csv  # Border width, title bar height
│   ├── fonts.csv           # Installed fonts
│   ├── defender_exclusions.csv
│   └── hosts.backup        # Hosts file copy
├── env/                    # Environment variables + PATH
├── registry/               # Exported .reg registry files
├── packages/               # App package lists (winget, choco, scoop)
├── scheduled_tasks/        # User task definitions
└── restore_points/         # System snapshots (before-change backups)
```
