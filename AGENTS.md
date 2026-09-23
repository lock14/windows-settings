# Agent Guidelines for windows-settings

This repository contains workstation configuration files, prompt themes, Windows Terminal settings, CLI tab completions, and setup automation for **PowerShell 7+**, **Oh My Posh**, **Neovim**, and **Windows Terminal** on Windows.

Any agent modifying this repository must follow these core principles and constraints.

---

## 1. Repository Architecture & Component Map

| Component | Repository Path | Target Location on System | Purpose |
| :--- | :--- | :--- | :--- |
| **PowerShell Module** | `module/` | `$HOME\Documents\PowerShell\Modules\WindowsSettings\` | Autoloaded shell functions, aliases, Git tools, completions, performance loader |
| **PowerShell Profile** | `config/powershell/Microsoft.PowerShell_profile.ps1` | `$PROFILE` | Minimal 1-line profile importing `WindowsSettings` |
| **Oh My Posh Prompt** | `config/powershell/p10k_single_line.omp.json` | `$HOME\.poshthemes\p10k_single_line.omp.json` | Base02 shelf prompt theme with compiled disk caching & directional chevrons |
| **Neovim Configuration** | `config/nvim/init.lua` | `$env:LOCALAPPDATA\nvim\init.lua` | Neovim 0.11+ / 0.12+ Lua config (Lazy.nvim, Native LSP, Treesitter, Solarized Dark) |
| **Neovim Queries & Tree-sitter** | `config/nvim/queries/`, `after/`, `ftplugin/` | `$env:LOCALAPPDATA\nvim\` | Dedicated AST highlight queries & Java filetype plugin matching Universal Color Contract |
| **Legacy Vim Config** | `config/vim/_vimrc` | `$HOME\_vimrc` & `$HOME\.vimrc` | Zero-dependency standalone fallback configuration with inline Solarized Dark palette |
| **Command Prompt AutoRun** | `config/cmd/autorun.cmd` | `%LOCALAPPDATA%\cmd\autorun.cmd` | Native `cmd.exe` AutoRun environment, TrueColor Solarized Dark prompt, and doskey macros |
| **Terminal Fragments** | `config/terminal/windows-settings.json` | `%LOCALAPPDATA%\Microsoft\Windows Terminal\Fragments\WindowsSettings\` | Zero-touch Windows Terminal JSON Fragment extension |
| **TrueColor Themes & Syntaxes** | `config/bat/` & `config/colors/` | `%APPDATA%\bat\` & `$env:LS_COLORS` | 24-bit Solarized Dark themes & standalone Sublime syntaxes for `bat`, `eza`, and `dircolors` |
| **Native User Binaries** | `bin/` | Registered in User `$env:Path` | Dual-execution CLI scripts (`<name>.ps1` + `<name>.cmd`) |
| **Polyglot Sample Code** | `sample-code/` | Repository validation suite | 20 real-world sample files across languages for syntax & query evaluation |
| **Package Declarations** | `configuration.dsc.yaml` & `mise.toml` | System Provisioning | Microsoft DSC v3 and Mise declarative package specifications |
| **Automation Scripts** | `setup.ps1`, `bootstrap.ps1` | Root orchestrators | Declarative provisioning and configuration runners supporting `-DryRun` |
| **Automated Tests** | `tests/test_settings.ps1` | Test Suite | 163+ automated validation tests across 8 modules |

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
| **Control Flow & Jumps**| `yellow` | `#B58900` | `if`, `return`, `for`, `while`, `switch`, `case`, `select`, `defer`, `match`, `try`, `throw`, `yield`, `await`, PSReadLine control flow keywords |
| **Structural & Declarations**| `green` | `#859900` | `package`, `import`, `func`, `var`, `type`, `struct`, primitive types (`int`, `string`, `bool`), PSReadLine commands & types |
| **Functions & Methods** | `blue` | `#268BD2` | Function declarations, method calls, directory names |
| **Strings & Paths** | `cyan` | `#2AA198` | String literals, PSReadLine strings |
| **Numbers & Constants** | `magenta` | `#D33682` | Numeric literals, `nil`, `true`, `false`, `iota`, PSReadLine numbers |
| **Operators & Mechanics**| `violet` | `#6C71C4` | Preprocessor symbols, compiler directives |
| **Preprocessors & Headers**| `orange` | `#CB4B16` | Preprocessor macros, compiler directives |
| **Errors & Diagnostics** | `red` | `#DC322F` | Syntax errors, diagnostic warnings |

