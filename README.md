# windows-settings

[![CI](https://github.com/lock14/windows-settings/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/lock14/windows-settings/actions/workflows/ci.yml)

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
.\fonts\font-setup.ps1              # Download & install MesloLGS NF fonts
.\posh\posh-setup.ps1               # Install Oh My Posh & configure profile
.\completions\completions-setup.ps1 # Register CLI tab completions (gh, winget, docker)
.\terminal\terminal-setup.ps1       # Apply Windows Terminal settings (Solarized Dark)
.\packages\winget-setup.ps1         # Install essential developer tools via winget
```

---

## What's Included

### 1. Powerlevel10k Single-Line Prompt (`posh/p10k.omp.json`)
- Direct port of Powerlevel10k Rainbow adapted to a single-line prompt with Solarized Dark palette tones.
- Right prompt (`rprompt`) with execution time, status codes, and language environment indicators (Go, Python, Node, .NET, Rust, AWS).

### 2. Shell Intelligence & Auto-Suggestions
- **Predictive IntelliSense (`PSReadLine`)**: Fish/Zsh-style inline history prediction styled in Solarized Dark muted tones (`#586E75`).
- **Interactive History Search (`Ctrl+R`)**: Live fuzzy search over persistent command history using `fzf`.
- **Menu Completion (`Tab`)**: Visual, interactive dropdown menu navigation for command arguments and paths.

### 3. Git & Developer Shortcuts
Includes the full Oh My Zsh Git plugin suite and custom workflow helpers:

| Shortcut | Description |
| :--- | :--- |
| `Ctrl+R` | Interactive fuzzy search command history via `fzf` |
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
| `go_testall` | `go test ./...` |
| `go_buildall` | `go build ./...` |
| `go_lint` | `golangci-lint run` (with auto-cached configuration) |
| `tf` | `terraform` |
| `yaml_lint` | `yamllint -c ~/.yamllint.yml` |
| `fs` | Fast recursive directory tree search (`fd --no-ignore-vcs` + `tree`) |

### 4. Native CLI Utilities (`bin/`)
Ported from `home-settings/common-bin/` for native PowerShell execution:

| Utility | Description | Example Usage |
| :--- | :--- | :--- |
| `gen-passwd.ps1` | Cryptographically secure random password generator | `gen-passwd.ps1 -Length 24 -IncludeSymbols` |
| `repeat-until-success.ps1` | Retries a command until exit code 0 | `repeat-until-success.ps1 -Command "curl https://example.com"` |
| `sum.ps1` | Sums numbers from standard input / pipeline | `1..100 \| sum.ps1` |

### 5. Solarized Dark & MesloLGS NF Windows Terminal (`terminal/settings.json`)
- Canonical Solarized Dark color scheme.
- MesloLGS NF font pre-configured for powerline glyphs.
- Custom keybindings (`Ctrl+C` copy, `Ctrl+V` paste, `Alt+Shift+D` split pane).

---

## Directory Overview

| Path | Description |
| :--- | :--- |
| `setup.ps1` | Master setup script orchestrating fonts, prompt, completions, PATH, and terminal |
| `bin/` | Native CLI utilities (`gen-passwd.ps1`, `repeat-until-success.ps1`, `sum.ps1`) |
| `completions/` | Tab completions for `gh`, `winget`, `docker`, `kubectl`, `helm`, `terraform` |
| `fonts/` | Downloads and installs MesloLGS NF fonts |
| `packages/` | Workstation developer tool provisioning with `winget` |
| `posh/p10k.omp.json` | Oh My Posh Solarized Dark single-line Powerlevel10k theme |
| `posh/Microsoft.PowerShell_profile.ps1` | PowerShell profile (Oh My Posh + Git/Dev aliases + PSReadLine) |
| `posh/posh-setup.ps1` | Installs Oh My Posh via winget, deploys theme & profile |
| `terminal/settings.json` | Windows Terminal configuration & color schemes |
| `terminal/terminal-setup.ps1` | Deploys `settings.json` to Windows Terminal `LocalState` with backups |
| `tests/test_settings.ps1` | Comprehensive test suite for CI and local verification |
