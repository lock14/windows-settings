# Agent Guidelines for windows-settings

This repository contains workstation configuration files, a 17-theme 24-bit TrueColor palette engine, prompt themes, a cross-platform Zellij 0.46+ + Neovim Named Pipe RPC IDE & AI agent fleet manager, CLI tab completions, and setup automation for **PowerShell 7+**, **Zellij**, **Oh My Posh**, **Neovim**, **Command Prompt (`cmd.exe`)**, and **Windows Terminal** on Windows.

Any agent modifying this repository must follow these core principles and constraints.

---

## 1. Repository Architecture & Component Map

| Component | Repository Path | Target Location on System | Purpose |
| :--- | :--- | :--- | :--- |
| **PowerShell Module** | `module/` | `$HOME\Documents\PowerShell\Modules\WindowsSettings\` | Autoloaded shell functions (82 exports), aliases, Git safety tools, completions, async PR/theme sync, `<10ms` loader |
| **PowerShell Profile** | `config/powershell/Microsoft.PowerShell_profile.ps1` | `$PROFILE` | Minimal 1-line profile importing `WindowsSettings` |
| **Oh My Posh Prompt** | `config/powershell/p10k_single_line.omp.json` | `$HOME\.poshthemes\p10k_single_line.omp.json` | Base02 shelf prompt theme with compiled disk caching, holiday icons, & clickable OSC 8 `<branch>@<N>` PR badges |
| **17-Theme Palette Specs** | `config/themes/` | `$HOME\.config\windows-settings\themes\` | 17 built-in 24-bit TrueColor `.theme` specs (9 classic palettes + 8 US Holiday themes) + custom user theme support |
| **Neovim Configuration** | `config/nvim/init.lua`, `lazy-lock.json` | `$env:LOCALAPPDATA\nvim\` | Neovim 0.11+ / 0.12+ Lua config (Lazy.nvim, Native LSP, 17-theme `:Theme`, Named Pipe IDE RPC, `render-markdown.nvim`, `mini.files`) |
| **Neovim Queries & Tree-sitter** | `config/nvim/queries/`, `after/`, `ftplugin/` | `$env:LOCALAPPDATA\nvim\` | 43 dedicated AST highlight `.scm` queries (13 base + 30 extensions) & Java filetype plugin matching Universal Color Contract |
| **Legacy Vim Config** | `config/vim/_vimrc` | `$HOME\_vimrc` & `$HOME\.vimrc` | Zero-dependency standalone fallback configuration with inline 17-theme engine & `:Theme` command |
| **Command Prompt AutoRun** | `config/cmd/autorun.cmd` | `%LOCALAPPDATA%\cmd\autorun.cmd` | Zero-dependency native `cmd.exe` AutoRun environment, UTF-8 Base02 Powerline shelf prompt, dynamic `theme_env.cmd` hook, `cmd.d\` drop-ins, and `doskey` macros |
| **Zellij Workspace & Themes** | `config/zellij/` | `%APPDATA%\Zellij\config\` | Declarative Zellij `0.46+` `config.kdl`, `ide-3pane` / `ide-2pane` KDL layouts, `windows-settings.kdl` theme, `OSC 7501` Attention Inbox, & 1-hop GPU `terminal` config |
| **Terminal Fragments** | `config/terminal/windows-settings.json`, `settings.json` | `%LOCALAPPDATA%\Microsoft\Windows Terminal\Fragments\WindowsSettings\` | Zero-touch Windows Terminal JSON Fragment extension with all 17 TrueColor schemes & clean `Alt+*` pass-through to Zellij |
| **TrueColor Themes & Syntaxes** | `config/bat/` & `config/colors/` | `%APPDATA%\bat\` & `$env:LS_COLORS` | 17 `*-TrueColor.tmTheme` files, 37 standalone `.sublime-syntax` grammars, and 40-language calibrated `LS_COLORS` |
| **Modern CLI Configs** | `config/git/`, `btop/`, `tealdeer/`, `clangd/` | User config & `%APPDATA%` directories | Declarative configs for `delta` (`delta.gitconfig`), `btop4win` (`btop.conf` + 17 themes), `tealdeer`, and `clangd` |
| **Native User Binaries** | `bin/` | Registered in User `$env:Path` | 7 dual-execution CLI utilities (`gen-passwd`, `ide`, `install-nerd-fonts`, `repeat-until-success`, `sum`, `theme`, `update-system`) as `<name>.ps1` + `<name>.cmd` |
| **Polyglot Sample Code** | `sample-code/` | Repository validation suite | 40 real-world sample files across languages for syntax & Tree-sitter query evaluation |
| **Package Declarations** | `configuration.dsc.yaml` & `mise.toml` | System Provisioning | Microsoft DSC v3 and Mise declarative package & polyglot runtime specifications |
| **Automation Scripts** | `setup.ps1`, `bootstrap.ps1` | Root orchestrators | Declarative provisioning, theme synchronization, and clean uninstallation runners supporting `-DryRun` |
| **Agent & LLM Context** | `AGENTS.md`, `llms.txt` | Repository root | Canonical agent guidelines (single root `AGENTS.md`) and concise `llms.txt` LLM index |
| **Governance & CI** | `LICENSE`, `CONTRIBUTING.md`, `SECURITY.md`, `.github/` | Repository & GitHub | Apache-2.0 license, contributor & security policies, PR/issue templates, Dependabot, CI & Security workflows |
| **Automated Tests** | `tests/test_settings.ps1` | Test Suite | 234+ automated validation tests across 8 modules |

---

## 2. Portability, Line Endings & Path Invariants

- **Never Commit Personal User Paths**: Never hardcode personal paths like `C:\Users\<username>\`, `/Users/<username>/`, or `/home/<username>/` into scripts, configuration files, comments, or documentation.
- **Use Canonical PowerShell & Environment Variables**:
  - User Home: `$HOME` or `$env:USERPROFILE`
  - Local AppData: `$env:LOCALAPPDATA`
  - Roaming AppData: `$env:APPDATA`
  - PowerShell Profile: `$PROFILE`
  - Path Construction: Always use `Join-Path` or `Split-Path` rather than hardcoding string backslashes or slashes.
- **Strict Line-Ending Discipline (`.gitattributes`)**:
  - `.ps1`, `.psm1`, `.psd1`, `.cmd`, and `.bat` files **must** use `CRLF` (`\r\n`) line endings. Critically, `cmd.exe` miscalculates byte offsets after `chcp 65001 >nul` if a `.cmd` script or generated `theme_env.cmd` uses `LF` instead of `CRLF`.
  - `.md`, `.json`, `.kdl`, `.yml`, `.yaml`, `.toml`, `.lua`, `.scm`, `.theme`, `.tmTheme`, `.sublime-syntax`, `.gitconfig`, `.conf`, `.txt`, and `LICENSE` files use `LF` (`\n`) line endings.
- **Windows Terminal Dynamic Resolution & Fragments**:
  - Deploy JSON Fragment extensions under `%LOCALAPPDATA%\Microsoft\Windows Terminal\Fragments\WindowsSettings\` for zero-touch configuration without mutating base `settings.json`.
  - When merging or syncing active schemes into `settings.json`, search dynamically across all possible installation locations (`LocalState`, `Microsoft.WindowsTerminal_8wekyb3d8bbwe`, `Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe`).
- **Dual-Execution Support in `bin/`**:
  - Every native utility script in `bin/` must have both a PowerShell implementation (`<name>.ps1`) and a CMD batch wrapper (`<name>.cmd`) for transparent invocation across PowerShell, `cmd.exe`, and external tools.

---

## 3. Destructive Safety, Idempotent Backups & Clean Uninstall

- **Mandatory Non-Destructive Backups**:
  - Any installation or setup script (`setup.ps1`, `bootstrap.ps1`) must create a timestamped backup (`.bak_<timestamp>`) before overwriting or modifying an existing user configuration file (e.g. Windows Terminal `settings.json`, PowerShell `$PROFILE`, Neovim `init.lua`).
- **Strict Idempotency Requirement**:
  - Running setup scripts repeatedly must not corrupt configuration files, create duplicate profile blocks or duplicate `git config --global include.path` entries, or generate redundant backups when file content has not changed.
  - Sourcing profiles or re-running installers must be safe to execute multiple times in the same session.
- **Support `-DryRun`, `-Theme`, `-Uninstall*`, and Modular Switches**:
  - All provisioning, theme-switching, and uninstall logic in `setup.ps1`, `bootstrap.ps1`, `bin/theme.ps1`, `bin/ide.ps1`, and `bin/update-system.ps1` must support `-DryRun` / `--dry-run` preview mode without mutating files, registry entries, or system state.
  - Provide modular execution switches: `-Bootstrap`, `-DotfilesOnly`, `-SystemOnly`, `-UseDSC`, `-WithGUI`, `-Theme <slug|holiday>`, and clean removal switches `-Uninstall`, `-UninstallDotfiles`, `-UninstallFonts`, `-UninstallBin`.
- **Preserve Unrelated User Configuration**:
  - When modifying configuration files (e.g., Windows Terminal `settings.json`, PowerShell `$PROFILE`, global `.gitconfig`), preserve existing user custom profiles, keybindings, actions, or third-party settings unless explicitly instructed to overwrite them.
- **Graceful Failure & Error Handling**:
  - Use `$ErrorActionPreference = 'Stop'` in automation scripts.
  - Validate prerequisites (`winget`, `zellij`, `oh-my-posh`, `fzf`, `git`, `gh`, `wt`) gracefully, emitting clear instructions or warnings when a tool is not present rather than hard-crashing.

---

## 4. Shell Performance & Architecture Invariants

- **High-Speed Shell Startup (<10ms Target)**:
  - The shell configuration is packaged as an autoloaded PowerShell Module (`WindowsSettings.psd1`).
  - `$PROFILE` must remain minimal: `Import-Module WindowsSettings -DisableNameChecking -ErrorAction SilentlyContinue`.
  - **No Dynamic Disk Traversal in `psm1`**: Never use `Get-ChildItem -Recurse` inside module startup paths. All public/private module scripts are sourced explicitly; local drop-in hooks (`$HOME\.config\windows-settings\{env,aliases,functions}.d\*.ps1`) use flat single-directory checks only when the directory exists.
  - **No Dynamic `Get-Command` Loops**: Never run `Get-Command` scans across all PATH directories during shell startup. Use statically known binary names and direct command calls.
  - **Compiled Disk Caching & Non-Blocking Background Sync**:
    - Heavy prompt and engine initializations (`oh-my-posh init`, `zoxide init`, `gh completion`, active `theme_env.ps1`) are cached as compiled `.ps1` files under `$HOME\.cache\powershell\` (and `$HOME\.cache\windows-settings\`) to avoid spawning sub-processes on every new shell tab.
    - Prompt wrappers (`global:prompt`) synchronize cross-pane theme changes via lightweight file-timestamp checks on `theme` and `p10k_single_line.omp.json`. **Crucially**, Oh My Posh caches compiled prompt colors per `$env:POSH_SESSION_ID` (`pwsh.<UUID>.omp.cache`) and inside any active `oh-my-posh serve` daemon (`$global:_ompStreamingState.ServeProcess`); whenever the active theme changes, both `bin/theme.ps1` and `Sync-PromptDynamicState` must delete the stale `pwsh.<oldId>.omp.cache`, rotate `$env:POSH_SESSION_ID`, and reset `$global:_ompStreamingState.ServeProcess` so prompt colors repaint immediately in live and cross-pane sessions.
    - Prompt wrappers also refresh `<branch>@<N>` GitHub/GitLab PR badges asynchronously in the background without blocking prompt rendering.
- **Un-Aliasing Conflicting Legacy Cmdlets & Raw `cat` Parity**:
  - Automatically un-alias conflicting PowerShell cmdlets (`cat`, `sort`, `tee`, `diff`, `echo`, `sleep`, `ls`, `gcm`, `gl`, `gp`) so modern tools (`uutils-coreutils`, `eza`, Git aliases) execute without prefixing `&`.
  - Matching `home-settings`, `cat` is left un-wrapped so `uutils-coreutils` `cat.exe` runs natively with zero paging/decoration surprises, while `b` invokes `bat` (`autorun.cmd` also runs `doskey cat=` to clear any legacy `cat` macro).
- **PSScriptAnalyzer Compliance**:
  - All PowerShell scripts (`.ps1`, `.psm1`, `.psd1`) must pass static analysis configured in `PSScriptAnalyzerSettings.psd1` with zero errors or warnings.

---

## 5. Multi-Theme TrueColor Engine & Solarized Dark Precision

By default, all visual components across the terminal, shell, prompt, file viewers, and editor adhere strictly to the authentic **Solarized Dark** palette (Ethan Schoonover specification), while the unified **17-Theme Palette Engine (`bin/theme.ps1`)** generalizes the exact same semantic role mapping across **9 classic palettes** (`solarized-dark`, `solarized-light`, `catppuccin-mocha`, `catppuccin-latte`, `gruvbox-dark`, `tokyonight-night`, `kanagawa-wave`, `nord`, `onedark`), **8 US Holiday themes** (`new-years`, `valentines`, `st-patricks`, `easter`, `independence-day`, `halloween`, `thanksgiving`, `christmas`), and custom user `.theme` definitions (`--create`).

### Canonical Default Palette Reference (Solarized Dark)
| Role | Color Name | Hex Code | Purpose / Usage |
| :--- | :--- | :--- | :--- |
| **Base Background** | `base03` | `#002B36` | Terminal background, Neovim background, bat background |
| **Current Line / Alt Bg** | `base02` | `#073642` | CursorLine, selection background, prompt shelf, line highlight |
| **Comments / Dim Borders** | `base01` | `#586E75` | Code comments (italic), eza tree connectors (`xx`), prompt dim elements, bat borders |
| **Subtle Text** | `base00` | `#657B83` | Secondary text, thin prompt chevrons, status indicators |
| **Standard Foreground** | `base0` | `#839496` | Standard typed text, CLI arguments, paths, struct fields, invocations, identifiers |
| **Emphasis Text** | `base1` | `#93A1A1` | Bright text, active `CursorLineNr`, highlighted labels |
| **Light Tone (Paper)** | `base2` / `base3` | `#EEE8D5` / `#FDF6E3` | Light background references (primary surfaces in light themes) |
| **Control Flow & Jumps**| `yellow` | `#B58900` | `if`, `return`, `for`, `while`, `switch`, `case`, `select`, `defer`, `match`, `try`, `throw`, `yield`, `await`, PSReadLine control flow keywords |
| **Structural & Declarations**| `green` | `#859900` | `package`, `func`, `var`, `type`, `struct`, primitive types (`int`, `string`, `bool`), JSON/YAML/TOML keys, PSReadLine commands & types |
| **Functions & Methods** | `blue` | `#268BD2` | Function declarations, directory names, TOML/INI section headers, Markdown H2 |
| **Strings & Paths** | `cyan` | `#2AA198` | String literals, paths, struct tags, format specifiers, PSReadLine strings |
| **Numbers & Constants** | `magenta` | `#D33682` | Numeric literals, `nil`, `true`, `false`, `iota`, `self`/`this`, crypto files, PSReadLine numbers |
| **Operators & Mechanics**| `violet` | `#6C71C4` | Annotations, attributes, module imports (`import`, `use`), media files, Markdown H3 |
| **Preprocessors & Headers**| `orange` | `#CB4B16` | Preprocessor macros, compiler directives, CSS at-rules, archives, Markdown H1 |
| **Errors & Diagnostics** | `red` | `#DC322F` | Syntax errors, diff deletions, error status anchors, diagnostic errors |

