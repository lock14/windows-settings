# Agent Guidelines for windows-settings

This repository contains workstation configuration files, prompt themes, Windows Terminal settings, CLI tab completions, and setup automation for **PowerShell 7+**, **Oh My Posh**, **Neovim**, and **Windows Terminal** on Windows.

Any agent modifying this repository must follow these core principles and constraints.

---

## 1. Repository Architecture & Component Map

| Component | Repository Path | Target Location on System | Purpose |
| :--- | :--- | :--- | :--- |
| **PowerShell Module** | `module/` | `$HOME\Documents\PowerShell\Modules\WindowsSettings\` | Autoloaded shell functions, aliases, Git tools, completions, performance loader |
| **PowerShell Profile** | `config/powershell/Microsoft.PowerShell_profile.ps1` | `$PROFILE` | Minimal 1-line profile importing `WindowsSettings` |
| **Oh My Posh Prompt** | `config/powershell/p10k_single_line.omp.json` | `$HOME\.poshthemes\p10k_single_line.omp.json` | Primary Powerline prompt theme with compiled disk caching |
| **Neovim Configuration** | `config/nvim/init.lua` | `$env:LOCALAPPDATA\nvim\init.lua` | Neovim 0.11+ Lua config (Lazy.nvim, Native LSP, Treesitter, Solarized Dark) |
| **Legacy Vim Config** | `config/vim/_vimrc` | `$HOME\_vimrc` & `$HOME\.vimrc` | Fallback configuration for legacy Vim |
| **Terminal Fragments** | `config/terminal/windows-settings.json` | `%LOCALAPPDATA%\Microsoft\Windows Terminal\Fragments\WindowsSettings\` | Zero-touch Windows Terminal JSON Fragment extension |
| **TrueColor Themes** | `config/bat/` & `config/colors/` | `%APPDATA%\bat\themes\` & `$env:LS_COLORS` | 24-bit Solarized Dark themes for `bat`, `eza`, and `dircolors` |
| **Native User Binaries** | `bin/` | Registered in User `$env:Path` | Dual-execution CLI scripts (`<name>.ps1` + `<name>.cmd`) |
| **Package Declarations** | `configuration.dsc.yaml` & `mise.toml` | System Provisioning | Microsoft DSC v3 and Mise declarative package specifications |
| **Automation Scripts** | `setup.ps1`, `bootstrap.ps1` | Root orchestrators | Declarative provisioning and configuration runners supporting `-DryRun` |
| **Automated Tests** | `tests/test_settings.ps1` | Test Suite | 133 automated validation tests across 8 modules |

---

## 2. Portability & Path Invariants

- **Never Commit Personal User Paths**: Never hardcode personal paths like `C:\Users\<username>\`, `/Users/<username>/`, or `/home/<username>/` into scripts, configuration files, or tests.
- **Use Canonical PowerShell & Environment Variables**:
  - User Home: `$HOME` or `$env:USERPROFILE`
  - Local AppData: `$env:LOCALAPPDATA`
  - Roaming AppData: `$env:APPDATA`
  - PowerShell Profile: `$PROFILE`
  - Path Construction: Always use `Join-Path` or `Split-Path` rather than hardcoding string backslashes or slashes.
- **Windows Terminal Dynamic Resolution & Fragments**:
  - Deploy JSON Fragment extensions under `%LOCALAPPDATA%\Microsoft\Windows Terminal\Fragments\WindowsSettings\` for zero-touch configuration without mutating base `settings.json`.
  - When merging `settings.json`, search dynamically across all possible installation locations (`LocalState`, `Microsoft.WindowsTerminal_8wekyb3d8bbwe`, `Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe`).
- **Dual-Execution Support in `bin/`**:
  - Every native utility script in `bin/` must have both a PowerShell implementation (`<name>.ps1`) and a CMD batch wrapper (`<name>.cmd`) for transparent invocation across PowerShell, cmd.exe, and external tools.

---

## 3. Destructive Safety & Idempotent Backup Policy

- **Mandatory Non-Destructive Backups**:
  - Any installation or setup script (`setup.ps1`, `bootstrap.ps1`) must create a timestamped backup (`.bak_<timestamp>`) before overwriting or modifying an existing user configuration file (e.g. Windows Terminal `settings.json`, PowerShell `$PROFILE`, Neovim `init.lua`).
- **Strict Idempotency Requirement**:
  - Running setup scripts repeatedly must not corrupt configuration files, create duplicate profile blocks, or generate redundant backups when file content has not changed.
  - Sourcing profiles or re-running installers must be safe to execute multiple times in the same session.
- **Support `-DryRun`, `-UseDSC`, and Modular Switches**:
  - All provisioning and setup logic in `setup.ps1`, `bootstrap.ps1`, and sub-scripts must support `-DryRun` preview mode without mutating files, registry entries, or system state.
  - Provide modular execution switches: `-Bootstrap`, `-DotfilesOnly`, `-SystemOnly`, `-UseDSC`, `-WithGUI`.
- **Preserve Unrelated User Configuration**:
  - When modifying configuration files (e.g., Windows Terminal `settings.json`, PowerShell `$PROFILE`), preserve existing user custom profiles, keybindings, actions, or third-party settings unless explicitly instructed to overwrite them.
- **Graceful Failure & Error Handling**:
  - Use `$ErrorActionPreference = 'Stop'` in automation scripts.
  - Validate prerequisites (e.g. `winget`, `oh-my-posh`, `fzf`, `git`) gracefully, emitting clear instructions or warnings when a tool is not present rather than hard-crashing.

---

## 4. Shell Performance & Architecture Invariants

- **High-Speed Shell Startup (<10ms Target)**:
  - The shell configuration is packaged as an autoloaded PowerShell Module (`WindowsSettings.psd1`).
  - `$PROFILE` must remain minimal: `Import-Module WindowsSettings -DisableNameChecking -ErrorAction SilentlyContinue`.
  - **No Dynamic Disk Traversal in `psm1`**: Never use `Get-ChildItem -Recurse` inside module startup paths. All public/private module scripts are sourced explicitly.
  - **No Dynamic `Get-Command` Loops**: Never run `Get-Command` scans across all PATH directories during shell startup (e.g., registering completers). Use statically known binary names and direct command calls.
  - **Compiled Disk Caching**: Heavy prompt and engine initializations (`oh-my-posh init`, `zoxide init`, `gh completion`) must be cached as compiled `.ps1` files under `$HOME\.cache\powershell\` to avoid spawning sub-processes on every new shell tab.
- **Un-Aliasing Conflicting Legacy Cmdlets**:
  - Automatically un-alias conflicting PowerShell cmdlets (`cat`, `sort`, `tee`, `diff`, `echo`, `sleep`, `ls`, `gcm`, `gl`, `gp`) so modern tools (`uutils-coreutils`, `eza`, `bat`, Git aliases) execute without prefixing `&`.
- **PSScriptAnalyzer Compliance**:
  - All PowerShell scripts (`.ps1`, `.psm1`, `.psd1`) must pass static analysis configured in `PSScriptAnalyzerSettings.psd1` with zero errors or warnings.

---

## 5. Solarized Dark & 24-Bit TrueColor Theme Precision

All visual components across the terminal, shell, prompt, file viewers, and editor must strictly adhere to the authentic **Solarized Dark** palette (Ethan Schoonover specification).

### Canonical Palette Reference
| Role | Color Name | Hex Code | Purpose / Usage |
| :--- | :--- | :--- | :--- |
| **Base Background** | `base03` | `#002B36` | Terminal background, Neovim background, bat background |
| **Current Line / Alt Bg** | `base02` | `#073642` | CursorLine, selection background, line highlight |
| **Comments / Dim Borders** | `base01` | `#586E75` | Code comments (italic), eza tree connectors (`xx`), prompt dim elements, bat borders |
| **Subtle Text** | `base00` | `#657B83` | Secondary text, status indicators |
| **Standard Foreground** | `base0` | `#839496` | Standard typed text, CLI arguments, paths, struct fields, identifiers |
| **Emphasis Text** | `base1` | `#93A1A1` | Bright text, highlighted labels |
| **Light Tone (Paper)** | `base2` / `base3` | `#EEE8D5` / `#FDF6E3` | Light background references (never default text) |
| **Keywords & Control** | `green` | `#859900` | `package`, `import`, `func`, `return`, `if`, `for`, `var`, `type`, `struct`, PSReadLine commands |
| **Types & Struct Names** | `yellow` | `#B58900` | Primitive types (`int`, `string`, `bool`), PSReadLine variables, options & parameters |
| **Functions & Methods** | `blue` | `#268BD2` | Function declarations, method calls, directory names |
| **Strings & Paths** | `cyan` | `#2AA198` | String literals, PSReadLine strings |
| **Numbers & Constants** | `magenta` | `#D33682` | Numeric literals, `nil`, `true`, `false`, `iota`, PSReadLine numbers |
| **Operators & Mechanics**| `violet` | `#6C71C4` | Operators, pipes, redirections, PSReadLine operators |
| **Preprocessors & Headers**| `orange` | `#CB4B16` | Preprocessor macros, compiler directives |
| **Errors & Diagnostics** | `red` | `#DC322F` | Syntax errors, diagnostic warnings |

