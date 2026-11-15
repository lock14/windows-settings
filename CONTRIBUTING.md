# Contributing to windows-settings

This document outlines the architectural invariants, multi-file component contracts, local development workflow, verification requirements, and pull request conventions for `github.com/lock14/windows-settings`.

## Core architectural and safety principles

All contributions must respect the repository invariants:

* **Portability and zero personal paths**: Never commit personal user directories or machine-specific paths such as `C:\Users\<username>\`, `/Users/<username>/`, or `/home/<username>/`. Always use canonical PowerShell and Windows environment variables (`$HOME`, `$env:USERPROFILE`, `$env:LOCALAPPDATA`, `$env:APPDATA`, `$PROFILE`) and construct paths with `Join-Path` and `Split-Path`.
* **Strict line-ending discipline**:
  * `.ps1`, `.psm1`, `.psd1`, `.cmd`, and `.bat` files use `CRLF` (`\r\n`) line endings because `cmd.exe` miscalculates byte offsets after `chcp 65001 >nul` if a batch script uses `LF`.
  * `.md`, `.json`, `.kdl`, `.yml`, `.yaml`, `.toml`, `.lua`, `.scm`, `.theme`, `.tmTheme`, `.sublime-syntax`, `.gitconfig`, `.conf`, `.txt`, and `LICENSE` files use `LF` (`\n`) line endings.
* **Non-destructive backups, idempotency, and dry-run support**:
  * Provisioning and uninstall flows (`setup.ps1`, `bootstrap.ps1`) create a timestamped `.bak_<timestamp>` backup before modifying existing user files and skip backup creation when file content is already identical.
  * Every provisioning, theme-switching, IDE orchestration, and system-update script (`setup.ps1`, `bootstrap.ps1`, `bin/theme.ps1`, `bin/ide.ps1`, `bin/update-system.ps1`) honors `-DryRun` or `--dry-run` without mutating files, registry keys, or running processes.
* **High-speed shell startup**:
  * `$PROFILE` remains a single-line `Import-Module WindowsSettings -DisableNameChecking -ErrorAction SilentlyContinue` statement.
  * Never introduce `Get-ChildItem -Recurse`, `Get-Command` `PATH` scans, or synchronous external child processes inside `module/` startup paths; rely on compiled `.ps1` caches under `$HOME\.cache\powershell\`.
* **Universal semantic color contract**:
  * Syntax grammars, Tree-sitter queries, prompts, terminal profiles, and filesystem palettes adhere to the 3-tier semantic color contract across all 17 built-in palettes (9 classic developer palettes and 8 US Holiday themes) and 40 languages: `BASE0` and `BASE01` monotone ground, `YELLOW` reserved exclusively for control flow, `GREEN` declarations and primitive types, `BLUE` routine declarations and section headers, `VIOLET` annotations and imports, `CYAN` strings and paths, `MAGENTA` constants and literals, and `ORANGE` directives and Markdown H1 headings.

## Component structure and multi-file contracts

Keep components uniform across shells and tools, and never commit ad-hoc scratch scripts, patch files, or `.bak` backups into the repository tree:

1. **Adding or updating a CLI utility**:
   * **PowerShell script**: Implement `bin/<name>.ps1` (`CRLF`) with `[CmdletBinding()]`, `$ErrorActionPreference = 'Stop'`, pipeline input support where applicable, and `--dry-run` for stateful operations.
   * **Batch wrapper**: Add `bin/<name>.cmd` (`CRLF`) invoking `pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0<name>.ps1" %*`.
   * **Shell integration**: Register a wrapper or alias in `module/Utilities.ps1` or `module/Developer.ps1`, export it in `module/WindowsSettings.psd1`, add tab completion in `module/Completions.ps1`, add a `doskey` macro in `config/cmd/autorun.cmd`, and add test coverage in `tests/test_settings.ps1`.