### Universal Semantic Color Contract
Colors across the developer workstation fulfill invariant domain roles across all 40 supported languages, tools, and filetypes (and translate 1:1 through every `.theme` slot when switching themes via `theme`):

| Palette Slot | Default Hex | Universal Semantic Role | Manifestations Across Languages & Tools |
| :--- | :--- | :--- | :--- |
| **Yellow (`YELLOW`)** | `#B58900` | Uncontested control flow & jumps | `if`, `return`, `for`, `while`, `switch`, `case`, `select`, `defer`, `match`, `try`, `throw`, `yield`, `await`, `CASE/WHEN` (exclusive to control flow, never in Markdown headings, declarative data/config documents, CSS stylesheets, or Java Properties) |
| **Green (`GREEN`)** | `#859900` | Structural scaffolding, declarations, static primitive types & core built-ins, diff additions | `int`, `double`, `u64`, `usize`, `bool`, `void`, Python built-in types (`int`, `str`, `float`, `bool`, `list`, `dict`, `set`, `tuple`), `func`, `fn`, `def`, `class`, `struct`, `interface`, `var`, `let`, `const`, `typedef`, `CREATE TABLE`, SQL data types, JSON/YAML/TOML/Properties keys, XML/HTML attribute names, CSS property names, `+` added lines, PSReadLine commands |
| **Base0 (`BASE0`)** | `#839496` | Neutral ground, custom domain types, schemas, invocations, operators | Custom domain types (`OrderRecord`, `Context`, `HashMap`, `Instant`), schema relations, function/method calls (`printf()`, `.stream()`), CSS custom properties & functions (`var()`, `clamp()`), XML/HTML/TOML/Properties delimiters, parameters, operators, PSReadLine arguments |
| **Blue (`BLUE`)** | `#268BD2` | Routine declarations & structural headers | `func New...`, `fn find...`, `def __init__`, XML element tags, TOML table section headers (`[package]`), CSS tag and class selectors, diff hunk headers (`@@ ... @@`), Markdown H2 |
| **Violet (`VIOLET`)** | `#6C71C4` | Aspects, annotations, attributes, modules & imports | `@Service`, `@dataclass`, `#[derive]`, `[[nodiscard]]`, CSS pseudo-classes/elements (`:root`, `:hover`), `import`, `from`, `use`, `package main`, Markdown H3 |
| **Magenta (`MAGENTA`)**| `#D33682` | Constants, literals, hashes, sentinels, receivers | `1024`, `nil`, `null`, `None`, `true`, `false`, TOML date-times, CSS hex colors, XML entity references, `ALL_CAPS` constants, `this`, `self`, PSReadLine numbers |
| **Cyan (`CYAN`)** | `#2AA198` | Strings, filesystem paths, struct tags, format placeholders | `"Hello %s\n"`, paths, markdown link URLs, XML attribute strings, format specifiers (`%s`, `%d`), PSReadLine strings |
| **Orange (`ORANGE`)** | `#CB4B16` | Directives, preprocessor macros, shebang | `#define`, `#include`, `#!/bin/bash`, CSS at-rules (`@layer`, `@media`), XML processing instructions (`<?xml ... ?>`), Markdown H1 |
| **Base01 (`BASE01`)** | `#586E75` | Comments, subtle metadata, structural delimiters | `// comments`, `#` comments, `bat` frames, `eza` tree connectors, Markdown markers, inactive line numbers, PSReadLine comments & predictions |

