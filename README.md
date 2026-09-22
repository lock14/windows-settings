# windows-settings

[![CI](https://github.com/lock14/windows-settings/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/lock14/windows-settings/actions/workflows/ci.yml)

Modern Windows developer workstation configuration and setup automation for **PowerShell 7+**, **Oh My Posh**, **Neovim**, and **Windows Terminal**.

---

## Showcase

<p align="center">
  <img src="assets/prompt.png" alt="Oh My Posh & Modern Directory Trees" width="850">
  <br>
  <em>Oh My Posh Powerline prompt, predictive IntelliSense, and <code>eza</code> directory tree</em>
</p>

<p align="center">
  <img src="assets/bat.png" alt="24-bit TrueColor Syntax Highlighting via bat" width="850">
  <br>
  <em>24-bit TrueColor syntax highlighting and Git gutter integration via <code>bat</code> / <code>cat</code></em>
</p>

<p align="center">
  <img src="assets/nvim.png" alt="Modern Lua Neovim in Solarized Dark with Native LSP" width="850">
  <br>
  <em>Modern Lua Neovim in Solarized Dark with Native LSP (Go, Terraform, Python) and Treesitter AST highlighting</em>
</p>

---

## Architecture Overview

```text
windows-settings/
├── configuration.dsc.yaml         # WinGet DSC v3 declarative machine configuration
├── mise.toml                      # Declarative polyglot toolchains & CLI tools (Java, Go, Python, Node, Rust, Tree-sitter)
├── bootstrap.ps1                  # Turnkey zero-dependency one-liner bootstrapper
├── setup.ps1                      # Declarative master setup engine (diff detection, backup, -DryRun)
│
├── assets/                        # Showcase media and documentation diagrams
│
├── bin/                           # Native CLI utilities (gen-passwd, repeat-until-success, sum)
│
├── config/                        # Unified declarative tool & editor configurations
│   ├── bat/                       # Solarized Dark 24-bit TrueColor bat theme & custom syntaxes
│   │   ├── Solarized-Dark-TrueColor.tmTheme  # 24-bit TrueColor Solarized Dark theme
│   │   └── syntaxes/              # 18 custom Sublime Text / bat syntax grammars
│   ├── colors/                    # Directory colors (LS_COLORS)
│   ├── nvim/                      # Modern Lua Neovim 0.11+ (Native LSP, Tree-sitter AST queries)
│   │   ├── init.lua               # Neovim 0.11+ Native LSP, monochromatic UI, Solarized Dark
│   │   ├── lazy-lock.json         # Pinned Lazy.nvim plugin lockfile
│   │   ├── ftplugin/              # Per-filetype language client enhancements (e.g. java.lua)
│   │   ├── queries/               # Custom base Tree-sitter AST queries (css, html, xml, etc.)
│   │   └── after/queries/         # Tree-sitter query extensions across 17 languages
│   ├── powershell/                # PowerShell profile & Oh My Posh theme (p10k_single_line.omp.json)
│   ├── terminal/                  # Windows Terminal JSON fragment & settings
│   └── vim/                       # Standalone zero-dependency fallback Vim configuration (_vimrc)
│
├── module/                        # Flat WindowsSettings PowerShell Module
│   ├── WindowsSettings.psd1       # Module manifest (61 exported functions)
│   ├── WindowsSettings.psm1       # Module root loader (TrueColor, LS_COLORS, EZA_COLORS, FZF)
│   ├── Completions.ps1            # Native dynamic CLI completions
│   ├── Developer.ps1              # Developer tools & shortcuts
│   ├── Git.ps1                    # Git shortcuts & workflows
│   ├── Navigation.ps1             # Modern navigation & directory tools
│   └── Utilities.ps1              # Core utilities & cmdlets
│
├── sample-code/                   # 20-language polyglot sample suite for syntax highlighting verification
│
└── tests/
    └── test_settings.ps1          # 159 automated tests across all 8 test modules
```

---

## Prerequisites

- **PowerShell 7+** (`pwsh`)
- **Git for Windows**
- **Windows Terminal**
- **winget** (Windows Package Manager, included in Windows 10/11)

---

## Quick Start

### 1. Turnkey Bootstrap (New Machines)

Stream and run directly in PowerShell 7 (`pwsh`) without pre-cloning:

```powershell
irm https://raw.githubusercontent.com/lock14/windows-settings/main/bootstrap.ps1 | iex
```

### 2. Declarative WinGet Configuration (Microsoft DSC v3)

Provision the complete workstation toolchain natively via Microsoft DSC:

```powershell
winget configure .\configuration.dsc.yaml
```

### 3. Automated Master Setup (Existing Clone)

```powershell
git clone https://github.com/lock14/windows-settings.git
cd windows-settings

# Full automated bootstrap
.\setup.ps1 -Bootstrap

# User dotfiles only (module, prompt, nvim, terminal fragments)
.\setup.ps1 -DotfilesOnly

# Preview actions without making system changes
.\setup.ps1 -DryRun
```

### 4. Command-Line Options (`setup.ps1` & `bootstrap.ps1`)

| Option | Default | Description |
| :--- | :--- | :--- |
| `-Bootstrap` | *disabled* | Full new machine bootstrap (packages, fonts, prompt, module, terminal, nvim) |
| `-DotfilesOnly` | *disabled* | Configure user dotfiles, fonts, nvim, terminal, and shell module only (no package install) |
| `-SystemOnly` | *disabled* | Provision winget packages and CLI tools only |
| `-UseDSC` | *disabled* | Provision workstation packages using declarative WinGet DSC manifest (`configuration.dsc.yaml`) |
| `-DryRun` | *disabled* | Preview actions without modifying the system |
| `-WithGUI` / `-IncludeGUI` | *disabled* | Install GUI desktop applications (VS Code, Windows Terminal, Docker Desktop via winget) |
| `-SkipPackages` | *disabled* | Skip winget package installation |
| `-SkipFonts` | *disabled* | Skip MesloLGS Nerd Font Mono installation |
| `-SkipPosh` | *disabled* | Skip Oh My Posh & PowerShell module configuration |
| `-SkipCompletions` | *disabled* | Skip CLI argument completions registration |
| `-SkipTerminal` | *disabled* | Skip Windows Terminal settings & JSON fragment deployment |
| `-SkipVim` | *disabled* | Skip Neovim & Vim configuration |
| `-SkipBin` | *disabled* | Skip adding `bin/` directory to User PATH |

---

## What's Included

### 1. Single-Line Powerlevel10k Prompt (`config/powershell/p10k_single_line.omp.json`)
- Flawless dynamic Powerline transitions powered by **Oh My Posh**.
- **Base02 Shelf Foundation**: Grounded on the **Base02 (`#073642`) dark teal shelf** matching Ethan Schoonover's specification.
- **Calm OS Glyph**: Displayed in calm **Base0 (`#839496`)** on Base02, eliminating glaring high-luminance white.
- **Dynamic Git State Shifting**: Turns **Green** when clean, **Yellow** when modified/staged, **Orange** when diverged, **Cyan** when ahead.
- Left side: OS glyph $\to$ Directory (``) $\to$ Git branch & status.
- Right side (`rprompt`): Persistent status anchor (`` in Solarized Green `#859900` on success, `` in Solarized Red `#DC322F` on error) matching `home-settings` Powerlevel10k, with contextual command execution time (`` in Yellow `#B58900`), toolchains (Node, Go, Python, .NET, Rust), and AWS context unified on the Base02 shelf with solid wedge cap (`\uE0B2`).
- **High-Speed Disk Caching**: Compiles prompt hook into `$HOME\.cache\powershell\omp_init.ps1` for sub-second startup (<10ms).

### 2. First-Class PowerShell Module (`WindowsSettings`)
- Clean autoloaded PowerShell Module (`$HOME\Documents\PowerShell\Modules\WindowsSettings`).
- Clean 1-line `$PROFILE`:
  ```powershell
  Import-Module WindowsSettings
  ```
- Instant updates via `git pull` without modifying or corrupting profile files.

### 3. Modern Rust CLI Developer Toolchain
- **`eza`**: 83-code authentic 24-bit TrueColor Solarized Dark palette (`EZA_COLORS`), Git status, long-ISO timestamps, file group ownership, and tree views (`e`, `el`, `elm`, `et`, `elt`, `elx`).
- **`zoxide` (`z`)**: Frecency-based smart directory jumping.
- **`bat`**: Syntax-highlighted paging with Git modification markers, authentic Solarized Dark TrueColor theme (`Solarized-Dark-TrueColor.tmTheme`), 18 custom standalone syntaxes compiled via `bat cache --build`, and italic comments (`BAT_OPTS = '--italic-text=always'`).
- **`glow`**: Terminal Markdown renderer with Solarized Dark styling.
- **`uutils-coreutils`**: Fast, memory-safe compiled Rust GNU coreutils (`ls`, `ll`, `la`, `l`) strictly rendered with unbolded Solarized `LS_COLORS`.
- **`fzf`**: Interactive fuzzy search (`Ctrl+R`, `Ctrl+T`) styled in TrueColor Solarized Dark, powered by high-speed `ripgrep` (`rg`) and `fd` fallback engines.
- **`PSReadLine`**: Predictive IntelliSense and restrained 24-bit TrueColor syntax highlighting (control flow in Solarized Yellow `#B58900`, commands & primitive types in Solarized Green `#859900`, strings in Cyan `#2AA198`, numbers in Magenta `#D33682`).

### 4. Git & Developer Shortcuts
Includes the full Oh My Zsh Git plugin suite and developer workflow helpers:

| Shortcut | Description |
| :--- | :--- |
| `Ctrl+R` | Interactive fuzzy search command history via `fzf` |
| `z <dir>` | Smart jump to directory via `zoxide` |
| `cat <file>` | Syntax-highlighted file viewing via `bat` |
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
| `guser-branch` | Prefix branch with `$USER/` (stripping redundant prefixes) |
| `go-testall` | `go test ./...` |
| `go-buildall` | `go build ./...` |
| `go-lint` | `golangci-lint run` (with auto-cached configuration) |
| `tf` | `terraform` |
| `vi` / `vim` / `v` | `nvim` (Modern Lua Neovim) |
| `yaml-lint` | `yamllint -c ~/.yamllint.yml` |
| `ls` | Standard directory listing (`ls --color=auto`) |
| `ll` | Detailed directory listing (`ls -alF`) |
| `la` | List all files including hidden (`ls -A`) |
| `l` | Compact column directory listing (`ls -CF`) |
| `e` | Modern directory listing (`eza --icons=auto`) |
| `el` | Detailed directory listing with Git status (`eza -la --git --header --group --time-style=long-iso`) |
| `et` / `lt` | Tree view listing (`eza --tree --level=2`) |
| `elt` | Detailed tree view (`eza -la --tree --level=2 --git --group --time-style=long-iso`) |
| `elm` | Detailed listing sorted by modification date (`--sort=modified`) |
| `elx` | Detailed forensic listing with inode, file sizes, and extended attributes (`-H -i -S --extended`) |
| `fs` | Fast recursive directory tree search (`fd` + `Format-PathTree`) |

### 5. Modern Lua Neovim (`config/nvim/init.lua`)
- Lua-first Neovim configuration with **Lazy.nvim**.
- **Native LSP (`mason.nvim` + `nvim-lspconfig`)**: Neovim 0.11+ / 0.12+ LSP architecture (`LspAttach`, `vim.lsp.config`, `vim.lsp.enable`) managing Go (`gopls`), Terraform (`terraform-ls`), Python (`pyright`), YAML.
- **Tree-sitter AST Queries**: Comprehensive base query supersedures (`queries/`) and runtime overrides (`after/queries/`) across 17 languages for authentic Solarized Dark highlighting.
- **Monochromatic UI Chrome**: Subtle dark borders, calm status lines, and minimal gutter clutter.
- **4-Tier Diagnostic Ladder**: Clear diagnostic distinction (Error Red, Warn Yellow, Info Blue, Hint Cyan).
- **Subtle Dark Diff Tints**: `diffAdd`, `diffDelete`, `diffChange` matching terminal Solarized Dark backgrounds.
- **Telescope**: Fast in-editor fuzzy file finding (`<leader>ff`, `<leader>fg`).
- **Solarized Dark**: Seamless `#002B36` terminal background matching (`maxmx03/solarized.nvim` with `variant = "spring"`).

### 6. Zero-Dependency Fallback Vim (`config/vim/_vimrc`)
- Standalone zero-dependency fallback configuration with self-contained Solarized Dark palette (`s:ApplySolarizedDark`).
- Graceful degradation when running legacy Vim on servers or environments without Neovim.

### 7. Zero-Touch Windows Terminal (`config/terminal/`)
- Native Windows Terminal JSON Fragment extension (`config/terminal/windows-settings.json`).
- Automatically loads Solarized Dark, MesloLGS Nerd Font Mono, and keybindings without ever modifying `settings.json` or conflicting with WSL profiles.

---

## Testing & Quality Gates

Run the automated test suite locally:

```powershell
pwsh -NoProfile -File ./tests/test_settings.ps1
```

Runs **159 automated tests across all 8 modules**:
1. PowerShell Script & Module Syntax
2. JSON, YAML & Manifest Validity (`configuration.dsc.yaml`, `p10k.omp.json`, `settings.json`, fragments)
3. WindowsSettings Module Import & Function Exports (61 functions)
4. Native CLI Utilities & Pipeline Handling (`sum`, `gen-passwd`, `repeat-until-success`)
5. Git Workflow Behavior (`gsync`, `gprune`, `guser-branch`, `fix-abcxyz-branch-name`)
6. Completions & Prompt Rendering
7. Path Invariants & Dual Execution Wrappers
8. Setup Script Idempotency, DryRun & Backup Policy