### Universal Semantic Color Contract
Colors across the developer workstation fulfill invariant domain roles across all languages, tools, and filetypes:

| Palette Color | Hex Code | Universal Semantic Role | Manifestations Across Languages & Tools |
| :--- | :--- | :--- | :--- |
| **Solarized Yellow**| `#B58900` | Uncontested control flow & jumps | `if`, `return`, `for`, `while`, `switch`, `case`, `select`, `defer`, `match`, `try`, `throw`, `yield`, `await`, `CASE/WHEN` (exclusive to control flow, never in Markdown headings, declarative data/config documents, CSS stylesheets, or Java Properties) |
| **Solarized Green** | `#859900` | Structural scaffolding, declarations, static primitive types & core built-ins, diff additions | `int`, `double`, `u64`, `usize`, `bool`, `void`, Python built-in types (`int`, `str`, `float`, `bool`, `list`, `dict`, `set`, `tuple`), `package`, `func`, `fn`, `def`, `class`, `struct`, `interface`, `var`, `let`, `const`, `typedef`, `CREATE TABLE`, `DEFAULT`, `ASC`, `DESC`, SQL data types (`VARCHAR`, `BIGINT`), JSON/YAML property keys, TOML mapping & dotted keys (`name`, `port`, `pool.min_size`), Java Properties keys (`spring.application.name`, `server.port`), XML/HTML attribute names (`xmlns`, `version`, `id`, `replicas`, `lang`, `class`, `charset`, `data-status`), CSS property names (`font-family`, `display`, `color`, `margin`), `+` added lines, PSReadLine commands |
| **Base0 Grey**      | `#839496` | Neutral ground, custom domain types, schemas, invocations, operators | Custom domain types (`OrderRecord`, `Context`, `HashMap`, `Instant`), schema relations (tables/views/CTEs), dynamic types/classes (Python `Callable`, `Union`), function/method calls (`printf()`, `.stream()`), CSS custom properties & variables (`--color-base03`), CSS functions (`var()`, `clamp()`), CSS attribute selectors (`[data-status="healthy"]`), XML/HTML tag delimiters (`<`, `>`, `</`, `/>`), TOML brackets and delimiters (`[`, `]`, `[[`, `]]`, `=`, `.`), Java Properties delimiters (`=`, `:`) and interpolation references (`${...}`), parameters, operators, PSReadLine arguments |
| **Solarized Blue**  | `#268BD2` | Routine declarations & structural headers | `func New...`, `fn find...`, `def __init__`, XML element tags (`<deployment>`, `<script>`), TOML table section headers (`[package]`, `[[rate_limits]]`), CSS tag and class selectors (`body`, `.card`), diff hunk headers (`@@ ... @@`), Markdown H2 |
| **Solarized Violet**| `#6C71C4` | Aspects, annotations, attributes, modules & imports | `@Service`, `@dataclass`, `#[derive]`, `[[nodiscard]]`, CSS pseudo-classes/elements (`:root`, `:hover`, `::before`), `import`, `from`, `use`, `package main`, Markdown H3 |
| **Solarized Magenta**| `#D33682`| Constants, literals, hashes, sentinels, receivers | `1024`, `nil`, `null`, `None`, `true`, `false`, TOML date-times (`2025-09-14T08:30:00Z`), Java Properties numbers and booleans, CSS hex colors (`#002b36`), XML entity references (`&amp;`), `ALL_CAPS` constants, `this`, `self`, PSReadLine numbers |
| **Solarized Cyan**  | `#2AA198` | Strings, filesystem paths, struct tags, format placeholders | `"Hello %s\n"`, paths, markdown link URLs, XML attribute strings, Java Properties strings, format specifiers (`%s`, `%d`), PSReadLine strings |
| **Solarized Orange**| `#CB4B16` | Directives, preprocessor macros, shebang | `#define`, `#include`, `#!/bin/bash`, CSS at-rules (`@layer`, `@keyframes`, `@media`, `@container`), XML processing instructions (`<?xml ... ?>`), Markdown H1 |
| **Base01 Dim**      | `#586E75` | Comments, subtle metadata, structural delimiters | `// comments`, Java Properties comments (`#`), bat frames, tree connectors, Markdown markers, inactive line numbers, PSReadLine comments & predictions |