---

### The Higher-Order Architectural Pillars (Windows Developer Workstation)

1. **Pillar I: The 3-Tier Semantic Color Contract & Canvas Tranquility**
   - **Tier 1: Monotone Ground (70–80% screen area)** — `BASE0` & `BASE01`: Standard typed text, CLI arguments, paths, struct fields, custom domain types, schema relations, routine invocations, operators, parameters, delimiters, and comments.
   - **Tier 2: Structural Anchors (15–20% screen area)** — Green scaffolding and declarations, Yellow exclusive to control flow, Blue function declarations and section headers, Violet annotations and imports.
   - **Tier 3: Values & Directives (5–10% screen area)** — Cyan strings and paths, Magenta constants, numeric literals, and booleans, Orange preprocessor macros and Markdown H1.
   - **Monochromatic UI Chrome**: Gutter coordinates strictly employ pure luminance contrast (active `CursorLineNr` in `BASE1` Bold on `BASE02`, inactive `LineNr` in `BASE01`), split dividers (`WinSeparator`, `VertSplit`) and floating popup borders (`FloatBorder`) strictly in `BASE01`, delimiter matching (`MatchParen`) in `BASE1` on `BASE02` without syntax mutation, and non-mutating `sp` underlines for diagnostics.

2. **Pillar II: Operational Role Invariance (Runtime Semantics over Static Syntax)**
   - Function declarations are structural landmarks in Blue; function/method invocations rest calmly on the `BASE0` canvas.
   - Factory functions (like Go `NewClusterNode`) remain invocations in calm `BASE0`, never flipping to Yellow.
   - Sentinels (`null`, `nil`, `None`, `_`) strictly classify as constants in Magenta.

