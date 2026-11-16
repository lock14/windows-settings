# windows-settings

[![CI](https://github.com/lock14/windows-settings/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/lock14/windows-settings/actions/workflows/ci.yml)
[![Security](https://github.com/lock14/windows-settings/actions/workflows/security.yml/badge.svg?branch=main)](https://github.com/lock14/windows-settings/actions/workflows/security.yml)
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)

Workstation setup automation, a 17-theme 24-bit TrueColor palette engine, a Zellij 0.46+ and Neovim Named Pipe RPC terminal IDE and AI agent fleet manager, and shell configurations for Windows 10 and Windows 11.

Host machines require PowerShell 7+ (`pwsh`), Git for Windows, Windows Terminal, and `winget`. Polyglot runtimes and modern CLI utilities are managed declaratively via WinGet DSC (`configuration.dsc.yaml`) and [mise](https://mise.jdx.dev/) (`mise.toml`).

## Table of contents

- [Quick start and installation](#quick-start-and-installation)
  - [Turnkey bootstrap (new machines)](#turnkey-bootstrap-new-machines)
  - [Declarative WinGet configuration (Microsoft DSC v3)](#declarative-winget-configuration-microsoft-dsc-v3)
  - [CLI orchestrator (`setup.ps1`)](#cli-orchestrator-setupps1)
- [Command-line options (`setup.ps1` and `bootstrap.ps1`)](#command-line-options-setupps1-and-bootstrapps1)
- [Architecture overview](#architecture-overview)
- [Integrated development environment and AI workspace](#integrated-development-environment-and-ai-workspace)
  - [IDE workspace keybindings and navigation](#ide-workspace-keybindings-and-navigation)
- [Interactive shells and prompts](#interactive-shells-and-prompts)
- [Developer toolchains and modern CLI suite](#developer-toolchains-and-modern-cli-suite)
  - [Color theme management (`theme`)](#color-theme-management-theme)
- [Extensibility and customization](#extensibility-and-customization)
- [Git and shell shortcuts](#git-and-shell-shortcuts)
- [Standalone utilities (`bin/`)](#standalone-utilities-bin)
- [Development and testing](#development-and-testing)
- [Contributing, security, and license](#contributing-security-and-license)

## Quick start and installation

Provision a new machine via the single-command remote bootstrapper, apply the declarative Microsoft DSC manifest, or invoke `setup.ps1` directly with modular flags.

### Turnkey bootstrap (new machines)

Stream and run directly in PowerShell 7 (`pwsh`) without pre-cloning:

```powershell
irm https://raw.githubusercontent.com/lock14/windows-settings/main/bootstrap.ps1 | iex
```

### Declarative WinGet configuration (Microsoft DSC v3)

Provision workstation packages declaratively via Microsoft DSC:

```powershell
winget configure .\configuration.dsc.yaml
```

### CLI orchestrator (`setup.ps1`)

Clone the repository and run `setup.ps1` to configure user dotfiles, select an initial theme, preview changes in dry-run mode, or cleanly uninstall managed files:

```powershell
git clone https://github.com/lock14/windows-settings.git
cd windows-settings

# Full automated bootstrap
.\setup.ps1 -Bootstrap

# User dotfiles only with a specific initial palette (or -Theme holiday)
.\setup.ps1 -DotfilesOnly -Theme solarized-dark

# Preview actions without modifying system state
.\setup.ps1 -DryRun

# Remove deployed dotfiles, module, fragments, fonts, and PATH entries
.\setup.ps1 -Uninstall
```

## Command-line options (`setup.ps1` and `bootstrap.ps1`)

`setup.ps1` and `bootstrap.ps1` accept modular switches to provision packages, deploy dotfiles, choose an initial color scheme, preview operations, or uninstall managed artifacts:

| Option | Default | Description |
| :--- | :--- | :--- |
| `-Bootstrap` | `disabled` | Full machine bootstrap (packages, fonts, themes, prompt, PowerShell module, terminal, and Neovim) |
| `-DotfilesOnly` | `disabled` | Configure user dotfiles, fonts, themes, Neovim, terminal, and shell module without installing packages |
| `-SystemOnly` | `disabled` | Provision `winget` packages and CLI tools only |
| `-UseDSC` | `disabled` | Provision workstation packages using the declarative WinGet DSC manifest (`configuration.dsc.yaml`) |
| `-Theme <slug\|holiday>` | `solarized-dark` | Apply initial TrueColor theme across all tools (`solarized-dark`, `catppuccin-mocha`, `holiday`, and others) |
| `-DryRun` | `disabled` | Preview setup or uninstall actions without modifying the system |
| `-WithGUI` or `-IncludeGUI` | `disabled` | Install GUI desktop applications (VS Code, Windows Terminal, and Docker Desktop via `winget`) |
| `-Uninstall` | `disabled` | Remove all deployed dotfiles, module, terminal fragments, fonts, and `bin/` `PATH` entry |
| `-UninstallDotfiles` | `disabled` | Remove deployed dotfiles, PowerShell module, `cmd.exe` AutoRun, and Windows Terminal fragment only |
| `-UninstallFonts` | `disabled` | Remove installed MesloLGS Nerd Font Mono files and registry entries only |
| `-UninstallBin` | `disabled` | Remove repository `bin/` directory from User `PATH` only |
| `-SkipPackages` | `disabled` | Skip `winget` package installation |
| `-SkipFonts` | `disabled` | Skip MesloLGS Nerd Font Mono installation |
| `-SkipPosh` | `disabled` | Skip Oh My Posh, theme engine, and PowerShell module configuration |
| `-SkipCMD` | `disabled` | Skip Windows Command Prompt (`cmd.exe`) AutoRun and `doskey` configuration |
| `-SkipCompletions` | `disabled` | Skip CLI argument completions registration |
| `-SkipTerminal` | `disabled` | Skip Windows Terminal settings and JSON Fragment deployment |
| `-SkipVim` | `disabled` | Skip Neovim and standalone Vim configuration |
| `-SkipBin` | `disabled` | Skip adding `bin/` directory to User `PATH` |

## Architecture overview

<p align="center">
  <img src="assets/prompt.png" alt="Oh My Posh prompt and eza directory tree" width="850">
  <br>
  <em>Oh My Posh Powerline shelf prompt, predictive IntelliSense, and <code>eza</code> directory tree</em>
</p>

<p align="center">
  <img src="assets/bat.png" alt="24-bit TrueColor syntax highlighting via bat" width="850">
  <br>
  <em>24-bit TrueColor syntax highlighting and Git gutter integration via <code>bat</code> (<code>b</code>)</em>
</p>

<p align="center">
  <img src="assets/nvim.png" alt="Neovim in Solarized Dark with Native LSP" width="850">
  <br>
  <em>Lua Neovim in Solarized Dark with Native LSP, <code>render-markdown.nvim</code>, and Tree-sitter AST highlighting</em>
</p>

The repository is organized into declarative package manifests (`configuration.dsc.yaml` and `mise.toml`), idempotent orchestrators (`setup.ps1` and `bootstrap.ps1`), dual-execution CLI utilities (`bin/`), tool and theme configurations (`config/`), an autoloaded PowerShell module (`module/`), a 40-language validation corpus (`sample-code/`), and an automated verification suite (`tests/`):

```text
windows-settings/
├── configuration.dsc.yaml         # WinGet DSC v3 declarative machine configuration
├── mise.toml                      # Declarative polyglot toolchains and CLI tools (Go, Java, Node, Python, Rust, Lean, CLI suite)
├── bootstrap.ps1                  # Turnkey one-liner bootstrapper
├── setup.ps1                      # Declarative master setup engine (-Theme, -Uninstall*, diff backup, -DryRun)
├── llms.txt                       # Concise LLM-oriented architecture and CLI index
├── CONTRIBUTING.md                # Contributor guide, multi-file contracts, and verification checklist
├── SECURITY.md                    # Vulnerability reporting policy
├── LICENSE                        # Apache License 2.0
│
├── .github/                       # CI and Security workflows, Dependabot, PR and YAML Issue templates
│
├── assets/                        # Showcase media and documentation diagrams
│
├── bin/                           # 7 dual-execution CLI utilities (.ps1 and .cmd):
│                                  #   gen-passwd, ide, install-nerd-fonts, repeat-until-success, sum, theme, update-system
│
├── config/                        # Unified declarative tool, theme, and editor configurations
│   ├── bat/                       # 24-bit TrueColor bat themes and standalone Sublime syntaxes
│   │   ├── themes/                # 17 TrueColor .tmTheme palettes (9 classic and 8 US Holiday)
│   │   └── syntaxes/              # 37 standalone Sublime Text and bat syntax grammars
│   ├── btop/                      # btop4win config (btop.conf) and 17 TrueColor themes
│   ├── clangd/                    # C and C++ language server configuration (config.yaml)
│   ├── cmd/                       # Native cmd.exe AutoRun, Powerline shelf prompt, and doskey macros (autorun.cmd, macros.doskey)
│   ├── colors/                    # 40-language calibrated GNU dircolors (LS_COLORS)
│   ├── git/                       # TrueColor Git delta diff viewer config (delta.gitconfig)
│   ├── nvim/                      # Lua Neovim 0.11+ and 0.12+ (Native LSP, Named Pipe RPC, :Theme)
│   │   ├── init.lua               # Native LSP, 17-theme engine, mini.files, render-markdown, IDE RPC
│   │   ├── lazy-lock.json         # Pinned Lazy.nvim plugin lockfile
│   │   ├── ftplugin/              # Per-filetype enhancements (java.lua)
│   │   ├── queries/               # 13 custom base Tree-sitter AST queries
│   │   └── after/queries/         # 30 Tree-sitter AST query extensions (43 .scm files total)
│   ├── powershell/                # PowerShell profile and Oh My Posh theme (p10k_single_line.omp.json)
│   ├── tealdeer/                  # Rust tldr client configuration (config.toml)
│   ├── terminal/                  # Windows Terminal JSON Fragment and settings (17 schemes and Alt+* pass-through)
│   ├── themes/                    # 17 canonical .theme palette specifications (9 classic and 8 US Holiday)
│   ├── vim/                       # Standalone zero-dependency 17-theme Vim configuration (_vimrc)
│   └── zellij/                    # Declarative Zellij 0.46+ config, Inverted-T layouts, and TrueColor theme
│
├── module/                        # Autoloaded WindowsSettings PowerShell module (sub-10ms warm startup)
│   ├── WindowsSettings.psd1       # Module manifest (v3.0.0, 82 exported functions)
│   ├── WindowsSettings.psm1       # Root loader (theme sync, async PR badge cache, *.d/ drop-ins, FZF)
│   ├── Completions.ps1            # Dynamic CLI tab completions
│   ├── Developer.ps1              # IDE RPC wrappers (v, icd, qide), theme, and polyglot shortcuts
│   ├── Git.ps1                    # Git shortcuts and safety guards (gprune vs gpurge, gsync, guser-branch)
│   ├── Navigation.ps1             # Directory navigation and tree search (eza, ls, zoxide, fs)
│   └── Utilities.ps1              # Core shell utilities (b, ds, btop, update)
│
├── plugin/
│   └── ws-bar/                    # Rust wasm32-wasip1 1-line BASE02 Zellij IDE top-bar plugin
│
├── sample-code/                   # 40-language polyglot sample suite for syntax and AST query validation
│
└── tests/
    └── test_settings.ps1          # 256+ automated tests across all 8 test modules
```

## Integrated development environment and AI workspace

The repository provides a multi-session terminal IDE (`bin/ide.ps1` and `bin/ide.cmd`) built on Zellij `0.46+` (`config/zellij/`) and a live Neovim Named Pipe RPC server (`\\.\pipe\nvim-ide-<session>`), with an automatic Windows Terminal split-pane fallback (`--backend wt`).

- **Spatial window geometry and background sessions**:
  - **3-pane layout**: Launched by default via `ide`, `ide3`, or `ide --3pane` as a frameless Inverted-T workspace beneath a 1-line `BASE02` IDE top shelf (`windows-settings-bar`, falling back automatically to Zellij's built-in `compact-bar` when Rust is unavailable), placing the AI Agent (`agy`, `claude`, or `codex`) at top-left, the Neovim Editor at top-right (automatically opening `README.md` when present in the launch directory), and a full-width PowerShell terminal across the bottom.
  - **2-pane layout**: Launched via `ide2` or `ide --2pane` with side-by-side AI Agent and full-height Neovim Editor panes.
  - **Interactive 1-line IDE top shelf**: Displays the session pill on the left (with automatic holiday icons during US Holiday themes and a workspace subdirectory pill when `icd` diverges from the session root), clickable intra-tab `AI`, `Editor`, and `Shell` role indicators plus active `ZOOM` and extra tab pills in the center, and cross-session attention, fleet count, `Monitor`, and `Help` pills on the right. Clicking an already-focused role pill bounces back to the previous pane, while entering any modal Zellij input mode such as `Tmux`, `Resize`, or `Scroll` replaces the right shelf with contextual key hints.
  - **Detached fleet and GPU desktop app**: `ide -d <dir>` (`--detach`) spawns background agent sessions (`zellij attach --create-background`), while `Ctrl+b d` detaches without stopping running processes. `ide --desktop [dir]` launches Zellij's 1-hop GPU desktop app (`zellij terminal`) with a native OS system tray badge and desktop notifications.
- **Unified attention tracking and fleet switcher**:
  - Tracks live `OSC 7501` agent lifecycle states (`running`, `approval`, `quota`, `done`, `idle`) across Claude Code, Codex, and Antigravity (`agy` via `$HOME\.gemini\config\hooks.json`).
  - Press `Alt+s`, `Ctrl+b s`, or `Space s` inside Neovim (or run `ide -s` from any shell) to toggle the floating `fzf` IDE Fleet Switcher across both active and saved workspaces, complete with a live ANSI AI pane viewport preview on the right (or recent Git commits for stopped sessions), `<branch>@<N>` pull request badges, shared-worktree warnings, and hotkeys for `Ctrl+n` (`zoxide` directory launch), `Ctrl+o` (`--open-pr`), `Ctrl+y` (`--ack-ai`), `Ctrl+x` (`--quit` with unsaved-buffer checks), and `Ctrl+a`, `Ctrl+e`, or `Ctrl+t` role focus. Press `Alt+Shift+S` or `Ctrl+b S` (`ide --next-attention`) to jump directly to the next agent waiting for input, or `Ctrl+b w` for Zellij's native `session-manager` dialog.
- **4-layer keybinding and RPC architecture**:
  - **Layer 1 (app-local)**: Preserves standard `Ctrl` bindings inside shells, AI CLIs, and Neovim (`Ctrl+h/j/k/l` move across internal Neovim splits, `Ctrl+j/k` navigate Telescope results, and `<Home>` toggles between first non-blank character `^` and column `0`), while Windows Terminal forwards `Alt+*` chords cleanly to Zellij.
  - **Layer 2 (workspace navigation)**: `Alt+h/j/k/l` move focus across panes, `Alt+a`, `Alt+e`, and `Alt+t` focus or bounce the AI Agent, Editor, or Shell pane via the WASM role router, `Alt+Shift+E` and `Alt+Shift+T` park or restore the Editor or Shell pane (`--toggle-editor`, `--toggle-term`), `Alt+Left/Down/Up/Right` resize panes, `Alt+z` toggles pane zoom, `Ctrl+b r` refreshes all running IDE sessions (`ide --refresh`), `Alt+m` opens the floating system monitor (`ide --monitor`), `Alt+?` opens the keybinding cheatsheet (`ide --keys`), and right-clicking the top bar, tab, or any pane opens an IDE workspace `context_menu` with auto-resolved shortcut hints.
  - **Layer 3 (editor, file explorer, and RPC context dispatch)**: Inside the shell, `v [+line|+cmd] [-c cmd] [--] <file>...` opens one or more files directly in the session's Neovim pane over Named Pipe RPC while healing stale working directories, and `icd [dir]` (or `:IdeCd [dir]` in Neovim) synchronizes the working directory across shell, editor, and top shelf. Inside Neovim, `-` or `Space e` opens `mini.files`, visual-mode `Space a`, normal-mode `Space il`, `Space id`, and `:IdeSend[!]` stage sanitized references or diagnostics directly into the AI Agent prompt (`ide --send`) without overwriting the system clipboard, `Space m` toggles `render-markdown.nvim`, and `:Q`, `Alt+q`, `qide`, and `quit` (`ide --quit`) verify all Neovim buffers are saved before closing the session (`idek` or `ide --kill` force-closes).
  - **Layer 4 (links, jumplist, and clipboard)**: `gx` and `Ctrl+Click` follow Markdown links, `#heading` anchors, relative paths, and URLs, falling back to LSP definition jumps, while mouse back and forward buttons (`<X1Mouse>` and `<X2Mouse>`) traverse the Neovim jumplist.
- **LSP, Tree-sitter, and standalone Vim**:
  - **Native LSP**: Configured in `config/nvim/init.lua` via `vim.lsp.config` and `vim.lsp.enable` for Go (`gopls`), Python (`pyright`), TypeScript (`ts_ls` with automatic `tsserver.js` discovery), Rust (`rust_analyzer`), C and C++ (`clangd`), Bash (`bashls`), JSON (`jsonls`), Terraform (`terraformls`), YAML (`yamlls`), Lean 4 (`leanls`), and Java (`ftplugin/java.lua`), backed by declarative `npm:*` language server entries in `mise.toml` and non-blocking `cmdheight=1` Mason notification truncation.
  - **Tree-sitter and fallback Vim**: 43 custom `.scm` queries (`queries/` and `after/queries/`) align highlighting with `bat`, and `config/vim/_vimrc` provides a zero-dependency 17-theme `:Theme` and Smart-Home fallback when Neovim is unavailable.

### IDE workspace keybindings and navigation

The following table indexes keyboard shortcuts, editor commands, shell wrappers, and CLI flags across the IDE workspace:

| Keybinding or action | Context | Description |
| :--- | :--- | :--- |
| `Alt+h/j/k/l` | Universal | Move focus across Zellij panes and Neovim splits |
| `Ctrl+h/j/k/l` | Neovim normal | Move focus across internal Neovim splits (`Ctrl+j/k` move through Telescope results) |
| `Alt+a`, `Alt+e`, or `Alt+t` | Universal | Focus or bounce the AI Agent, Editor, or Shell pane via WASM role routing (`Alt+;` bounces back) |
| `Alt+Shift+E` or `Alt+Shift+T` | Universal | Park or restore the Editor (`--toggle-editor`) or Shell (`--toggle-term`) pane |
| `Alt+s`, `Ctrl+b s`, or `Space s` | Universal | Toggle floating `fzf` IDE Fleet Switcher with live AI pane preview across active and saved sessions (`ide -s`; `Ctrl+b w` opens raw `session-manager`) |
| `Alt+Shift+S` or `Ctrl+b S` | Universal | Jump to the next workspace waiting for AI attention (`ide --next-attention`) |
| `Space a`, `Space il`, or `Space id` | Neovim | Stage visual `@file#L1-L2` reference, current line, or buffer diagnostics into the AI Agent prompt (`ide --send`) |
| `<Home>` | Neovim or Vim | Toggle cursor between first non-blank character (`^`) and column 1 (`0`) across normal, visual, select, and insert modes |
| `Alt+Left/Down/Up/Right` | Zellij | Resize the active pane directionally |
| `Alt+z` | Zellij | Toggle full-window zoom on the active pane |
| `Ctrl+b r` | Zellij | Hot-reload active theme, cheatsheet cache, WASM top bar, and Neovim RPC state across live sessions (`ide --refresh`) |
| `Alt+m` or `Ctrl+b m` | Universal | Toggle floating system monitor (`ide --monitor` using `btop4win` or built-in TUI fallback) |
| `Alt+?` or `Ctrl+b ?` | Universal | Open TrueColor IDE keybinding cheatsheet (`ide --keys`) |
| `Left-click` (top-bar pills) | Zellij | Focus or bounce `AI`, `Editor`, or `Shell` panes, toggle `ZOOM`, or toggle the `IDE Fleet Switcher`, `Monitor`, or `Help` modals |
| `Right-click` (bar, tab, or pane) | Zellij | Open IDE workspace context menu (`Focus AI/Editor/Shell`, `IDE fleet switcher`, `Refresh all sessions`, `Monitor`, `Keys`, `Quit`) |
| `Ctrl+b d` | Zellij | Detach from the current workspace while keeping agents and Neovim running |
| `-` or `Space e` | Neovim normal | Open `mini.files` explorer at the active buffer directory |
| `Space ff` or `Space fg` | Neovim normal | Find files (`Space ff`) or live grep (`Space fg`) via Telescope |
| `Space m` | Neovim normal | Toggle in-buffer Markdown rendering (`render-markdown.nvim`) |
| `gd`, `gr`, or `K` | Neovim LSP | Go to definition (`gd`), find references (`gr`), or show hover documentation (`K`) |
| `gx` | Neovim normal | Follow Markdown link, `#heading` anchor, file path, or URL under cursor |
| `<X1Mouse>` or `<X2Mouse>` | Neovim | Step backward or forward in the Editor jumplist |
| `:IdeCd [dir]` or `icd [dir]` | Neovim or shell | Synchronize working directory across Editor, Shell, and top bar (`icd ~` resets root) |
| `v [+line\|+cmd] [-c cmd] <file>...` | Shell | Open one or more files in the active IDE Neovim pane over Named Pipe RPC |
| `:Q`, `Alt+q`, `qide`, or `quit` | Universal | Quit the IDE workspace after checking Neovim for unsaved buffers (`ide --quit`) |
| `:Q!`, `idek`, or `ide --kill` | Neovim or shell | Force-close the active or named IDE workspace without checking unsaved buffers |
| `ide [dir]`, `ide3`, or `ide2` | Shell | Launch or attach to a 3-pane Inverted-T (`--3pane`) or 2-pane (`--2pane`) workspace |
| `ide -d <dir>` or `ide --detach <dir>` | Shell | Spawn a detached background IDE session for `<dir>` |
| `ide --desktop [dir]` | Shell | Launch the workspace inside Zellij's native 1-hop GPU desktop app (`zellij terminal`) |
| `ide --ai <agy\|claude\|codex>` | Shell | Select the AI coding agent CLI (overriding `$env:IDE_AI_CLI`) |
| `ide --open-pr [session]` | Shell | Open the session's active GitHub pull request or GitLab merge request in the default browser |
| `ide --agent-state <state> [session]` | Shell or hook | Record lifecycle state (`running`, `approval`, `quota`, `done`, `idle`) and emit `OSC 7501` |
| `ide --swap <left\|down\|up\|right>` | Shell | Swap the active pane directionally inside the workspace |
| `ide --refresh [--dry-run]` | Shell | Re-apply active theme and synchronize live Zellij top bars and Neovim RPC sessions |
| `ide --list [--plain]` | Shell | List active IDE sessions sorted by urgency with `<branch>@<N>` metadata (`--plain` prints session names) |
| `ide --backend <zellij\|wt>` | Shell | Select Zellij multiplexer (default) or Windows Terminal split-pane backend |

## Interactive shells and prompts

Interactive PowerShell and Command Prompt sessions are configured for low startup latency, predictive completion, and visual parity:

- **PowerShell module**: `WindowsSettings` is deployed to `$HOME\Documents\PowerShell\Modules\WindowsSettings` and imported via a 1-line `$PROFILE` (`Import-Module WindowsSettings -DisableNameChecking -ErrorAction SilentlyContinue`), compiling `oh-my-posh`, `mise` binary paths, `zoxide`, `gh` completion, and `theme_env.ps1` initializers to `$HOME\.cache\powershell\` for fast warm startup.
- **Single-line Oh My Posh shelf prompt**: Configured in `config/powershell/p10k_single_line.omp.json`:
  - Renders via a persistent streaming daemon on the active theme's `BASE02` shelf (`#073642` in Solarized Dark) with the OS icon in calm `BASE0` (shifting automatically to seasonal glyphs when a US Holiday theme is active).
  - Resolves and caches GitHub and GitLab pull and merge request numbers asynchronously in the background, rendering clickable OSC 8 `<branch>@<N>` badges next to the Git branch without blocking prompt redraws.
  - Anchors right-prompt command status (Green on success and Red on error) alongside execution duration, active language toolchains, and cloud context.
- **Windows Command Prompt AutoRun**: `config/cmd/autorun.cmd` and `config/cmd/macros.doskey` are deployed to `%LOCALAPPDATA%\cmd\` and registered in `HKCU\Software\Microsoft\Command Processor\AutoRun` to enable UTF-8 (`chcp 65001`), `COLORTERM=truecolor`, `FORCE_HYPERLINK=1`, `JQ_COLORS`, dynamic `theme_env.cmd` and `mise_paths.cmd` hooks, and single-load `doskey /macrofile` shortcut parity.

## Developer toolchains and modern CLI suite

- **Syntax-highlighted file viewer and raw concatenation**: `b` invokes `bat` with 17 `.tmTheme` palettes, 37 standalone `.sublime-syntax` grammars, Git gutter markers, and italic comments, while `cat` runs unwrapped `uutils-coreutils` `cat.exe`.
- **Git diff viewer**: `delta` renders TrueColor syntax-highlighted Git diffs (`config/git/delta.gitconfig`) linked into global `.gitconfig` and updated dynamically by `theme`.
- **Directory listings**: `eza` provides 24-bit TrueColor `EZA_COLORS` (`e`, `el`, `elm`, `et`, `elt`, `elx`) alongside 40-language calibrated `LS_COLORS` (`ls`, `ll`, `la`, `l`).
- **Modern CLI utilities**: `dust` (`ds`), `sd`, `yq`, `jq`, `tealdeer` (`tldr`), `btop4win` (`btop`), `glow`, `zoxide` (`z`, `zi`), and `fzf` (`Ctrl+R`), provisioned via `configuration.dsc.yaml` and `mise.toml`.
- **Zero-touch Windows Terminal Fragment**: `config/terminal/windows-settings.json` deploys all 17 TrueColor schemes, `MesloLGS Nerd Font Mono`, and clean `Alt+*` pass-through without overwriting user profiles in base `settings.json`.

### Color theme management (`theme`)

The `theme` utility (`bin/theme.ps1` and `bin/theme.cmd`) switches the active color scheme across Zellij, Windows Terminal, Neovim (live Named Pipe RPC), Vim, PowerShell and PSReadLine, Oh My Posh, `cmd.exe`, `bat`, `delta`, `btop4win`, `tealdeer`, `fzf`, `eza`, `jq`, `LS_COLORS`, and live terminal OSC 4, 10, 11, and 12 slots:

- **Classic developer palettes (9)**: `solarized-dark` (default), `solarized-light`, `catppuccin-mocha`, `catppuccin-latte`, `gruvbox-dark`, `tokyonight-night`, `kanagawa-wave`, `nord`, and `onedark`.
- **US Holiday palettes (8)**: `new-years`, `valentines`, `st-patricks`, `easter`, `independence-day`, `halloween`, `thanksgiving`, and `christmas`.
- **Custom user themes**: Scaffold a custom `.theme` specification in `$HOME\.config\windows-settings\themes\` with `theme --create <slug> --from <base>` to include it in `theme --list`, `:Theme` completion, and interactive `fzf` previews.

| Command | Description |
| :--- | :--- |
| `theme` | Open interactive `fzf` picker with live TrueColor swatch and syntax preview |
| `theme <slug>` | Switch terminal emulators, Zellij, Neovim, Vim, prompts, and CLI tools to `<slug>` |
| `theme --holiday` | Switch to the active or nearest upcoming US Holiday theme |
| `:Theme [slug\|--holiday]` | View or switch the active color theme inside Neovim or standalone Vim |
| `theme --list [--plain]` | List all built-in and custom themes (`--plain` prints raw theme slugs) |
| `theme --current` | Print the currently active theme slug |
| `theme --preview <slug>` | Render a TrueColor 16-color swatch and syntax preview without switching |
| `theme --create <slug> [--from <base>]` | Scaffold a custom user theme in `$HOME\.config\windows-settings\themes\<slug>.theme` |
| `theme --sync-assets` | Regenerate static `bat`, `btop`, and Windows Terminal theme assets from `.theme` files |
| `theme --dry-run <slug>` | Preview all configuration updates for `<slug>` without modifying files |

## Extensibility and customization

Keep machine-local or private settings in untracked drop-in hooks so repository updates remain conflict-free:

- `$HOME\.config\windows-settings\env.d\*.ps1`: Local PowerShell environment variables and `PATH` additions.
- `$HOME\.config\windows-settings\aliases.d\*.ps1`: Local PowerShell aliases.
- `$HOME\.config\windows-settings\functions.d\*.ps1`: Local PowerShell functions.
- `$HOME\.config\windows-settings\cmd.d\*.cmd`: Local `cmd.exe` AutoRun drop-in scripts and `doskey` macros.
- `$HOME\.config\windows-settings\themes\*.theme`: Custom user 24-bit TrueColor theme definitions.
- `$HOME\.gemini\config\hooks.json`: Antigravity lifecycle hooks forwarding `SessionStart`, `PreInvocation`, and `Stop` events to `ide.cmd --agy-hook` for Zellij `OSC 7501` attention badges.
- `$HOME\.claude\settings.json` and `$HOME\.codex\config.toml`: Optional external fleet hooks forwarding Claude Code JSON `stdin` (`ide.cmd --agent-state approval` on `Notification` and `ide.cmd --agent-state done` on `Stop`) or Codex trailing JSON notifications (`notify = ["ide.cmd", "--agent-state", "done"]`) into the session state cache.

## Git and shell shortcuts

Functions and aliases in `module/` (mirrored as `doskey` macros in `config/cmd/macros.doskey`) provide shortcuts for navigation, IDE control, directory listings, Git workflows, and polyglot builds:

| Shortcut | Description |
| :--- | :--- |
| `Ctrl+R` | Fuzzy search command history via `fzf` (with PSReadLine fallback when `fzf` is absent) |
| `z <dir>` or `zi` | Jump to frecency-ranked directory via `zoxide` (`zi` opens interactive picker) |
| `b <file>` | View file with TrueColor syntax highlighting and Git gutter via `bat` |
| `cat <file>` | Concatenate files raw without paging or line numbers via `uutils-coreutils` `cat` |
| `theme [slug]` | Open interactive `fzf` theme picker or switch all tools to `<slug>` |
| `ide`, `ide3`, or `ide2` | Launch or attach to a 3-pane Inverted-T or 2-pane Zellij and Neovim IDE workspace |
| `v [+line\|+cmd] [-c cmd] <file>...` | Open one or more files in the active IDE Neovim pane over Named Pipe RPC (falls back to local `nvim`) |
| `icd [dir]` | Synchronize working directory across current shell and active IDE Neovim server |
| `qide`, `quit`, or `idek` | Safely quit IDE workspace after checking unsaved buffers (`idek` force-kills) |
| `vi` or `vim` | Launch `nvim` (falling back to standalone `vim` when `nvim` is absent) |
| `ds` | Analyze directory disk usage via `dust` |
| `btop` | Launch interactive TrueColor system monitor (`btop4win`) |
| `update` | Update `winget`, `mise`, PowerShell modules, toolchains, Neovim plugins, and tool caches (`update-system`) |
| `ls`, `ll`, `la`, or `l` | Coreutils directory listings styled with TrueColor `LS_COLORS` |
| `e`, `el`, `elm`, `et`, `elt`, or `elx` | `eza` listings with Nerd Font icons, Git status, ISO timestamps, and tree views |
| `fs [pattern]` | Recursive directory tree search combining `fd` and `Format-PathTree` |
| `gco`, `gcb`, or `gcm` | `git checkout`, `git checkout -b`, or switch to primary branch (`main`, `master`, or `trunk`) |
| `ga` or `gaa` | `git add` or `git add --all` |
| `gst` or `gss` | `git status` or short `git status -s` |
| `gd` or `gds` | `git diff` or `git diff --staged` rendered through `delta` |
| `gl` or `gp` | `git pull --rebase --autostash` or `git push` (auto-sets `-u origin HEAD` on new branches) |
| `gb`, `gba`, or `gbd` | List local branches, list all branches, or delete merged branch (`git branch -d`) |
| `gsta`, `gstp`, or `gstl` | Push, pop, or list Git stashes |
| `glog` or `glo` | Graph commit log (`git log --graph`) or compact one-line log (`git log --oneline`) |
| `grb`, `grbc`, or `grba` | Start, continue, or abort interactive or branch rebase |
| `gcommit` or `gamend` | Stage all changes and commit, or stage all and `--amend --no-edit` |
| `gup` | Fetch with `--prune` and pull with `--rebase --autostash` |
| `gprune` | Delete local branches already merged into the primary branch (`git branch -d`) |
| `gpurge` | Force-delete unmerged local branches (`git branch -D`) after confirmation |
| `gsync` | Verify clean working tree, fetch, and rebase current branch onto `origin/main` or `origin/master` |
| `guser-branch` | Prefix feature branch with `$USER/` (refuses `main` or `master` and strips duplicate prefixes) |
| `go-testall`, `go-buildall`, or `go-lint` | Run `go test ./...`, `go build ./...`, or `golangci-lint run` |
| `tf` or `yaml-lint` | Run `terraform` or `yamllint` |

## Standalone utilities (`bin/`)

Every utility in `bin/` ships as a PowerShell script (`<name>.ps1`) paired with a `cmd.exe` wrapper (`<name>.cmd`) registered on the User `PATH` by `setup.ps1`:

| Utility | Key options and arguments | Description |
| :--- | :--- | :--- |
| `gen-passwd` | `-Length <int>`, `-Count <int>`, `-NoSymbols` | Generate cryptographically random passwords using `RandomNumberGenerator` |
| `ide` | `--3pane`, `--2pane`, `--ai <cli>`, `-d, --detach`, `--desktop`, `-s, --sessions`, `--next-attention`, `--toggle-editor`, `--toggle-term`, `--swap <dir>`, `--open [+line] <file>`, `--preview <file>`, `--cd <dir>`, `--send [--stdin\|--ref\|--text] [--switch]`, `--agent-state <state>`, `--open-pr`, `--refresh`, `--monitor`, `--keys`, `--quit`, `--kill`, `--list [--plain]`, `--backend <zellij\|wt>`, `--dry-run`, `[dir]` | Launch and manage Zellij `0.46+` and Neovim Named Pipe RPC workspaces and AI coding agent sessions |
| `install-nerd-fonts` | `-FontName <name>`, `-DryRun` | Download and register MesloLGS Nerd Font Mono faces in user font settings |
| `repeat-until-success` | `-MaxAttempts <int>`, `-DelaySeconds <int>`, `<command>` | Re-run a command until it exits `0` or reaches `-MaxAttempts` |
| `sum` | `[numbers...]`, pipeline `stdin` | Accumulate integers and floating-point numbers from arguments or piped input |
| `theme` | `--list [--plain]`, `--current`, `--set <slug>`, `--holiday`, `--preview <slug>`, `--create <slug> [--from <base>]`, `--env`, `--path`, `--sync-assets`, `--no-live`, `--dry-run`, `[slug]` | Synchronize 17 built-in and custom 24-bit TrueColor themes across terminals, multiplexers, editors, prompts, and CLI tools |
| `update-system` | `--system-only`, `--skip-winget`, `--skip-mise`, `--skip-modules`, `--skip-nvim`, `--dry-run` | Update `winget` packages, `mise` runtimes, PowerShell modules, `rustup` and `elan` toolchains, Neovim plugins, `tldr` and `bat` caches, and compiled shell startup caches |

## Development and testing

Run `PSScriptAnalyzer` static analysis and the 8-module validation suite locally before submitting changes:

```powershell
Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
$null | pwsh -NoProfile -File ./tests/test_settings.ps1
```

The test suite executes 256+ automated checks across 8 modules:

1. PowerShell script and module AST syntax validation
2. JSON, KDL, YAML, theme, Tree-sitter query, governance, documentation typography, and manifest validity
3. `WindowsSettings` module import, alias mapping, and 82 function exports
4. Native `bin/` CLI utilities and pipeline input handling
5. Git workflow behavior and branch safety guards (`gsync`, `gprune`, `gpurge`, `guser-branch`)
6. Tab completions, `cmd.exe` AutoRun, and Oh My Posh rendering (including OSC 8 PR badges and live theme cache rotation)
7. Path invariants, byte-level `CRLF` and `LF` line endings, startup hygiene, and `.cmd` batch wrappers
8. Setup orchestrator idempotency, `-DryRun`, `-Theme`, clean `-Uninstall*`, and timestamped backup behavior

## Contributing, security, and license

- **Contributing**: See [CONTRIBUTING.md](CONTRIBUTING.md) for local `-DryRun` testing, multi-file component contracts, and pull request guidelines.
- **Security**: Report vulnerabilities privately per [SECURITY.md](SECURITY.md).
- **License**: Licensed under the [Apache License 2.0](LICENSE).