---

### The Higher-Order Architectural Pillars (Windows Developer Workstation)

1. **Pillar I: The 3-Tier Semantic Color Contract & Canvas Tranquility**
   - **Tier 1: Monotone Ground (70–80% screen area)** — Base0 (`#839496`) & Base01 (`#586E75`): Standard typed text, CLI arguments, paths, struct fields, custom domain types (`OrderRecord`, `Context`), schema relations, routine invocations (`printf()`, `.stream()`), operators (`+`, `==`), parameters, delimiters, and comments.
   - **Tier 2: Structural Anchors (15–20% screen area)** — Green scaffolding and declarations, Yellow exclusive to control flow (`if`, `return`, `for`, `switch`), Blue function declarations and TOML section headers, Violet annotations and imports (`@Service`, `#[derive]`).
   - **Tier 3: Values & Directives (5–10% screen area)** — Cyan strings and paths, Magenta constants, numeric literals, and booleans, Orange preprocessor macros and Markdown H1.
   - **Monochromatic UI Chrome**: Gutter coordinates strictly employ pure luminance contrast (active `CursorLineNr` in Base1 Bold `#93A1A1` on `base02` `#073642`, inactive `LineNr` in Base01 `#586E75`), split dividers (`WinSeparator`, `VertSplit`) and floating popup borders (`FloatBorder`) strictly in Base01, delimiter matching (`MatchParen`) in Base1 on Base02 without syntax mutation, and non-mutating `sp` underlines for diagnostics.

2. **Pillar II: Operational Role Invariance (Runtime Semantics over Static Syntax)**
   - Function declarations are structural landmarks in Blue (`#268BD2`); function/method invocations rest calmly on the Base0 Grey (`#839496`) canvas.
   - Factory functions (like Go `NewClusterNode`) remain invocations in calm Base0 Grey, never flipping to Yellow.
   - Sentinels (`null`, `nil`, `None`, `_`) strictly classify as constants in Solarized Magenta (`#D33682`).

3. **Pillar III: Gestalt Semantic Continuity & Atomic Compound Enclosure**
   - String payloads, interpolation wrappers, and format specifiers (`%s`, `\n`) form a single continuous entity in Solarized Cyan (`#2AA198`).
   - Compound enclosures (attributes `#[derive]`, `[[nodiscard]]`, `@Override`, Go struct tags) remain unified in their primary accent without token fracturing.
   - Diff lines form a single semantic mutation in continuous Green (`+`) or Red (`-`).

4. **Pillar IV: Navigational Neutrality (Qualifiers, Sigils, and Scope Boundaries)**
   - Scope qualifiers (`std::`, `boost::`, `context.`, `fmt.`) serve navigational routing and remain in calm Base0 Grey (`#839496`), while formal definition sites receive Violet (`#6C71C4`).
   - Shell parameter expansions and PowerShell variable prefixes strictly remain calm Base0.

5. **Pillar V: Pushdown Automata State Machine Engineering (`bat` / Sublime Syntaxes)**
   - Standalone, 100% self-contained grammar specifications in `config/bat/syntaxes/` (`Bash`, `C`, `C++`, `CSS`, `Diff`, `Go`, `HTML`, `Java`, `Java Properties`, `JSON`, `Markdown`, `Python`, `Rust`, `SQL`, `Terraform`, `TOML`, `TypeScript`, `XML`).
   - Pushdown transitions consume opening delimiters and avoid lookahead traps; contextual keywords are guarded by syntax lookarounds to prevent false control flow matching.

6. **Pillar VI: Tree-sitter AST Query Hierarchy & Cascade Engineering (Neovim)**
   - Root fallback captures strictly mirror the universal color contract (`@function.call = Base0`, `@keyword.import = Violet`, `@variable.builtin = Magenta`).
   - Single source of truth query architecture: base query supersedure in `config/nvim/queries/` without `;; extends` (eliminates rogue `url` metadata and broad selector swallowing), and runtime extensions in `config/nvim/after/queries/` with `;; extends`.
   - Document-order rule precedence ensures generic catch-all patterns precede specialized predicate captures.
   - Diagnostic squiggles isolate severity through underline color (`sp`), with `fg = "NONE"` preventing syntax color corruption.