3. **Pillar III: Gestalt Semantic Continuity & Atomic Compound Enclosure**
   - String payloads, interpolation wrappers, and format specifiers (`%s`, `\n`) form a single continuous entity in Cyan.
   - Compound enclosures (attributes `#[derive]`, `[[nodiscard]]`, `@Override`, Go struct tags) remain unified in their primary accent without token fracturing.
   - Diff lines form a single semantic mutation in continuous Green (`+`) or Red (`-`), enhanced in `delta` via `MIX_GREEN` / `MIX_RED` subtle line backgrounds.

4. **Pillar IV: Navigational Neutrality (Qualifiers, Sigils, and Scope Boundaries)**
   - Scope qualifiers (`std::`, `boost::`, `context.`, `fmt.`) serve navigational routing and remain in calm `BASE0`, while formal definition sites receive Violet.
   - Shell parameter expansions and PowerShell variable prefixes strictly remain calm `BASE0`.

5. **Pillar V: Pushdown Automata State Machine Engineering (`bat` / Sublime Syntaxes)**
   - 37 standalone, 100% self-contained `.sublime-syntax` grammar specifications in `config/bat/syntaxes/` covering the 40-language polyglot suite (`sample-code/`).
   - Pushdown transitions consume opening delimiters and avoid lookahead traps; contextual keywords are guarded by syntax lookarounds to prevent false control flow matching.

