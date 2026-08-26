# windows-settings

Windows workstation configuration files and setup automation for PowerShell 7 and Windows Terminal.

Designed to provide visual and functional parity with [`home-settings`](https://github.com/lock14/home-settings) (*nix / Zsh / Solarized Dark).

---

## Prerequisites

The following tools should be available on Windows:

- **PowerShell 7+** (`pwsh`)
- **Git for Windows**
- **Windows Terminal**
- **winget** (Windows Package Manager, included in Windows 10/11)

---

## Quick Start

Open PowerShell 7 (`pwsh`) and run:

```powershell
git clone https://github.com/lock14/windows-settings.git
cd windows-settings
.\setup.ps1
```

To run individual components:

```powershell
.\fonts\font-setup.ps1          # Download & install MesloLGS NF fonts
.\posh\posh-setup.ps1           # Install Oh My Posh & configure profile
.\terminal\terminal-setup.ps1   # Apply Windows Terminal settings (Solarized Dark)
```

---

## What's Included

### 1. Powerlevel10k Single-Line Prompt (`posh/p10k.omp.json`)
- Direct port of Powerlevel10k Rainbow adapted to a single-line prompt with Solarized Dark palette tones.
- Right prompt (`rprompt`) with execution time, status codes, and language environment indicators (Go, Python, Node, .NET, Rust, AWS).

### 2. Git Shortcuts (`posh/Microsoft.PowerShell_profile.ps1`)
Includes the full Oh My Zsh Git plugin suite and custom workflow helpers:

| Shortcut | Action |
| :--- | :--- |
| `gco` | `git checkout` |
| `gcb` | `git checkout -b` |
| `gcm` | `git checkout main` (or `master`) |
| `ga` / `gaa` | `git add` / `git add --all` |
| `gst` / `gss` | `git status` / `git status -s` |
| `gd` / `gds` | `git diff` / `git diff --staged` |
| `gl` / `gp` | `git pull` / `git push` |
| `gb` / `gba` / `gbd` | `git branch` (list / all / delete) |
| `gsta` / `gstp` / `gstl` | `git stash` (push / pop / list) |
| `glog` / `glo` | `git log --graph` / `git log --oneline` |
| `grb` / `grbc` / `grba` | `git rebase` / `--continue` / `--abort` |
| `gcommit` | `git add -A && git commit` |
| `gamend` | `git add -A && git commit --amend --no-edit` |
| `gup` | `git fetch && git pull --rebase origin HEAD` |
| `gprune` | Delete local branches except `main`/`master` |
| `gsync` | Rebase current branch onto latest `main`/`master` |

### 3. Solarized Dark & MesloLGS NF Windows Terminal (`terminal/settings.json`)
- Canonical Solarized Dark color scheme.
- MesloLGS NF font pre-configured for powerline glyphs.
- Custom keybindings (`Ctrl+C` copy, `Ctrl+V` paste, `Alt+Shift+D` split pane).

---

## Directory Overview

| Path | Description |
| :--- | :--- |
| `setup.ps1` | Master setup script orchestrating fonts, prompt, and terminal setup |
| `fonts/font-setup.ps1` | Downloads and installs MesloLGS NF Regular, Bold, Italic fonts |
| `posh/p10k.omp.json` | Oh My Posh Solarized Dark single-line Powerlevel10k theme |
| `posh/posh-setup.ps1` | Installs Oh My Posh via winget, deploys theme & profile |
| `posh/Microsoft.PowerShell_profile.ps1` | Profile template with Git aliases & Oh My Posh init |
| `terminal/settings.json` | Windows Terminal configuration & color schemes |
| `terminal/terminal-setup.ps1` | Deploys `settings.json` to Windows Terminal `LocalState` with backups |