### Integration Rules
1. **Global 24-Bit TrueColor (`COLORTERM=truecolor`)**:
   - Modern Rust CLI tools (`bat`, `eza`, `delta`) check `$env:COLORTERM`. Ensure `$env:COLORTERM = 'truecolor'` is exported in `WindowsSettings.psm1` and registered in the user's permanent environment variables to prevent 256-color quantization.
2. **PSReadLine 24-Bit Escape Sequences**:
   - In `PSReadLine`, pass 24-bit TrueColor escape sequences (``"`e[38;2;R;G;Bm"``) with explicit `Default = "`e[38;2;131;148;150m"` mapping so unquoted file paths and arguments render in comfortable `#839496` Base0 light grey rather than stark white.
3. **`bat` TrueColor Theme**:
   - `bat` syntax highlighting uses `config/bat/Solarized-Dark-TrueColor.tmTheme` compiled into `%APPDATA%\bat\` via `bat cache --build`.
   - `cat` is aliased to `bat --theme="Solarized-Dark-TrueColor" --paging=auto`.
4. **`eza` Tree Connector Colors**:
   - `EZA_COLORS` and `EXA_COLORS` are configured with `xx=38;5;10` (Solarized Base01) so `lt` / `eza --tree` renders crisp `├──` tree punctuation.
5. **Neovim Lua Configuration**:
   - Uses `maxmx03/solarized.nvim` with `variant = "spring"` for vibrant high-contrast syntax highlighting matching the terminal.
   - Configures native Neovim 0.11+ / 0.12+ LSP architecture (`LspAttach` autocommands, `vim.lsp.config`, `vim.lsp.enable`).

---

## 6. Developer Shortcuts & Editor Suite

- **Maintain Kebab-Case Naming with Backward Compatibility**:
  - Maintain the full Git plugin suite: `gco`, `gcb`, `gcm`, `ga`, `gaa`, `gst`, `gss`, `gd`, `gds`, `gl`, `gp`, `gb`, `gba`, `gbd`, `gsta`, `gstp`, `gstl`, `glog`, `glo`, `grb`, `gcommit`, `gamend`, `gup`, `gprune`, `gsync`, `guser-branch`.
  - Maintain developer shortcuts: `go-testall`, `go-buildall`, `go-lint`, `yaml-lint`, `fs`, `Format-PathTree`, `ll`, `la`, `lt`.
  - Maintain editor shortcuts: `vi`, `vim`, `v` aliased to `nvim` (with automatic fallback to `vim` if Neovim is not installed).
  - Provide backward-compatible wrappers for legacy aliases (`go_testall`, `go_buildall`, `go_lint`, `yaml_lint`, `fix-abcxyz-branch-name`).
  - `guser-branch` must cleanly strip redundant user prefixes (`$env:USERNAME/` or `$env:USER/`) before renaming.

---

## 7. Documentation Boundaries & Continuous Learning

- **Mandatory Documentation Synchronization**:
  - **Every agent change must update documentation**: Whenever new aliases, functions, CLI utilities, setup parameters, or terminal configurations are added or modified, update the relevant documentation in the same commit/PR.
- **`README.md` is for Users**:
  - Focus purely on user-facing concerns: prerequisites, quick start commands, architecture overview, shortcuts tables, and utility usage examples.
- **`AGENTS.md` is for Agents & Contributors**:
  - Architectural principles, path invariant enforcement, linter rules, testing procedures, palette specs, and agent workflows belong exclusively in `AGENTS.md`.
- **Persist User Corrections**:
  - Whenever an agent receives feedback, corrections, or instructions regarding repository conventions, it **must immediately encode the underlying principle into `AGENTS.md`** before concluding the task.

---

## 8. CLI Execution & Markdown Escaping Safety

- **Avoid Inline Backtick Expansion in PowerShell Commands**:
  - In PowerShell (`pwsh`), the backtick (`` ` ``) is the native escape character.
  - When passing markdown strings containing inline code (e.g. `` `eza` ``, `` `node` ``) within double quotes (`"..."`), PowerShell evaluates the backticks as escape sequences:
    - `` `e `` expands to the ANSI escape character (`^[`)
    - `` `n `` expands to newline
    - `` `t `` expands to tab
    - Resulting in corrupted text, missing backticks, and unwanted escape characters in GitHub PRs, issues, or commit bodies.
- **Mandatory Safe Markdown Invocation Patterns**:
  1. **File-Based Arguments (`--body-file`)**: When creating or editing PRs/issues via GitHub CLI (`gh`), always write the markdown body to a temporary file first and pass `--body-file <path>`.
  2. **Single-Quoted Strings & Here-Strings**: When passing inline markdown, always enclose it in single quotes (`'...'`) or single-quoted here-strings (`@' ... '@`) where PowerShell performs zero escape interpretation.
  3. **Never Use Double Quotes with Markdown Backticks**: Never execute `gh pr create --body "..."` with embedded backticks.

---

## 9. Verification Checklist for Agents

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
   Ensure all **133 tests pass across all 8 test modules**:
   - `[1/8]` PowerShell Script & Module Syntax
   - `[2/8]` JSON, YAML & Manifest Validity (`configuration.dsc.yaml`, `p10k.omp.json`, `settings.json`, fragments)
   - `[3/8]` WindowsSettings Module Import & Function Exports (61 functions)
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