6. **Pillar VI: Tree-sitter AST Query Hierarchy & Cascade Engineering (Neovim)**
   - Root fallback captures strictly mirror the universal color contract (`@function.call = Base0`, `@keyword.import = Violet`, `@variable.builtin = Magenta`).
   - Single source of truth query architecture across 43 `.scm` files: 13 base query supersedures in `config/nvim/queries/` without `;; extends` (`css`, `dockerfile`, `elixir`, `graphql`, `html`, `html_tags`, `lean`, `markdown_inline`, `properties`, `proto`, `rego`, `textproto`, `xml` — zero `(#set! "url"` metadata), and 30 runtime extensions in `config/nvim/after/queries/` with `;; extends`.
   - Document-order rule precedence ensures generic catch-all patterns precede specialized predicate captures.
   - Diagnostic squiggles isolate severity through underline color (`sp`), with `fg = "NONE"` preventing syntax color corruption.

7. **Pillar VII: Standalone Subsystem Independence & LTS Currency**
   - Decoupled from packaging lag through version-controlled grammars in `config/bat/syntaxes/`, theme engines in `bin/theme.ps1`, and query overrides in `config/nvim/`.
   - Polyglot runtimes and modern Rust/Go CLI tools declaratively pinned in `mise.toml` (`bat`, `delta`, `dust`, `elan`, `eza`, `fd`, `fzf`, `gh`, `glow`, `go`, `java`, `jq`, `neovim`, `node`, `python`, `ripgrep`, `rust`, `sd`, `tealdeer`, `tree-sitter`, `yq`, `zellij`, `zoxide`).

8. **Pillar VIII: Workstation Visual Hierarchy & Spatial Typography**
   - 4-layer terminal canvas: Layer 0 (Canvas Ground `BASE03`), Layer 1 (Structural Chrome & Enclosures `BASE02` / `BASE01`), Layer 2 (Monotone Ground `BASE0`), Layer 3 (Semantic Accents).
   - Interactive shell prompts (Oh My Posh & `autorun.cmd`) sit on the `BASE02` shelf with thin directional chevrons (`\uE0B1` on left, `\uE0B3` on right in `BASE00`) maintaining horizontal momentum toward solid wedge caps (`\uE0B0` / `\uE0B2`).
   - Enforces 3-Tier Prompt Luminance Hierarchy: Frame `BASE01` < Separator `BASE00` < OS Icon `BASE0` (with automatic holiday glyph override via `_HS_PROMPT_OS_ICON` during US Holiday themes).

9. **Pillar IX: Multi-Tool Precedence & Filesystem Color Parity**
   - Multi-tool cascade: explicit glob in `LS_COLORS` $\gg$ explicit glob in `EZA_COLORS` $\gg$ 2-letter family code $\gg$ default.
   - Hardware-level ANSI slot discipline: archives in bright slot 9 (ANSI `91` Orange), media in bright slot 13 (ANSI `95` Violet), crypto keys/certificates in slot 5 (ANSI `35` Magenta).
   - Spatial domain isolation: crypto keys (`.key`, `.pem`, `.crt`, `cr`) strictly share Magenta, isolated from Blue directories and Orange archives.

---

### Concrete Tooling Implementations

1. **Unified Theme Engine (`bin/theme.ps1` + `bin/theme.cmd`)**:
   - Pure PowerShell 7 implementation (zero Python dependency) managing 17 built-in `.theme` definitions plus user-created custom themes (`--create <slug> --from <base>`).
   - Supports `--list`, `--plain`, `--current`, `--set`, `--preview`, `--holiday` (US federal/cultural holiday date engine with `$env:THEME_HOLIDAY_DATE` override), `--env`, `--path`, `--sync-assets`, `--dry-run`, `--no-live`, and interactive `fzf` TrueColor live preview picker.
   - Live-updates Zellij (`themes/windows-settings.kdl` + bounded `tray_badge_colors` and `terminal { theme { ... } }` blocks in `config.kdl`), Windows Terminal schemes, OSC 4/10/11/12 terminal palette slots, all running Neovim Named Pipe servers (`\\.\pipe\nvim*`), Oh My Posh (`p10k_single_line.omp.json`), `theme_env.ps1`, CRLF-safe `theme_env.cmd`, `bat`, `delta`, `btop4win`, `tealdeer`, `fzf`, `eza`, `jq`, and `LS_COLORS`.

