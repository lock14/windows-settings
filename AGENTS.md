# Agent Guidelines for windows-settings

This repository contains workstation configuration files, prompt themes, Windows Terminal settings, CLI tab completions, and setup automation for **PowerShell 7+** and **Windows Terminal** on Windows. It is designed to provide visual and functional parity with [`home-settings`](https://github.com/lock14/home-settings) (*nix / Zsh / Solarized Dark).

Any agent modifying this repository must follow these core principles.

---

## 1. Portability & Path Invariants

- **Never Commit Personal User Paths**: Never hardcode personal paths like `C:\Users\<username>\`, `/Users/<username>/`, or `/home/<username>/` into scripts, configuration files, or tests.
- **Use Canonical PowerShell & Environment Variables**:
  - User Home: `$HOME` or `$env:USERPROFILE`
  - Local AppData: `$env:LOCALAPPDATA`
  - Roaming AppData: `$env:APPDATA`
  - PowerShell Profile: `$PROFILE`
  - Path Construction: Always use `Join-Path` or `Split-Path` rather than hardcoding backslashes or slashes.
- **Standard Target Directory Structures**:
  - **PowerShell Profile**: `$PROFILE` (e.g. `$HOME\Documents\PowerShell\Microsoft.PowerShell_profile.ps1`)
  - **Oh My Posh Theme**: `$HOME\.poshthemes\p10k_single_line.omp.json`
  - **Shell Startup Cache**: `$HOME\.cache\powershell\` (`omp_init.ps1`, `gh_completion.ps1`, etc.)
  - **Windows Terminal Settings**: `%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json` (or Preview / unpacked locations)
  - **Vim Runtime & Configuration**: `$HOME\_vimrc`, `$HOME\.vim\`
  - **User Fonts**: `%LOCALAPPDATA%\Microsoft\Windows\Fonts\` (registered in `HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts`)
  - **User Binaries**: `$HOME\windows-settings\bin\` (registered in user `$env:Path`)
- **Windows Terminal Dynamic Resolution**:
  - Windows Terminal stores settings under `%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState` (or `Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState` or `%LOCALAPPDATA%\Microsoft\Windows Terminal`).
  - Always search dynamically across possible installation locations before defaulting.
- **Dual-Execution Support in `bin/`**:
  - Every native utility script in `bin/` must have both a PowerShell implementation (`<name>.ps1`) and a CMD batch wrapper (`<name>.cmd`) for transparent invocation across PowerShell, cmd.exe, and external tools.

---

## 2. Destructive Safety & Idempotent Backup Policy

- **Mandatory Non-Destructive Backups**:
  - Any installation or setup script (`setup.ps1`, `terminal-setup.ps1`, `posh-setup.ps1`, `vim-setup.ps1`) must create a timestamped backup (`.bak_<timestamp>`) before overwriting or modifying an existing user configuration file (e.g. Windows Terminal `settings.json`, PowerShell `$PROFILE`, Vim `_vimrc`).
- **Idempotency Requirement**:
  - Running setup scripts repeatedly must not corrupt configuration files, create duplicate profile blocks, or generate redundant backups when the file content has not changed.
  - Sourcing profiles or re-running installers must be safe to execute multiple times in the same session.
- **Preserve Unrelated Configuration**:
  - When modifying configuration files (e.g., Windows Terminal `settings.json`, PowerShell `$PROFILE`, Vim `_vimrc`), preserve existing user custom profiles, keybindings, actions, or third-party settings unless explicitly instructed to overwrite or replace them.
- **Graceful Failure & Error Handling**:
  - Use `$ErrorActionPreference = 'Stop'` in automation scripts.
  - Validate prerequisites (e.g. `winget`, `oh-my-posh`, `fzf`, `git`) gracefully, emitting clear instructions or warnings when a tool is not present rather than hard-crashing.

---

## 3. Shell Performance, Code Quality & Theme Hygiene

- **High-Speed Shell Startup**:
  - The PowerShell profile (`posh/Microsoft.PowerShell_profile.ps1`) must remain lightning fast.
  - Heavy initializations (e.g. Oh My Posh initialization scripts, CLI completions) must be compiled and cached to disk in `$HOME\.cache\powershell\` to maintain sub-second startup times.
- **PSScriptAnalyzer Compliance**:
  - All PowerShell scripts (`.ps1`) must pass static analysis configured in `PSScriptAnalyzerSettings.psd1` with zero errors or warnings.
- **Solarized Dark & Powerline Theme Integrity**:
  - All visual components—Oh My Posh single-line Powerlevel10k theme (`posh/p10k.omp.json`), Windows Terminal color schemes (`terminal/settings.json`), `PSReadLine` syntax and prediction colors, and `colors/LS_COLORS`—must strictly adhere to the Solarized Dark palette and MesloLGS NF font styling.
- **JSON Integrity**:
  - All JSON configuration files (`posh/p10k.omp.json`, `terminal/settings.json`) must remain valid, well-formatted JSON with correct block and profile structures.

---

## 4. Cross-Platform Parity with `home-settings`

- **Maintain Alias & Shortcut Parity**:
  - Maintain the Oh My Zsh Git plugin suite and custom workflow helpers (`gco`, `gcb`, `gcm`, `ga`, `gst`, `gcommit`, `gamend`, `gup`, `gprune`, `gsync`, `fix-abcxyz-branch-name`).
  - Maintain developer shortcuts (`go_testall`, `go_buildall`, `go_lint`, `yaml_lint`, `fs`, `Format-PathTree`, `ll`, `la`).
- **Native Utilities in `bin/`**:
  - Ensure all ported utilities (`gen-passwd`, `repeat-until-success`, `sum`) match the behavior, arguments, and pipeline support of their `home-settings` equivalents.

---

## 5. Documentation Boundaries & Mandatory Updates

- **Mandatory Documentation Synchronization**:
  - **Every agent change must update documentation**: Whenever new aliases, functions, CLI utilities, setup parameters, or terminal configurations are added or modified, update the relevant documentation in the same commit/PR.
- **`README.md` is for Users**:
  - Focus purely on user-facing concerns: prerequisites, quick start commands, directory overview, shortcuts tables, and utility usage examples.
  - Keep `README.md` clean, clear, and free of agent meta-instructions or internal maintenance rules.
- **`AGENTS.md` is for Agents & Contributors**:
  - Architectural principles, path invariant enforcement, linter rules, testing procedures, and agent workflows belong exclusively in `AGENTS.md`.

---

## 6. Continuous Learning & Principle Encoding

- **Persist User Corrections**:
  - Whenever an agent receives feedback, corrections, or instructions regarding repository conventions, it **must immediately encode the underlying principle into `AGENTS.md`** before concluding the task.
  - This ensures all future agent sessions inherit the correction seamlessly.

---

## 7. Verification Checklist for Agents

Before completing any task:
1. **Run Static Analysis**:
   ```powershell
   Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
   ```
   Ensure zero errors or warnings are reported.
2. **Run Test Suite**:
   ```powershell
   pwsh -NoProfile -File ./tests/test_settings.ps1
   ```
   Ensure all 93 tests pass across all 8 test modules:
   - `[1/8]` PowerShell Script Syntax
   - `[2/8]` JSON Validity & Schema Verification
   - `[3/8]` Profile Sourcing, Aliases & PSReadLine
   - `[4/8]` Native CLI Utilities & Pipeline Handling
   - `[5/8]` Git Workflow Behavior (`gsync`, `gprune`, `fix-abcxyz-branch-name`)
   - `[6/8]` Completions & Oh My Posh Rendering
   - `[7/8]` Path Invariants & Dual Execution Wrappers
   - `[8/8]` Setup Script Idempotency & Backup Policy
3. **Verify Path Invariants**:
   Inspect `git diff` to confirm no hardcoded personal usernames or machine-specific paths were introduced.
4. **Update Documentation**:
   - Update `README.md` if user-facing behavior, aliases, utilities, or configuration options changed.
   - Update `AGENTS.md` if repository principles, architecture, or agent rules changed.
   - **Encode Corrections**: Codify any user feedback into `AGENTS.md`.
