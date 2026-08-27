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

# Full automated setup
.\setup.ps1

# Full automated setup including winget package installation
.\setup.ps1 -InstallPackages
```

To run individual components:

```powershell
.\packages\winget-setup.ps1         # Install essential developer tools via winget
.\fonts\font-setup.ps1              # Download & install MesloLGS NF fonts
.\posh\posh-setup.ps1               # Install Oh My Posh & configure profile
.\completions\completions-setup.ps1 # Register CLI tab completions (gh, winget, docker, kubectl, helm)
.\terminal\terminal-setup.ps1       # Apply Windows Terminal settings (Solarized Dark)
.\vim\vim-setup.ps1                 # Provision Vim, Pathogen plugins & _vimrc
```

---

## What's Included

### 1. Powerlevel10k Single-Line Prompt (`posh/p10k.omp.json`)
- Direct port of Powerlevel10k Rainbow adapted to a single-line prompt with Solarized Dark palette tones.
- Right prompt (`rprompt`) with execution time, status codes, and language environment indicators (Go, Python, Node, .NET, Rust, AWS).

### 2. Shell Intelligence, Colors & Performance
- **Solarized Dark `LS_COLORS`**: Exact port of `home-settings/LS_COLORS` defining file and directory colors by type/extension for `ls`, `ll`, `la`, `fd`, `fzf`, and `fs`.
- **Predictive IntelliSense (`PSReadLine`)**: Fish/Zsh-style inline history prediction styled in Solarized Dark muted tones (`#586E75`).
- **Interactive History Search (`Ctrl+R`)**: Live fuzzy search over persistent command history powered by `fzf`.
- **Menu Completion (`Tab`)**: Visual, interactive dropdown menu navigation for command arguments and paths.
- **High-Speed Startup Caching**: Compiles Oh My Posh themes and CLI tab completions into `$HOME\.cache\powershell\` for silent sub-second startup.

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
| `ll` | List directory contents with details (`ls -alFh --color=auto`) |
| `la` | List all files including hidden (`ls -AFhl --color=auto`) |
| `fs` | Fast recursive directory tree search (`fd --no-ignore-vcs` + `Format-PathTree`) |
| `Format-PathTree` | Native trie-based visual tree formatter (*parity with Linux `tree --fromfile`*) |

### 4. Native CLI Utilities (`bin/`)
Ported from `home-settings/common-bin/` for native PowerShell and cmd execution:

| Utility | Description | Example Usage |
| :--- | :--- | :--- |
| `gen-passwd` | Cryptographically secure random password generator | `gen-passwd -Length 24 -IncludeSymbols` |
| `repeat-until-success` | Retries a command until exit code 0 | `repeat-until-success -Command "curl https://example.com"` |
| `sum` | Sums numbers from positional arguments or pipeline | `sum 1 2 3` or `1..100 \| sum` |

*Note: All utilities in `bin/` include `.cmd` wrappers and are registered as global cmdlets.*

### 5. Solarized Dark & MesloLGS NF Windows Terminal (`terminal/settings.json`)
- Canonical Solarized Dark color scheme.
- MesloLGS NF font pre-configured for powerline glyphs.
- Custom keybindings (`Ctrl+C` copy, `Ctrl+V` paste, `Alt+Shift+D` split pane).

### 6. Vim & Plugin Setup (`vim/_vimrc`)
- Pre-configured `_vimrc` matching `home-settings` with Solarized Dark theme.
- Automated Pathogen bundle provisioning (`auto-pairs`, `vim-colors-solarized`, `ultisnips`, `supertab`).
- Automatic user PATH registration for Vim.

---

## Directory Overview

| Path | Description |
| :--- | :--- |
| `setup.ps1` | Master setup script orchestrating fonts, prompt, completions, PATH, terminal, and vim |
| `bin/` | Native CLI utilities and batch wrappers (`gen-passwd`, `repeat-until-success`, `sum`) |
| `colors/` | Solarized Dark `LS_COLORS` definition database matching `home-settings` |
| `completions/` | Tab completions with high-speed disk caching (`gh`, `winget`, `docker`, `kubectl`, `helm`, `terraform`) |
| `fonts/` | Downloads and installs MesloLGS NF fonts |
| `packages/` | Workstation developer tool provisioning with `winget` (`fzf`, `rg`, `fd`, `jq`, `terraform`, `nvim`) |
| `posh/p10k.omp.json` | Oh My Posh Solarized Dark single-line Powerlevel10k theme |
| `posh/Microsoft.PowerShell_profile.ps1` | PowerShell profile (Oh My Posh + Git/Dev aliases + PSReadLine + LS_COLORS + Completions) |
| `posh/posh-setup.ps1` | Installs Oh My Posh via winget, deploys theme & profile |
| `terminal/settings.json` | Windows Terminal configuration & color schemes |
| `terminal/terminal-setup.ps1` | Deploys `settings.json` to Windows Terminal `LocalState` with backups |
| `vim/_vimrc` | Vim configuration file with Solarized Dark and plugin settings |
| `vim/vim-setup.ps1` | Provisions Vim, Pathogen runtime plugins, and deploys `_vimrc` with backups |
| `tests/test_settings.ps1` | Comprehensive automated test suite (92 tests) for CI and local verification |
| `PSScriptAnalyzerSettings.psd1` | Quality gate & linter settings for strict CI validation |