2. **Hybrid Zellij + Neovim Named Pipe IDE & Agent Fleet Manager (`bin/ide.ps1` + `bin/ide.cmd`)**:
   - Cross-platform counterpart to `home-settings/bin/ide` built on off-the-shelf **Zellij `0.46+`** (`config/zellij/`) and Windows Named Pipe RPC (`\\.\pipe\nvim-ide-<session>`), with zero custom compiled daemons and automatic `--backend wt` Windows Terminal split-pane fallback.
   - `--3pane` launches a frameless Inverted-T workspace (`ide-3pane.kdl`: Top-Left AI Agent, Top-Right Neovim Editor, Bottom full-width PowerShell beneath a 1-line `BASE02` `compact-bar`); `--2pane` (`ide-2pane.kdl`) launches side-by-side AI + Editor; `-d/--detach` spawns detached background agent sessions (`zellij attach --create-background`); `--desktop` launches Zellij's native 1-hop GPU desktop app (`zellij terminal`) with built-in OS System Tray icon & desktop notifications.
   - Native **`OSC 7501` Attention Inbox**: Claude Code and Codex emit `OSC 7501` natively; Antigravity (`agy`) is wired via `~/.gemini/config/hooks.json` (`ide.cmd --agy-hook SessionStart|PreInvocation|Stop`) deployed idempotently by `setup.ps1`.
   - Supports `--ai agy|claude|codex`, `-s/--sessions` (floating `zellij:session-manager` Attention Inbox), `Alt+Shift+S` / `--next-attention` (`GoToNextAttention`), `Alt+a/e/t` / `--focus-role` / `--toggle`, `--open` / `--preview` / `--open-or-edit` (`v [+line] <file>`), synchronized workspace directory diving (`icd` / `:IdeCd`), `<leader>a` / `--send` bracketed-paste prompt injection (`zellij action paste -p`), `--keys` TrueColor cheatsheet, `--monitor`, `--list`, and unsaved-buffer protected `:Q` / `qide` / `quit` (`--quit`).

