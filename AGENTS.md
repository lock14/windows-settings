# Agent Guidelines for windows-settings

This repository contains workstation configuration files, prompt themes, Windows Terminal settings, CLI tab completions, and setup automation for **PowerShell 7+**, **Starship**, **Neovim**, and **Windows Terminal** on Windows.

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
  - **PowerShell Module**: `$HOME\Documents\PowerShell\Modules\WindowsSettings\`
  - **Starship Config**: `$HOME\.config\starship.toml`
  - **Neovim Configuration**: `$env:LOCALAPPDATA\nvim\` (`init.lua`)
  - **Windows Terminal Fragments**: `%LOCALAPPDATA%\Microsoft\Windows Terminal\Fragments\WindowsSettings\windows-settings.json`
  - **User Fonts**: `%LOCALAPPDATA%\Microsoft\Windows\Fonts\` (registered in `HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts`)
  - **User Binaries**: `$HOME\windows-settings\bin\` (registered in user `$env:Path`)
- **Windows Terminal Dynamic Resolution & Fragments**:
  - Deploy JSON Fragment extensions under `%LOCALAPPDATA%\Microsoft\Windows Terminal\Fragments\WindowsSettings\` for zero-touch configuration without touching base `settings.json`.
  - When merging `settings.json`, search dynamically across all possible installation locations (`LocalState`, `Microsoft.WindowsTerminal_8wekyb3d8bbwe`, `Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe`).
- **Dual-Execution Support in `bin/`**:
  - Every native utility script in `bin/` must have both a PowerShell implementation (`<name>.ps1`) and a CMD batch wrapper (`<name>.cmd`) for transparent invocation across PowerShell, cmd.exe, and external tools.

---

## 2. Destructive Safety & Idempotent Backup Policy

- **Mandatory Non-Destructive Backups**:
  - Any installation or setup script (`setup.ps1`, `terminal-setup.ps1`, `posh-setup.ps1`, `vim-setup.ps1`) must create a timestamped backup (`.bak_<timestamp>`) before overwriting or modifying an existing user configuration file (e.g. Windows Terminal `settings.json`, PowerShell `$PROFILE`, Neovim `init.lua`).
- **Idempotency Requirement**:
  - Running setup scripts repeatedly must not corrupt configuration files, create duplicate profile blocks, or generate redundant backups when the file content has not changed.
  - Sourcing profiles or re-running installers must be safe to execute multiple times in the same session.
- **Support `-DryRun`, `-UseDSC`, and Granular Execution Switches**:
  - All provisioning and setup logic in `setup.ps1`, `bootstrap.ps1`, and sub-scripts must support `-DryRun` preview mode without mutating files, registry entries, or system state.
  - Provide modular execution switches: `-Bootstrap`, `-DotfilesOnly`, `-SystemOnly`, `-UseDSC`, `-WithGUI`.
- **Preserve Unrelated Configuration**:
  - When modifying configuration files (e.g., Windows Terminal `settings.json`, PowerShell `$PROFILE`), preserve existing user custom profiles, keybindings, actions, or third-party settings unless explicitly instructed to overwrite or replace them.
- **Graceful Failure & Error Handling**:
  - Use `$ErrorActionPreference = 'Stop'` in automation scripts.
  - Validate prerequisites (e.g. `winget`, `starship`, `fzf`, `git`) gracefully, emitting clear instructions or warnings when a tool is not present rather than hard-crashing.

---

## 3. Shell Performance, Code Quality & Theme Hygiene

- **High-Speed Shell Startup & Modular PowerShell**:
  - Shell logic is packaged as a clean autoloaded PowerShell Module (`Modules/WindowsSettings/WindowsSettings.psd1`).
  - The user's `$PROFILE` simply imports `WindowsSettings`.
  - Dynamic Go workspace paths (`go env GOPATH`) must be resolved safely without slowing shell startup.
- **PSScriptAnalyzer Compliance**:
  - All PowerShell scripts (`.ps1`, `.psm1`, `.psd1`) must pass static analysis configured in `PSScriptAnalyzerSettings.psd1` with zero errors or warnings.
- **Solarized Dark & Powerline Theme Integrity**:
  - All visual components—Starship prompt (`starship.toml`), Windows Terminal color schemes & fragments, `PSReadLine` syntax and prediction colors, `colors/LS_COLORS`, and Neovim Lua styling—must strictly adhere to the Solarized Dark palette and MesloLGS NF font styling.
- **Declarative Provisioning**:
  - Workstation tools are declared in `configuration.dsc.yaml` (Microsoft DSC v3) and `mise.toml` (polyglot runtime toolchains).

---

## 4. Developer Shortcuts & Navigation Suite

- **Maintain Kebab-Case Naming with Backward Compatibility**:
  - Maintain the full Git plugin suite and workflow helpers (`gco`, `gcb`, `gcm`, `ga`, `gst`, `gcommit`, `gamend`, `gup`, `gprune`, `gsync`, `guser-branch`).
  - Maintain developer shortcuts: `go-testall`, `go-buildall`, `go-lint`, `yaml-lint`, `fs`, `Format-PathTree`, `ll`, `la`, `lt`.
  - Provide backward-compatible wrappers for legacy aliases (`go_testall`, `go_buildall`, `go_lint`, `yaml_lint`, `fix-abcxyz-branch-name`).
  - `guser-branch` must cleanly strip redundant user prefixes (`$env:USERNAME/` or `$env:USER/`) before renaming.
- **Modern CLI Integration**:
  - Adopt `eza` for `ls`, `ll`, `la`, `lt` with Git status indicators and directory trees.
  - Adopt `zoxide` for `z` frecency directory navigation.
  - Adopt `bat` for syntax-highlighted file viewing.
  - Adopt `uutils.coreutils` and `uutils.diffutils` with automatic un-aliasing of text cmdlet redirects (`cat`, `sort`, `tee`, `diff`, `echo`, `sleep`, `ls`).

---

## 5. Documentation Boundaries & Mandatory Updates

- **Mandatory Documentation Synchronization**:
  - **Every agent change must update documentation**: Whenever new aliases, functions, CLI utilities, setup parameters, or terminal configurations are added or modified, update the relevant documentation in the same commit/PR.
- **`README.md` is for Users**:
  - Focus purely on user-facing concerns: prerequisites, quick start commands, architecture overview, shortcuts tables, and utility usage examples.
- **`AGENTS.md` is for Agents & Contributors**:
  - Architectural principles, path invariant enforcement, linter rules, testing procedures, and agent workflows belong exclusively in `AGENTS.md`.

---

## 6. Continuous Learning & Principle Encoding

- **Persist User Corrections**:
  - Whenever an agent receives feedback, corrections, or instructions regarding repository conventions, it **must immediately encode the underlying principle into `AGENTS.md`** before concluding the task.

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
   Ensure all 125 tests pass across all 8 test modules:
   - `[1/8]` PowerShell Script & Module Syntax
   - `[2/8]` JSON, YAML & Manifest Validity (`configuration.dsc.yaml`, `starship.toml`, `settings.json`, fragments)
   - `[3/8]` WindowsSettings Module Import & Function Exports (60 functions)
   - `[4/8]` Native CLI Utilities & Pipeline Handling (`sum`, `gen-passwd`, `repeat-until-success`)
   - `[5/8]` Git Workflow Behavior (`gsync`, `gprune`, `guser-branch`, `fix-abcxyz-branch-name`)
   - `[6/8]` Completions & Prompt Rendering
   - `[7/8]` Path Invariants & Dual Execution Wrappers
   - `[8/8]` Setup Script Idempotency, DryRun & Backup Policy
3. **Verify Path Invariants**:
   Inspect `git diff` to confirm no hardcoded personal usernames or machine-specific paths were introduced.
4. **Update Documentation**:
   - Update `README.md` if user-facing behavior, aliases, utilities, or configuration options changed.
   - Update `AGENTS.md` if repository principles, architecture, or agent rules changed.