2. **Adding or updating a built-in theme palette**:
   * **Palette definition**: Declare all semantic and ANSI slots in `config/themes/<slug>.theme`.
   * **Static asset synchronization**: Run `pwsh -NoProfile -File ./bin/theme.ps1 --sync-assets` to regenerate `config/bat/themes/*-TrueColor.tmTheme`, `config/btop/themes/*.theme`, `config/terminal/windows-settings.json`, and `config/terminal/settings.json`, and update the standalone palette table in `config/vim/_vimrc`.
3. **Adding or updating language highlighting**:
   * **Polyglot parity**: Add a representative sample in `sample-code/`, a standalone `.sublime-syntax` grammar in `config/bat/syntaxes/`, a Tree-sitter `.scm` query in `config/nvim/queries/` or `config/nvim/after/queries/`, and an extension mapping in `config/colors/LS_COLORS`.

## Development setup and local workflow

### Prerequisites

* Windows 10 or Windows 11
* PowerShell 7 or higher (`pwsh`)
* Git for Windows
* `PSScriptAnalyzer` PowerShell module (`Install-Module -Name PSScriptAnalyzer -Scope CurrentUser`)
* Optional integration binaries: `oh-my-posh`, `zellij` (`0.46+`), `bat`, and `nvim`

### Clone, preview, and test

```powershell
# Clone the repository
git clone https://github.com/lock14/windows-settings.git
Set-Location windows-settings

# Preview setup and IDE actions without modifying system state
.\setup.ps1 -DryRun
.\setup.ps1 -DryRun -Theme nord
.\bin\ide.ps1 --dry-run

# Run PowerShell static analysis
Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1

# Run the automated validation suite
$null | pwsh -NoProfile -File ./tests/test_settings.ps1
```

## Documentation boundaries and synchronization

* **User-facing documentation**: [README.md](README.md) covers installation, quick-start commands, IDE workflows, theme switching, shell shortcuts, standalone utilities, and local customization without internal implementation mechanics or agent rules.
* **Contributor-facing documentation**: [CONTRIBUTING.md](CONTRIBUTING.md) covers local development setup, multi-file component contracts, static analysis, testing, and pull request guidelines.
* **Agent and architectural invariants**: [AGENTS.md](AGENTS.md) is the single canonical reference at the repository root for architecture invariants, palette specifications, technical writing and typography conventions, and agent verification checklists.
* **Mandatory synchronization**: Whenever commands, flags, aliases, themes, directory layouts, or architectural invariants change, update [README.md](README.md), [CONTRIBUTING.md](CONTRIBUTING.md), [AGENTS.md](AGENTS.md), and [llms.txt](llms.txt) in the same pull request.

## Pre-completion verification checklist

Before opening a pull request, ensure all of the following commands succeed without errors or warnings:

```powershell
# 1. PowerShell static analysis (zero errors and zero warnings)
Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1

# 2. Full automated validation suite (all 8 test modules pass, including doc typography and link lint)
$null | pwsh -NoProfile -File ./tests/test_settings.ps1

# 3. Verify module import latency and clean working tree
pwsh -NoProfile -Command "Measure-Command { Import-Module ./module/WindowsSettings.psd1 -DisableNameChecking }"
git status --short
```

## Pull request guidelines

1. **Branch naming**: Use descriptive prefixes such as `feat/zellij-monitor`, `fix/omp-cache-sync`, `perf/module-startup`, or `docs/ide-keybindings`.
2. **Commit messages**: Follow Chris Beams' seven rules: write an imperative, capitalized subject line of 50 characters or fewer (hard cap at 72) with no trailing period (such as `Add Zellij session monitor` or `Strip bat flags in raw cat fallback`), followed by a blank line and a 72-character wrapped plain-text body explaining what changed and why.
3. **Pull request description**: Complete the [pull request template](.github/PULL_REQUEST_TEMPLATE.md) explaining "why" before "what" grouped by subsystem, and update the description via `gh pr edit --body-file` whenever follow-up commits expand or modify the branch.