3. **`bat` & `delta` (Syntect CLI File & Diff Viewers)**:
   - Compiled theme cache via `bat cache --build` deploying all 17 `config/bat/themes/*-TrueColor.tmTheme` palettes and 37 `config/bat/syntaxes/*.sublime-syntax` grammars to `%APPDATA%\bat\`.
   - Available via `bat` or `b` alias (`$env:BAT_OPTS = '--italic-text=always'`), while `config/git/delta.gitconfig` configures `delta` side-by-side/inline TrueColor diffs linked via `git config --global --add include.path`.

4. **Neovim (`config/nvim/init.lua`) & Standalone Vim (`config/vim/_vimrc`)**:
   - Neovim 0.11+ / 0.12+ config with Lazy.nvim (`lazy-lock.json`), Native LSP (`gopls`, `pyright`, `ts_ls`, `rust_analyzer`, `clangd`, `terraformls`, `yamlls`, `leanls`, plus `ftplugin/java.lua`), 43 Tree-sitter `.scm` queries, `render-markdown.nvim`, `mini.files` + `mini.icons`, AST link/TOC navigation, `<X1Mouse>`/`<X2Mouse>` jump navigation, Named Pipe RPC server discovery, and live `:Theme` switcher.
   - Zero-dependency `config/vim/_vimrc` deployed to `$HOME\_vimrc` and `$HOME\.vimrc` with inline 17-theme TrueColor/256-color engine and `:Theme` command.

5. **`eza`, `uutils` `ls`, `btop4win`, `tealdeer` & `clangd`**:
   - `eza` (`e`, `el`, `elm`, `et`, `elt`, `elx`) and `LS_COLORS` (`ls`, `ll`, `la`, `l`) dynamically re-tinted by `bin/theme.ps1` across all 17 palettes.
   - Declarative configs deployed for `btop4win` (`config/btop/btop.conf` + 17 themes), `tealdeer` (`config/tealdeer/config.toml`), and `clangd` (`config/clangd/config.yaml`).

6. **Oh My Posh Prompt (`p10k_single_line.omp.json`) & Command Prompt (`autorun.cmd`)**:
   - Unified on the active theme's `BASE02` shelf with compiled disk caching (`$HOME\.cache\powershell\omp_init.ps1`), dynamic holiday OS icon (`_HS_PROMPT_OS_ICON`), clickable OSC 8 `<branch>@<N>` GitHub/GitLab PR hyperlinks (`_WS_GIT_PR_LABEL` / `_WS_GIT_PR_URL`), and persistent right status anchor (`` / ``).
   - `config/cmd/autorun.cmd` provides 0ms native `cmd.exe` parity (`chcp 65001 >nul`, `FORCE_HYPERLINK=1`, `JQ_COLORS`, dynamic `theme_env.cmd` hook, `cmd.d\*.cmd` drop-ins, `doskey cat=`, and full `doskey` alias parity).

---

## 6. Developer Shortcuts, Aliases & Git Safety Guards

- **Exact `home-settings` Alias & Shortcut Parity**:
  - **File & System Tools**: `b` = `bat` (while `cat` runs raw `uutils` `cat.exe`), `ds` = `dust`, `btop` = `btop4win` fallback, `update` = `update-system`, `theme` = `bin/theme.ps1`.
  - **IDE & Editor Suite**: `ide`, `ide2` (`ide --2pane`), `ide3` (`ide --3pane`), `idek` (`ide --kill`), `qide` / `quit` (`ide --quit`), `icd` (`ide --cd` + shell `Set-Location`), `v` (RPC-aware `ide --open-or-edit` inside IDE sessions, falling back to `nvim`/`vim`), `vi` / `vim` -> `nvim`.
  - **Git Suite & Safety Guards**:
    - Full Git shortcut suite: `gco`, `gcb`, `gcm`, `ga`, `gaa`, `gst`, `gss`, `gd`, `gds`, `gl`, `gp`, `gb`, `gba`, `gbd`, `gsta`, `gstp`, `gstl`, `glog`, `glo`, `grb`, `grbc`, `grba`, `gcommit`, `gamend`, `gup`, `gprune`, `gpurge`, `gsync`, `guser-branch`.
    - **`gprune` vs `gpurge`**: `gprune` safely deletes **merged** local branches only (`git branch -d`) after `git fetch --prune`; `gpurge` force-deletes unmerged local branches (`git branch -D`) with an interactive confirmation prompt (`-Force` / `-y` for non-interactive scripts).
    - **Primary-Branch & Dirty-Tree Guards**: `guser-branch` refuses to rename `main`/`master` and strips redundant `$env:USERNAME/` or `$env:USER/` prefixes; `gsync` checks for uncommitted changes before rebasing onto `origin/main` or `origin/master`; `gl`/`gup` use `--rebase --autostash` and `gp` auto-sets upstream (`-u origin HEAD`) when needed.
  - **Directory & Polyglot Helpers**: `go-testall`, `go-buildall`, `go-lint`, `yaml-lint`, `tf`, `fs`, `Format-PathTree`, `ls`, `ll`, `la`, `l`, `lt`, `e`, `el`, `elm`, `et`, `elt`, `elx` (plus legacy backward-compatible wrappers `go_testall`, `go_buildall`, `go_lint`, `yaml_lint`, `fix-abcxyz-branch-name`).

---

## 7. Component Structure, Multi-File Contracts & Code Style

- **Standardized Multi-File Component Contracts**:
  - **CLI Utility (`bin/`)**: Every tool in `bin/` requires `bin/<name>.ps1` (`CRLF`), `bin/<name>.cmd` (`CRLF`), a wrapper/alias in `module/Utilities.ps1` or `module/Developer.ps1`, an export in `module/WindowsSettings.psd1`, tab completion in `module/Completions.ps1`, a `doskey` macro in `config/cmd/autorun.cmd`, and test coverage in `tests/test_settings.ps1`.
  - **Theme Palette (`config/themes/`)**: Every built-in theme requires `config/themes/<slug>.theme`, synchronized static assets via `bin/theme.ps1 --sync-assets` (`config/bat/themes/*-TrueColor.tmTheme`, `config/btop/themes/*.theme`, `config/terminal/windows-settings.json`, `config/terminal/settings.json`), and a matching entry in standalone `config/vim/_vimrc`.
  - **Language Highlighting**: Every supported language requires a fixture in `sample-code/`, a standalone `.sublime-syntax` grammar in `config/bat/syntaxes/`, a Tree-sitter `.scm` query in `config/nvim/queries/` or `config/nvim/after/queries/`, and an extension mapping in `config/colors/LS_COLORS`.
  - **No Extraneous or Ad-Hoc Files**: Extraneous scratch scripts, temporary patch files, `tmp_*` folders, or `.bak` backups in the repository tree are prohibited. Scratch work belongs strictly in `<appDataDir>\brain\<conversation-id>\scratch\` or `$env:TEMP`.
  - **Single Canonical `AGENTS.md`**: Maintain a single root `AGENTS.md` file (supported natively across Antigravity, Claude Code, and Codex). Do not create duplicate `CLAUDE.md` or `.agents/AGENTS.md` files or symlinks.
- **Internal `.ps1` Script Section Ordering**:
  1. Optional comment-based help (`<# .SYNOPSIS ... #>`), `[CmdletBinding()]`, and `param(...)` block.
  2. `$ErrorActionPreference = 'Stop'` and strict execution settings.
  3. Constants, defaults, and canonical path resolution (`Join-Path` / `Split-Path`).
  4. Private helper functions (singular nouns; avoid state-changing verbs on pure helpers).
  5. `-DryRun` / mode dispatch and main execution entrypoint.
- **Identifier Anti-Shadowing & Encoding Discipline**:
  - Never use parameter or local variable names that shadow PowerShell automatic variables (`$args`, `$input`, `$Host`, `$HOME`, `$PID`, `$PROFILE`, `$Error`, `$Matches`, `$PSItem`).
  - Any `.ps1` file containing literal non-ASCII Unicode characters must include a UTF-8 BOM (or express codepoints via `[char]0x...` / `` "`u{...}" ``) to satisfy `PSUseBOMForUnicodeEncodedFile`.

---

## 8. Documentation Boundaries & Continuous Learning

- **Mandatory Documentation Synchronization**:
  - **Every agent change must update documentation**: Whenever new aliases, functions, CLI utilities, themes, setup parameters, or governance workflows are added or modified, update `README.md`, `AGENTS.md`, `llms.txt`, and (when contributor workflows change) `CONTRIBUTING.md` in the same commit/PR.
- **`README.md` is for Users**:
  - Focus purely on user-facing concerns: prerequisites, quick start commands, architecture overview, theme & IDE workflows, shortcuts tables, and utility usage examples.
- **`AGENTS.md` is for Agents & Maintainers**:
  - Architectural principles, path & line-ending invariant enforcement, multi-file contracts, linter rules, testing procedures, palette specs, and agent workflows belong exclusively in `AGENTS.md`.
- **Persist User Corrections**:
  - Whenever an agent receives feedback, corrections, or instructions regarding repository conventions, it **must immediately encode the underlying principle into `AGENTS.md`** before concluding the task.

---

## 9. Pull Request & CLI Markdown Escaping Conventions

- **Branch Naming & Conventional Commits**:
  - Use clear branch prefixes (`feat/*`, `fix/*`, `perf/*`, `docs/*`, `ci/*`) and concise Conventional Commit messages (`feat:`, `fix:`, `perf:`, `docs:`, `ci:`).
- **Accurate & Synchronized PR Descriptions**:
  - Follow `.github/PULL_REQUEST_TEMPLATE.md` and comprehensively capture all introduced features, CLI flags, performance considerations, and CI/toolchain updates.
  - **PR Description Synchronization**: Whenever subsequent commits in a PR branch modify, fix, or expand upon the original changeset (e.g., CI adjustments, bug fixes, refactoring), proactively update the PR description via `gh pr edit --body-file <path>` so it reflects the latest state of the PR.
- **Avoid Inline Backtick Expansion in PowerShell Commands**:
  - In PowerShell (`pwsh`), the backtick (`` ` ``) is the native escape character.
  - When passing markdown strings containing inline code (e.g. `` `eza` ``, `` `node` ``) within double quotes (`"..."`), PowerShell evaluates the backticks as escape sequences (` `e ` -> ESC, ` `n ` -> newline, ` `t ` -> tab), corrupting GitHub PRs, issues, or commit bodies.
- **Mandatory Safe Markdown Invocation Patterns**:
  1. **File-Based Arguments (`--body-file`)**: When creating or editing PRs/issues via GitHub CLI (`gh`), always write the markdown body to a temporary file first and pass `--body-file <path>`.
  2. **Single-Quoted Strings & Here-Strings**: When passing inline markdown, always enclose it in single quotes (`'...'`) or single-quoted here-strings (`@' ... '@`) where PowerShell performs zero escape interpretation.
  3. **Never Use Double Quotes with Markdown Backticks**: Never execute `gh pr create --body "..."` with embedded backticks.

---

## 10. Verification Checklist for Agents

Before completing any task:
1. **Run Static Analysis**:
   ```powershell
   Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
   ```
   Ensure zero errors or warnings are reported.
2. **Run Test Suite**:
   ```powershell
   $null | pwsh -NoProfile -File ./tests/test_settings.ps1
   ```
   Ensure all **234+ tests pass across all 8 test modules**:
   - `[1/8]` PowerShell Script & Module Syntax
   - `[2/8]` JSON, KDL, YAML, Theme, Query, Governance & Manifest Validity (`configuration.dsc.yaml`, `mise.toml`, `config/zellij/`, `p10k_single_line.omp.json`, `settings.json`, fragments, 17 `.theme` & `.tmTheme` files, 37 `bat` syntaxes, 43 `.scm` queries, `delta`, `tealdeer`, `clangd`, `btop`, `LICENSE`, `CONTRIBUTING.md`, `SECURITY.md`, `llms.txt`, `.github/`)
   - `[3/8]` WindowsSettings Module Import, Aliases & Function Exports (82 functions)
   - `[4/8]` Native CLI Utilities & Pipeline Handling (`sum`, `gen-passwd`, `repeat-until-success`, `theme`, `ide`, `update-system`)
   - `[5/8]` Git Workflow Behavior & Safety Guards (`gsync`, `gprune`, `gpurge`, `guser-branch`, `fix-abcxyz-branch-name`)
   - `[6/8]` Completions, CMD AutoRun & Prompt Rendering (including OSC 8 PR badge rendering)
   - `[7/8]` Path, Byte-Level Line-Ending, Startup Hygiene & Dual Execution Wrappers (all 7 `.ps1` + `.cmd` pairs in `bin/`)
   - `[8/8]` Setup Script Idempotency, DryRun, `-Theme`, Clean `-Uninstall*` & Backup Policy
3. **Verify Path & Line-Ending Invariants**:
   - Confirm zero hardcoded personal usernames or machine-specific paths exist across the repository.
   - Confirm `.ps1`, `.psm1`, `.psd1`, `.cmd`, and `.bat` files retain `CRLF` line endings and `.md`, `.json`, `.kdl`, `.yml`, `.yaml`, `.toml`, and `LICENSE` files retain `LF` line endings per `.gitattributes`.
4. **Update Documentation**:
   - Update `README.md` and `llms.txt` if user-facing behavior, aliases, utilities, themes, or configuration options changed.
   - Update `AGENTS.md` (and `CONTRIBUTING.md` where applicable) if repository principles, architecture, or agent rules changed.
