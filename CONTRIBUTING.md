# Contributing to windows-settings

Thank you for your interest in contributing to `github.com/lock14/windows-settings`! This document outlines our repository architecture invariants, multi-file component contracts, safe local testing workflow, and pull request requirements.

---

## 1. Core Architectural & Safety Principles

* **Portability & Zero Personal Paths:** Never hardcode personal user directories or machine-specific paths (`C:\Users\<name>\`, `/Users/<name>/`, `/home/<name>/`). Always use canonical PowerShell and Windows environment variables (`$HOME`, `$env:USERPROFILE`, `$env:LOCALAPPDATA`, `$env:APPDATA`, `$PROFILE`) and construct paths with `Join-Path` / `Split-Path`.
* **Strict Line-Ending Discipline (`.gitattributes`):**
  * `.ps1`, `.psm1`, `.psd1`, `.cmd`, and `.bat` files **must** use `CRLF` (`\r\n`) line endings (`cmd.exe` miscalculates byte offsets after `chcp 65001 >nul` if `.cmd` scripts use `LF`).
  * `.md`, `.json`, `.kdl`, `.yml`, `.yaml`, `.toml`, `.lua`, `.scm`, `.theme`, and `.txt` files **must** use `LF` (`\n`) line endings.
* **Non-Destructive Backups, Idempotency & `-DryRun` Support:**
  * Setup and uninstall flows (`setup.ps1`, `bootstrap.ps1`) must create a timestamped `.bak_<timestamp>` backup before modifying existing user files and skip backup creation when file content is already identical.
  * Every provisioning, theme-switching, IDE orchestration, or system-update script (`setup.ps1`, `bootstrap.ps1`, `bin/theme.ps1`, `bin/ide.ps1`, `bin/update-system.ps1`) must honor `-DryRun` / `--dry-run` without mutating files, registry keys, or processes.
* **High-Speed Shell Startup (`<10ms` Warm Target):**
  * `$PROFILE` remains a single-line `Import-Module WindowsSettings -DisableNameChecking -ErrorAction SilentlyContinue`.
  * Never introduce `Get-ChildItem -Recurse`, `Get-Command` PATH loops, or synchronous external sub-processes inside `module/` load paths; rely on compiled `.ps1` caches under `$HOME\.cache\powershell\`.
* **Universal Semantic Color Contract:**
  * Syntax, prompt, terminal, and filesystem palettes adhere to the 3-Tier Semantic Color Contract across all 17 built-in palettes (9 classic + 8 US Holiday themes) and 40 languages: `BASE0`/`BASE01` monotone ground, `YELLOW` strictly reserved for control flow, `GREEN` declarations & primitive types, `BLUE` routine declarations & section headers, `VIOLET` annotations & imports, `CYAN` strings & paths, `MAGENTA` constants & literals, `ORANGE` directives & H1.

---

## 2. Component Structure & Multi-File Contracts

Keep components uniform across shells and tools—never commit ad-hoc scratch scripts, patch files, or `.bak` backups into the repository tree:

1. **Adding or Updating a CLI Utility in `bin/`:**
   * `bin/<name>.ps1` (`CRLF`): Primary PowerShell 7 implementation (`[CmdletBinding()]`, `$ErrorActionPreference = 'Stop'`, pipeline support where appropriate, and `--dry-run` for stateful tools).
   * `bin/<name>.cmd` (`CRLF`): Dual-execution batch wrapper invoking `pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0<name>.ps1" %*`.
   * Shell integration: Wrapper/alias in `module/Utilities.ps1` or `module/Developer.ps1`, exported in `module/WindowsSettings.psd1`, tab completion in `module/Completions.ps1`, `doskey` macro in `config/cmd/autorun.cmd`, and unit/integration coverage in `tests/test_settings.ps1`.
2. **Adding or Updating a Theme Palette:**
   * Define all palette slots in `config/themes/<slug>.theme`.
   * Regenerate synchronized static assets via `pwsh -NoProfile -File ./bin/theme.ps1 --sync-assets` (`config/bat/themes/*-TrueColor.tmTheme`, `config/btop/themes/*.theme`, `config/terminal/windows-settings.json`, `config/terminal/settings.json`) and update standalone `config/vim/_vimrc`.
3. **Adding or Updating Language Highlighting:**
   * Include a representative sample in `sample-code/`, a standalone `.sublime-syntax` grammar in `config/bat/syntaxes/`, the corresponding Tree-sitter `.scm` query in `config/nvim/queries/` or `config/nvim/after/queries/`, and extension color mapping in `config/colors/LS_COLORS`.

---

## 3. Development Setup & Safe Local Workflow

### Prerequisites

* Windows 10 or Windows 11
* PowerShell 7+ (`pwsh`)
* Git for Windows
* `PSScriptAnalyzer` PowerShell module (`Install-Module -Name PSScriptAnalyzer -Scope CurrentUser`)
* Optional for full integration coverage: `oh-my-posh`, `zellij` (`0.46+`), `bat`, `nvim`

### Clone, Preview & Test

```powershell
# Clone the repository
git clone https://github.com/lock14/windows-settings.git
Set-Location windows-settings

# Preview setup actions safely without modifying system state
.\setup.ps1 -DryRun
.\setup.ps1 -DryRun -Theme nord
.\bin\ide.ps1 --dry-run

# Run static analysis
Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1

# Run the automated validation suite
$null | pwsh -NoProfile -File ./tests/test_settings.ps1
```

---

## 4. Pre-Completion Verification Checklist

Before opening a pull request, ensure all of the following succeed with zero errors or warnings:

```powershell
# 1. PowerShell static analysis (0 errors, 0 warnings)
Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1

# 2. Full automated test suite (all 8 test modules pass)
$null | pwsh -NoProfile -File ./tests/test_settings.ps1

# 3. Verify module import latency & clean working tree
pwsh -NoProfile -Command "Measure-Command { Import-Module ./module/WindowsSettings.psd1 -DisableNameChecking }"
git status --short
```

---

## 5. Pull Request Guidelines

1. **Branch Naming:** Use descriptive prefixes such as `feat/new-utility`, `fix/omp-cache-sync`, `perf/module-startup`, `docs/readme-shortcuts`, or `ci/workflow-hardening`.
2. **Commit Messages:** Follow the Conventional Commits specification (e.g., `feat: add Zellij session monitor`, `fix: strip bat flags in raw cat fallback`).
3. **PR Description:** Complete the [Pull Request Template](.github/PULL_REQUEST_TEMPLATE.md) thoroughly and keep the PR description synchronized if follow-up commits expand or adjust the changeset.
4. **Documentation Synchronization:** Update `README.md`, `AGENTS.md`, and `llms.txt` in the same pull request whenever user-facing commands, flags, themes, or architectural invariants change.