7. **Pillar VII: Standalone Subsystem Independence & LTS Currency**
   - Decoupled from packaging lag through version-controlled grammars in `config/bat/syntaxes/` and query overrides in `config/nvim/`.
   - Polyglot runtimes declaratively pinned in `mise.toml` (`java = "lts"`, `node = "lts"`, `go = "latest"`, `tree-sitter = "latest"`).

8. **Pillar VIII: Workstation Visual Hierarchy & Spatial Typography**
   - 4-layer terminal canvas: Layer 0 (Canvas Ground `#002B36`), Layer 1 (Structural Chrome & Enclosures `#073642` / `#586E75`), Layer 2 (Monotone Ground `#839496`), Layer 3 (Semantic Accents).
   - Interactive shell prompts (Oh My Posh) sit on an authentic Base02 (`#073642`) dark teal shelf with thin directional chevrons (`\uE0B1` on left, `\uE0B3` on right in `#657B83`) maintaining horizontal momentum toward solid wedge caps (`\uE0B0` / `\uE0B2`).
   - Enforces 3-Tier Prompt Luminance Hierarchy: Frame Base01 < Separator Base00 < OS Icon Base0 (`#839496`), eliminating high-contrast pearl white icons that outshine directory navigation.

9. **Pillar IX: Multi-Tool Precedence & Filesystem Color Parity**
   - Multi-tool cascade: explicit glob in `LS_COLORS` $\gg$ explicit glob in `EZA_COLORS` $\gg$ 2-letter family code $\gg$ default.
   - Hardware-level ANSI slot discipline: archives in bright slot 9 (ANSI `91` Orange), media in bright slot 13 (ANSI `95` Violet), crypto keys/certificates in slot 5 (ANSI `35` Magenta).
   - Spatial domain isolation: crypto keys (`.key`, `.pem`, `.crt`, `cr`) strictly share Magenta (`#D33682`), isolated from Blue directories and Orange archives.

---

### Concrete Tooling Implementations

1. **`bat` (Syntect CLI File Viewer)**:
   - Compiled theme cache via `bat cache --build` using `config/bat/Solarized-Dark-TrueColor.tmTheme`.
   - Standalone modern Sublime grammars deployed from `config/bat/syntaxes/` to `%APPDATA%\bat\syntaxes\`.
   - Available via `bat` or `cat` alias with `--theme="Solarized-Dark-TrueColor"`. `$env:BAT_OPTS = '--italic-text=always'`.

2. **Neovim (Native LSP & Tree-sitter Editor)**:
   - Uses `maxmx03/solarized.nvim` with `variant = "spring"` matching `bat` 1:1.
   - Deploys full query tree to `%LOCALAPPDATA%\nvim\`: base supersedures in `queries/` (`css`, `html`, `html_tags`, `properties`, `xml`) and additive extensions in `after/queries/` (`bash`, `c`, `cpp`, `diff`, `go`, `java`, `javascript`, `markdown`, `markdown_inline`, `printf`, `python`, `rust`, `sql`, `terraform`, `toml`, `typescript`, `xml`).
   - Non-language UI chrome: Gutter line numbers in monochromatic luminance (`CursorLineNr` in Base1 Bold on Base02), split and float borders in Base01, `MatchParen` in Base1 on Base02, `Search` in `mix_yellow` distinct from `Visual` in `mix_base1`, 4-tier diagnostic ladder, and subtle dark diff background tints.
   - Dedicated `ftplugin/java.lua` for on-demand `nvim-jdtls` with cross-platform cache resolution.

3. **Fallback Legacy Vim (`_vimrc`)**:
   - Zero-dependency, self-contained configuration in `config/vim/_vimrc` deployed to `$HOME\_vimrc` and `$HOME\.vimrc`.
   - Built-in portable Solarized Dark fallback function `s:ApplySolarizedDark()` configuring complete TrueColor GUI and 16/256-color cterm attributes without external plugins.

4. **`eza` (Modern Directory Listing)**:
   - Configured via aliases `e`, `el`, `elm`, `et`, `elt`, `elx` with unbolded 83-code TrueColor Solarized Dark palette in `$env:EZA_COLORS` and `$env:EXA_COLORS`: tree connectors Base01 (`xx=38;2;88;110;117`), directories Blue (`di=38;2;38;139;210`), executables Green (`ex=38;2;133;153;0`), documents/code Base0 (`fi`, `sc`, `do` in `38;2;131;148;150`), media Violet (`im`, `vi`, `mu`, `lo` in `38;2;108;113;196`), archives Orange (`co=38;2;203;75;22`), crypto Magenta (`cr=38;2;211;54;130`), table header underline Base1 (`hd=4;38;2;147;161;161`), block/char devices unbolded Magenta (`bd=38;2;211;54;130:cd=38;2;211;54;130`).

5. **GNU coreutils `ls` & `dircolors` (`$env:LS_COLORS`)**:
   - Configured via `config/colors/LS_COLORS` matching GNU dircolors: directories in Blue (`DIR 34`), executables in Green (`EXEC 32`), symlinks in Cyan (`LINK 36`), regular text/code in calm Base0 (`FILE 00`, `.c 00`, `.py 00`, `.md 00`, `.txt 00`), media in Violet (`95`), archives in Orange (`91`), crypto in Magenta (`35`), backups in dim Base01 (`90`).

6. **Oh My Posh Solarized Dark Prompt (`p10k_single_line.omp.json`)**:
   - Single-line Powerline prompt with compiled disk caching (`$HOME\.cache\powershell\omp_init.ps1`).
   - Both left and right prompts unified on authentic Base02 (`#073642`) dark teal shelf.
   - OS icon in calm Base0 (`#839496`), directories in Blue (`#268BD2`), Git VCS status in Green/Yellow/Orange reflecting repository state, persistent right status anchor (`` in Solarized Green `#859900` on success, `` in Solarized Red `#DC322F` on error) mirroring `home-settings`, and right prompt toolchains (Node, Go, Python, Dotnet, Rust) rendering in domain-semantic accents on Base02.

7. **PSReadLine & FZF**:
   - PSReadLine TrueColor syntax highlighting matching Solarized Dark palette.
   - Interactive history search (`Ctrl+R`) integrated with `fzf` using authentic Solarized Dark theme (`$env:FZF_DEFAULT_OPTS`) and ripgrep/fd file finding (`$env:FZF_DEFAULT_COMMAND`).

8. **Mise Toolchains & Go Isolation**:
   - Declarative developer toolchains in `mise.toml` (`glow = "latest"`, `tree-sitter = "latest"`, `go = "latest"`, `node = "lts"`, `python = "latest"`, `rust = "latest"`, `neovim = "latest"`, `eza = "latest"`, `bat = "latest"`).
   - Explicit Go environment isolation (`go.set_gobin = false`, `go.set_gopath = false`).

---

## 6. Developer Shortcuts & Editor Suite

- **Maintain Kebab-Case Naming with Backward Compatibility**:
  - Maintain the full Git plugin suite: `gco`, `gcb`, `gcm`, `ga`, `gaa`, `gst`, `gss`, `gd`, `gds`, `gl`, `gp`, `gb`, `gba`, `gbd`, `gsta`, `gstp`, `gstl`, `glog`, `glo`, `grb`, `gcommit`, `gamend`, `gup`, `gprune`, `gsync`, `guser-branch`.
  - Maintain developer shortcuts: `go-testall`, `go-buildall`, `go-lint`, `yaml-lint`, `fs`, `Format-PathTree`, `ls`, `ll`, `la`, `l`, `lt`, `e`, `el`, `elm`, `et`, `elt`, `elx`.
  - Modern `eza` listing aliases (`el`, `elm`, `elt`, `elx`) format timestamps with `--time-style=long-iso` and show file group ownership (`--group`).
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
   Ensure all **tests pass across all 8 test modules**:
   - `[1/8]` PowerShell Script & Module Syntax
   - `[2/8]` JSON, YAML & Manifest Validity (`configuration.dsc.yaml`, `p10k.omp.json`, `settings.json`, fragments)
   - `[3/8]` WindowsSettings Module Import & Function Exports
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
