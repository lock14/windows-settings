# Agent guidelines and repository architecture for windows-settings

This repository contains workstation configuration files, a 17-theme 24-bit TrueColor palette engine, prompt themes, a cross-platform Zellij 0.46+ and Neovim Named Pipe RPC IDE and AI agent fleet manager, CLI tab completions, and setup automation for PowerShell 7+, Zellij, Oh My Posh, Neovim, Command Prompt (`cmd.exe`), and Windows Terminal on Windows.

Any agent modifying this repository must adhere to the architecture invariants, multi-file contracts, and technical writing conventions below.

## 1. Repository architecture and component map

| Component | Repository path | Target location on system | Purpose |
| :--- | :--- | :--- | :--- |
| PowerShell module | `module/` | `$HOME\Documents\PowerShell\Modules\WindowsSettings\` | Autoloaded shell functions (82 exports), aliases, Git safety tools, completions, asynchronous PR and theme sync, and sub-10ms warm loader |
| PowerShell profile | `config/powershell/Microsoft.PowerShell_profile.ps1` | `$PROFILE` | Minimal 1-line profile importing `WindowsSettings` |
| Oh My Posh prompt | `config/powershell/p10k_single_line.omp.json` | `$HOME\.poshthemes\p10k_single_line.omp.json` | `BASE02` shelf prompt theme with compiled disk caching, holiday icons, and clickable OSC 8 `<branch>@<N>` PR badges |
| 17-theme palette specs | `config/themes/` | `$HOME\.config\windows-settings\themes\` | 17 built-in 24-bit TrueColor `.theme` specifications (9 classic palettes and 8 US Holiday themes) plus custom user theme support |
| Neovim configuration | `config/nvim/init.lua`, `lazy-lock.json` | `$env:LOCALAPPDATA\nvim\` | Neovim 0.11+ and 0.12+ Lua configuration (Lazy.nvim, Native LSP, 17-theme `:Theme`, Named Pipe IDE RPC, `render-markdown.nvim`, `mini.files`) |
| Neovim Tree-sitter queries | `config/nvim/queries/`, `after/`, `ftplugin/` | `$env:LOCALAPPDATA\nvim\` | 43 dedicated AST highlight `.scm` queries (13 base and 30 extensions) and Java filetype plugin aligned with the universal color contract |
| Legacy Vim configuration | `config/vim/_vimrc` | `$HOME\_vimrc` and `$HOME\.vimrc` | Zero-dependency standalone fallback configuration with inline 17-theme engine and `:Theme` command |
| Command Prompt AutoRun | `config/cmd/autorun.cmd`, `macros.doskey` | `%LOCALAPPDATA%\cmd\` | Zero-dependency native `cmd.exe` AutoRun environment, UTF-8 `BASE02` Powerline shelf prompt, dynamic `theme_env.cmd` and `mise_paths.cmd` hooks, `cmd.d\` drop-ins, and bulk `doskey /macrofile` macros |
| Zellij workspace and themes | `config/zellij/` | `%APPDATA%\Zellij\config\` | Declarative Zellij `0.46+` `config.kdl`, `ide-3pane` and `ide-2pane` KDL layouts, IDE `context_menu`, `windows-settings.kdl` theme, `OSC 7501` Attention Inbox, and 1-hop GPU `terminal` config |
| Terminal fragments | `config/terminal/windows-settings.json`, `settings.json` | `%LOCALAPPDATA%\Microsoft\Windows Terminal\Fragments\WindowsSettings\` | Zero-touch Windows Terminal JSON Fragment extension with all 17 TrueColor schemes and clean `Alt+*` pass-through to Zellij |
| TrueColor themes and syntaxes | `config/bat/`, `config/colors/` | `%APPDATA%\bat\` and `$env:LS_COLORS` | 17 `*-TrueColor.tmTheme` files, 37 standalone `.sublime-syntax` grammars, and 40-language calibrated `LS_COLORS` |
| Modern CLI configs | `config/git/`, `btop/`, `tealdeer/`, `clangd/` | User config and `%APPDATA%` directories | Declarative configs for `delta` (`delta.gitconfig`), `btop4win` (`btop.conf` and 17 themes), `tealdeer`, and `clangd` |
| Native user binaries | `bin/` | Registered in User `$env:Path` | 7 dual-execution CLI utilities (`gen-passwd`, `ide`, `install-nerd-fonts`, `repeat-until-success`, `sum`, `theme`, `update-system`) as `<name>.ps1` and `<name>.cmd` |
| Polyglot sample code | `sample-code/` | Repository validation suite | 40 sample files across languages for syntax and Tree-sitter query evaluation |
| Package declarations | `configuration.dsc.yaml`, `mise.toml` | System provisioning | Microsoft DSC v3 and Mise declarative package and polyglot runtime specifications |
| Automation scripts | `setup.ps1`, `bootstrap.ps1` | Root orchestrators | Declarative provisioning, theme synchronization, and clean uninstallation runners supporting `-DryRun` |
| Agent and LLM context | `AGENTS.md`, `llms.txt` | Repository root | Canonical agent guidelines (single root `AGENTS.md`) and concise `llms.txt` LLM index |
| Governance and CI | `LICENSE`, `CONTRIBUTING.md`, `SECURITY.md`, `.github/` | Repository and GitHub | Apache-2.0 license, contributor and security policies, PR and issue templates, Dependabot, and CI and Security workflows |
| Automated tests | `tests/test_settings.ps1` | Test suite | 237+ automated validation tests across 8 modules |

## 2. Portability, line endings, and path invariants

- **Never commit personal user paths**: Never hardcode personal paths like `C:\Users\<username>\`, `/Users/<username>/`, or `/home/<username>/` into scripts, configuration files, comments, or documentation.
- **Use canonical PowerShell and environment variables**:
  - **User home**: `$HOME` or `$env:USERPROFILE`
  - **Local AppData**: `$env:LOCALAPPDATA`
  - **Roaming AppData**: `$env:APPDATA`
  - **PowerShell profile**: `$PROFILE`
  - **Path construction**: Always use `Join-Path` or `Split-Path` rather than concatenating literal backslashes or forward slashes.
- **Strict line-ending discipline**: Enforced via `.gitattributes`:
  - `.ps1`, `.psm1`, `.psd1`, `.cmd`, `.bat`, and `.doskey` files strictly use `CRLF` (`\r\n`) line endings because `cmd.exe` miscalculates byte offsets after `chcp 65001 >nul` if a `.cmd` script or generated `theme_env.cmd` uses `LF` instead of `CRLF`.
  - `.md`, `.json`, `.kdl`, `.yml`, `.yaml`, `.toml`, `.lua`, `.scm`, `.theme`, `.tmTheme`, `.sublime-syntax`, `.gitconfig`, `.conf`, `.txt`, and `LICENSE` files strictly use `LF` (`\n`) line endings.
- **Windows Terminal dynamic resolution and fragments**:
  - Deploy JSON Fragment extensions under `%LOCALAPPDATA%\Microsoft\Windows Terminal\Fragments\WindowsSettings\` for zero-touch configuration without mutating base `settings.json`.
  - When merging or syncing active schemes into `settings.json`, search dynamically across all installation locations (`LocalState`, `Microsoft.WindowsTerminal_8wekyb3d8bbwe`, and `Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe`).
- **Dual-execution support**:
  - Every native utility script in `bin/` ships both a PowerShell implementation (`<name>.ps1`) and a `cmd.exe` batch wrapper (`<name>.cmd`) for transparent invocation across PowerShell, `cmd.exe`, and external tools.

## 3. Destructive safety, idempotent backups, and clean uninstall

- **Mandatory non-destructive backups**:
  - Any installation or setup script (`setup.ps1`, `bootstrap.ps1`) creates a timestamped backup (`.bak_<timestamp>`) before overwriting or modifying an existing user configuration file such as Windows Terminal `settings.json`, PowerShell `$PROFILE`, or Neovim `init.lua`.
- **Strict idempotency requirement**:
  - Running setup scripts repeatedly must not corrupt configuration files, create duplicate profile blocks or duplicate `git config --global include.path` entries, or generate redundant backups when file content has not changed.
  - Sourcing profiles or re-running installers must be safe to execute multiple times in the same session.
- **Dry-run, theme, uninstall, and modular switches**:
  - All provisioning, theme-switching, and uninstall logic in `setup.ps1`, `bootstrap.ps1`, `bin/theme.ps1`, `bin/ide.ps1`, and `bin/update-system.ps1` honors `-DryRun` or `--dry-run` preview mode without mutating files, registry entries, or system state.
  - Modular execution switches include `-Bootstrap`, `-DotfilesOnly`, `-SystemOnly`, `-UseDSC`, `-WithGUI`, `-Theme <slug|holiday>`, and clean removal switches `-Uninstall`, `-UninstallDotfiles`, `-UninstallFonts`, and `-UninstallBin`.
- **Preserve unrelated user configuration**:
  - When modifying configuration files (Windows Terminal `settings.json`, PowerShell `$PROFILE`, or global `.gitconfig`), preserve existing user custom profiles, keybindings, actions, and third-party settings unless explicitly instructed to overwrite them.
- **Graceful failure and error handling**:
  - Use `$ErrorActionPreference = 'Stop'` in automation scripts.
  - Validate prerequisites (`winget`, `zellij`, `oh-my-posh`, `fzf`, `git`, `gh`, `wt`) gracefully, emitting actionable instructions or warnings when a tool is absent rather than crashing.

## 4. Shell performance and architecture invariants

- **High-speed shell startup (sub-10ms warm target)**:
  - The shell configuration is packaged as an autoloaded PowerShell module (`WindowsSettings.psd1`).
  - `$PROFILE` remains a single line: `Import-Module WindowsSettings -DisableNameChecking -ErrorAction SilentlyContinue`.
  - **No dynamic disk traversal**: Never use `Get-ChildItem -Recurse` inside `WindowsSettings.psm1` or module startup paths. All public and private module scripts are sourced explicitly; local drop-in hooks (`$HOME\.config\windows-settings\env.d\*.ps1`, `aliases.d\*.ps1`, and `functions.d\*.ps1`) use flat single-directory checks only when the directory exists.
  - **No dynamic command scans**: Never scan `PATH` directories with `Get-Command` loops during shell startup. Use statically known binary names and direct invocations.
  - **Compiled disk caching and non-blocking background sync**:
    - Heavy prompt, runtime `PATH`, and engine initializations (`oh-my-posh init`, `mise bin-paths` via `mise_paths.ps1` and `mise_paths.cmd`, `zoxide init`, `gh completion`, active `theme_env.ps1`) are cached as compiled `.ps1` and `.cmd` files under `$HOME\.cache\powershell\`, `$HOME\.cache\windows-settings\`, and `%LOCALAPPDATA%\cmd\` to bypass child process and shim spawns on every new shell tab. Cached init scripts validate binary modification timestamps (`oh-my-posh.exe`, `zoxide.exe`, `gh.exe`) and flat `mise\installs\<tool>` subfolder timestamps so manual WinGet or Mise package upgrades automatically refresh stale caches without leaving orphaned version paths on `PATH`. `omp_init.ps1` is loaded lazily on the first `global:prompt` call and runs with `"streaming": 150` (`oh-my-posh serve` daemon) and `"native_status": true` for sub-15ms prompt redraws.
    - Prompt wrappers (`global:prompt`) synchronize cross-pane theme changes via lightweight file-timestamp checks on `theme` and `p10k_single_line.omp.json`. Oh My Posh caches compiled prompt colors per `$env:POSH_SESSION_ID` (`pwsh.<UUID>.omp.cache`) and inside any active `oh-my-posh serve` daemon (`$global:_ompStreamingState.ServeProcess`); whenever the active theme changes, both `bin/theme.ps1` and `Sync-PromptDynamicState` delete the stale `pwsh.<oldId>.omp.cache`, rotate `$env:POSH_SESSION_ID`, and send a graceful quit signal before resetting `$global:_ompStreamingState.ServeProcess` so prompt colors repaint immediately in live and cross-pane sessions.
    - Prompt wrappers also refresh `<branch>@<N>` GitHub and GitLab pull and merge request badges asynchronously in the background without blocking prompt rendering.
- **Un-aliasing conflicting legacy cmdlets**:
  - Automatically un-alias conflicting PowerShell cmdlets (`cat`, `sort`, `tee`, `diff`, `echo`, `sleep`, `ls`, `gcm`, `gl`, `gp`) so modern CLI tools (`uutils-coreutils`, `eza`, Git shortcuts) execute without prefixing `&`.
  - Matching `home-settings`, `cat` is left unwrapped so `uutils-coreutils` `cat.exe` runs natively with zero paging or decoration, while `b` invokes `bat` (`autorun.cmd` also runs `doskey cat=` to clear any legacy `cat` macro).
- **Static analysis compliance**:
  - All PowerShell scripts (`.ps1`, `.psm1`, `.psd1`) pass `PSScriptAnalyzer` static analysis configured in `PSScriptAnalyzerSettings.psd1` with zero errors and zero warnings.

## 5. Multi-theme TrueColor engine and Solarized Dark precision

By default, all visual components across the terminal, shell, prompt, file viewers, and editor adhere to the authentic Solarized Dark palette (Ethan Schoonover specification), while the unified 17-theme palette engine (`bin/theme.ps1`) generalizes the exact same semantic role mapping across 9 classic palettes (`solarized-dark`, `solarized-light`, `catppuccin-mocha`, `catppuccin-latte`, `gruvbox-dark`, `tokyonight-night`, `kanagawa-wave`, `nord`, `onedark`), 8 US Holiday themes (`new-years`, `valentines`, `st-patricks`, `easter`, `independence-day`, `halloween`, `thanksgiving`, `christmas`), and custom user `.theme` definitions (`--create`).

### Canonical default palette reference (Solarized Dark)

| Role | Color name | Hex code | Purpose and usage |
| :--- | :--- | :--- | :--- |
| Base background | `base03` | `#002B36` | Terminal background, Neovim background, `bat` background |
| Current line and shelf background | `base02` | `#073642` | `CursorLine`, selection background, prompt shelf, line highlight |
| Comments and dim borders | `base01` | `#586E75` | Code comments (italic), `eza` tree connectors (`xx`), prompt dim elements, `bat` borders |
| Subtle text | `base00` | `#657B83` | Secondary text, thin prompt chevrons, status indicators |
| Standard foreground | `base0` | `#839496` | Standard typed text, CLI arguments, paths, struct fields, invocations, identifiers |
| Emphasis text | `base1` | `#93A1A1` | Bright text, active `CursorLineNr`, highlighted labels |
| Light surface tones | `base2`, `base3` | `#EEE8D5`, `#FDF6E3` | Light background references (primary surfaces in light themes) |
| Control flow and jumps | `yellow` | `#B58900` | `if`, `return`, `for`, `while`, `switch`, `case`, `select`, `defer`, `match`, `try`, `throw`, `yield`, `await`, PSReadLine control flow keywords |
| Structural and declarations | `green` | `#859900` | `package`, `func`, `var`, `type`, `struct`, primitive types (`int`, `string`, `bool`), JSON, YAML, and TOML keys, PSReadLine commands and types |
| Functions and methods | `blue` | `#268BD2` | Function declarations, directory names, TOML and INI section headers, Markdown H2 |
| Strings and paths | `cyan` | `#2AA198` | String literals, paths, struct tags, format specifiers, PSReadLine strings |
| Numbers and constants | `magenta` | `#D33682` | Numeric literals, `nil`, `true`, `false`, `iota`, `self`, `this`, cryptographic files, PSReadLine numbers |
| Annotations and imports | `violet` | `#6C71C4` | Annotations, attributes, module imports (`import`, `use`), media files, Markdown H3 |
| Preprocessors and headers | `orange` | `#CB4B16` | Preprocessor macros, compiler directives, CSS at-rules, archives, Markdown H1 |
| Errors and diagnostics | `red` | `#DC322F` | Syntax errors, diff deletions, error status anchors, diagnostic errors |

### Universal semantic color contract

Colors across the workstation fulfill invariant domain roles across all 40 supported languages, tools, and filetypes, translating one-to-one through every `.theme` slot when switching themes via `theme`:

| Palette slot | Default hex | Universal semantic role | Manifestations across languages and tools |
| :--- | :--- | :--- | :--- |
| `YELLOW` | `#B58900` | Uncontested control flow and jumps | `if`, `return`, `for`, `while`, `switch`, `case`, `select`, `defer`, `match`, `try`, `throw`, `yield`, `await`, `CASE`, `WHEN` (exclusive to control flow, never in Markdown headings, declarative data or config documents, CSS stylesheets, or Java Properties) |
| `GREEN` | `#859900` | Structural scaffolding, declarations, primitive types, and diff additions | `int`, `double`, `u64`, `usize`, `bool`, `void`, Python built-in types (`int`, `str`, `float`, `bool`, `list`, `dict`, `set`, `tuple`), `func`, `fn`, `def`, `class`, `struct`, `interface`, `var`, `let`, `const`, `typedef`, `CREATE TABLE`, SQL data types, JSON, YAML, TOML, and Properties keys, XML and HTML attribute names, CSS property names, `+` added lines, PSReadLine commands |
| `BASE0` | `#839496` | Neutral ground, custom domain types, schemas, invocations, and operators | Custom domain types (`OrderRecord`, `Context`, `HashMap`, `Instant`), schema relations, function and method calls (`printf()`, `.stream()`), CSS custom properties and functions (`var()`, `clamp()`), XML, HTML, TOML, and Properties delimiters, parameters, operators, PSReadLine arguments |
| `BLUE` | `#268BD2` | Routine declarations and structural headers | `func New...`, `fn find...`, `def __init__`, XML element tags, TOML table section headers (`[package]`), CSS tag and class selectors, diff hunk headers (`@@ ... @@`), Markdown H2 |
| `VIOLET` | `#6C71C4` | Aspects, annotations, attributes, modules, and imports | `@Service`, `@dataclass`, `#[derive]`, `[[nodiscard]]`, CSS pseudo-classes and pseudo-elements (`:root`, `:hover`), `import`, `from`, `use`, `package main`, Markdown H3 |
| `MAGENTA` | `#D33682` | Constants, literals, hashes, sentinels, and receivers | `1024`, `nil`, `null`, `None`, `true`, `false`, TOML date-times, CSS hex colors, XML entity references, `ALL_CAPS` constants, `this`, `self`, PSReadLine numbers |
| `CYAN` | `#2AA198` | Strings, filesystem paths, struct tags, and format placeholders | `"Hello %s\n"`, paths, Markdown link URLs, XML attribute strings, format specifiers (`%s`, `%d`), PSReadLine strings |
| `ORANGE` | `#CB4B16` | Directives, preprocessor macros, and shebangs | `#define`, `#include`, `#!/bin/bash`, CSS at-rules (`@layer`, `@media`), XML processing instructions (`<?xml ... ?>`), Markdown H1 |
| `BASE01` | `#586E75` | Comments, subtle metadata, and structural delimiters | `//` and `#` comments, `bat` frames, `eza` tree connectors, Markdown markers, inactive line numbers, PSReadLine comments and predictions |

### Architectural pillars

1. **Pillar I (3-tier semantic color contract and canvas tranquility)**:
   - **Tier 1 (monotone ground, 70 to 80% screen area)**: `BASE0` and `BASE01` carry standard typed text, CLI arguments, paths, struct fields, custom domain types, schema relations, routine invocations, operators, parameters, delimiters, and comments.
   - **Tier 2 (structural anchors, 15 to 20% screen area)**: Green marks scaffolding and declarations, Yellow is exclusive to control flow, Blue marks function declarations and section headers, and Violet marks annotations and imports.
   - **Tier 3 (values and directives, 5 to 10% screen area)**: Cyan marks strings and paths, Magenta marks constants, numeric literals, and booleans, and Orange marks preprocessor macros and Markdown H1.
   - **Monochromatic UI chrome**: Gutter coordinates rely on luminance contrast (active `CursorLineNr` in `BASE1` bold on `BASE02`, inactive `LineNr` in `BASE01`), split dividers (`WinSeparator`, `VertSplit`) and popup borders (`FloatBorder`) in `BASE01`, delimiter matching (`MatchParen`) in `BASE1` on `BASE02` without syntax mutation, and non-mutating `sp` underlines for diagnostics.
2. **Pillar II (operational role invariance)**:
   - Function declarations are structural landmarks in Blue; function and method invocations rest on the `BASE0` canvas.
   - Factory functions (such as Go `NewClusterNode`) remain invocations in `BASE0`, never flipping to Yellow.
   - Sentinels (`null`, `nil`, `None`, `_`) classify as constants in Magenta.
3. **Pillar III (Gestalt semantic continuity and atomic compound enclosure)**:
   - String payloads, interpolation wrappers, and format specifiers (`%s`, `\n`) form a single continuous entity in Cyan.
   - Compound enclosures (attributes `#[derive]`, `[[nodiscard]]`, `@Override`, and Go struct tags) remain unified in their primary accent without token fracturing.
   - Diff lines form a single semantic mutation in continuous Green (`+`) or Red (`-`), enhanced in `delta` via `MIX_GREEN` and `MIX_RED` subtle line backgrounds.
4. **Pillar IV (navigational neutrality)**:
   - Scope qualifiers (`std::`, `boost::`, `context.`, `fmt.`) serve navigational routing and remain in `BASE0`, while formal declaration sites receive Violet.
   - Shell parameter expansions and PowerShell variable prefixes remain in `BASE0`.
5. **Pillar V (pushdown automata state machine engineering)**:
   - 37 standalone `.sublime-syntax` grammar specifications in `config/bat/syntaxes/` cover the 40-language polyglot suite (`sample-code/`).
   - Pushdown transitions consume opening delimiters and avoid lookahead traps; contextual keywords are guarded by lookarounds to prevent false control-flow matches.
6. **Pillar VI (Tree-sitter AST query hierarchy and cascade engineering in Neovim)**:
   - Root fallback captures mirror the universal color contract (`@function.call` maps to `Base0`, `@keyword.import` maps to `Violet`, and `@variable.builtin` maps to `Magenta`).
   - Single-source-of-truth query architecture across 43 `.scm` files: 13 base query supersedures in `config/nvim/queries/` without `;; extends` (`css`, `dockerfile`, `elixir`, `graphql`, `html`, `html_tags`, `lean`, `markdown_inline`, `properties`, `proto`, `rego`, `textproto`, `xml`, with zero `(#set! "url"` metadata), and 30 runtime extensions in `config/nvim/after/queries/` with `;; extends`.
   - Document-order rule precedence places generic catch-all patterns before specialized predicate captures, and diagnostic squiggles isolate severity via underline color (`sp`) with `fg = "NONE"`.
7. **Pillar VII (standalone subsystem independence and LTS currency)**:
   - Decoupled from upstream packaging lag through version-controlled grammars in `config/bat/syntaxes/`, theme generation in `bin/theme.ps1`, and query overrides in `config/nvim/`.
   - Polyglot runtimes and modern Rust and Go CLI tools are declaratively pinned in `mise.toml` (`bat`, `delta`, `dust`, `elan`, `eza`, `fd`, `fzf`, `gh`, `glow`, `go`, `java`, `jq`, `neovim`, `node`, `python`, `ripgrep`, `rust`, `sd`, `tealdeer`, `tree-sitter`, `yq`, `zellij`, `zoxide`).
8. **Pillar VIII (workstation visual hierarchy and spatial typography)**:
   - 4-layer terminal canvas: Layer 0 (`BASE03` ground), Layer 1 (`BASE02` and `BASE01` structural chrome), Layer 2 (`BASE0` monotone ground), and Layer 3 (semantic accents).
   - Interactive shell prompts (Oh My Posh and `autorun.cmd`) sit on the `BASE02` shelf with thin directional chevrons (`\uE0B1` on left and `\uE0B3` on right in `BASE00`) leading into solid wedge caps (`\uE0B0` and `\uE0B2`).
   - Prompt luminance hierarchy ascends from frame (`BASE01`) to separator (`BASE00`) to OS icon (`BASE0`), with automatic holiday glyph overrides via `_HS_PROMPT_OS_ICON` during US Holiday themes.
9. **Pillar IX (multi-tool precedence and filesystem color parity)**:
   - Precedence cascade: explicit glob in `LS_COLORS` takes precedence over explicit glob in `EZA_COLORS`, which takes precedence over 2-letter family codes and defaults.
   - Hardware ANSI slot discipline: archives map to bright slot 9 (ANSI `91` Orange), media files map to bright slot 13 (ANSI `95` Violet), and cryptographic keys and certificates (`.key`, `.pem`, `.crt`, `cr`) map to slot 5 (ANSI `35` Magenta), isolated from Blue directories and Orange archives.

### Concrete tooling implementations

1. **Unified theme engine**: Implemented in `bin/theme.ps1` and `bin/theme.cmd`:
   - Pure PowerShell 7 implementation managing 17 built-in `.theme` definitions plus user-created custom themes (`--create <slug> --from <base>`).
   - Supports `--list`, `--plain`, `--current`, `--set`, `--preview`, `--holiday` (US federal and cultural holiday date engine with `$env:THEME_HOLIDAY_DATE` override), `--env`, `--path`, `--sync-assets`, `--dry-run`, `--no-live`, and interactive `fzf` TrueColor preview selection.
   - Live-updates Zellij (`themes/windows-settings.kdl` plus bounded `tray_badge_colors` and `terminal { theme { ... } }` blocks in `config.kdl`), Windows Terminal schemes, OSC 4, 10, 11, and 12 terminal palette slots, running Neovim Named Pipe servers (`\\.\pipe\nvim*`), Oh My Posh (`p10k_single_line.omp.json`), `theme_env.ps1`, CRLF-safe `theme_env.cmd`, `bat`, `delta`, `btop4win`, `tealdeer`, `fzf`, `eza`, `jq`, and `LS_COLORS`.
2. **Hybrid Zellij and Neovim Named Pipe IDE and agent fleet manager**: Implemented in `bin/ide.ps1` and `bin/ide.cmd`:
   - Cross-platform counterpart to `home-settings/bin/ide` built on Zellij `0.46+` (`config/zellij/`) and Windows Named Pipe RPC (`\\.\pipe\nvim-ide-<session>`), with zero custom compiled daemons and automatic `--backend wt` Windows Terminal split-pane fallback.
   - `--3pane` launches a frameless Inverted-T workspace (`ide-3pane.kdl`: top-left AI Agent, top-right Neovim Editor, and bottom full-width PowerShell beneath a 1-line `BASE02` `compact-bar`); `--2pane` (`ide-2pane.kdl`) launches side-by-side AI and Editor panes; `-d` and `--detach` spawn detached background agent sessions (`zellij attach --create-background`); `--desktop` launches Zellij's native 1-hop GPU desktop app (`zellij terminal`) with OS system tray icon and desktop notifications.
   - Native `OSC 7501` Attention Inbox: Claude Code and Codex emit `OSC 7501` natively, and Antigravity (`agy`) is wired via `~/.gemini/config/hooks.json` (`ide.cmd --agy-hook SessionStart|PreInvocation|Stop`) deployed idempotently by `setup.ps1`.
   - Supports `--ai agy|claude|codex`, `-s` and `--sessions` (floating `zellij:session-manager` Attention Inbox), `Alt+Shift+S` and `--next-attention` (`GoToNextAttention`), `Alt+a`, `Alt+e`, `Alt+t`, right-click IDE `context_menu` across `bar`, `tab`, `pane`, and `common` targets, `--focus-role`, `--toggle`, `--open`, `--preview`, `--open-or-edit` (`v [+line] <file>`), synchronized workspace directory diving (`icd` and `:IdeCd`), `<leader>a` and `--send` bracketed-paste prompt injection (`zellij action paste -p`), `--keys` TrueColor cheatsheet, `--monitor`, `--list`, and unsaved-buffer protected `:Q`, `qide`, and `quit` (`--quit`).
3. **Syntect CLI file and diff viewers**: Configured for `bat` and `delta`:
   - Compiled theme cache via `bat cache --build` deploying all 17 `config/bat/themes/*-TrueColor.tmTheme` palettes and 37 `config/bat/syntaxes/*.sublime-syntax` grammars to `%APPDATA%\bat\`.
   - Accessible via `bat` or `b` (`$env:BAT_OPTS = '--italic-text=always'`), while `config/git/delta.gitconfig` configures `delta` TrueColor diffs linked via `git config --global --add include.path`.
4. **Neovim and standalone Vim**: Configured in `config/nvim/init.lua` and `config/vim/_vimrc`:
   - Neovim 0.11+ and 0.12+ configuration with Lazy.nvim (`lazy-lock.json`), Native LSP (`gopls`, `pyright`, `ts_ls`, `rust_analyzer`, `clangd`, `terraformls`, `yamlls`, `leanls`, plus `ftplugin/java.lua`), 43 Tree-sitter `.scm` queries, `render-markdown.nvim`, `mini.files` and `mini.icons`, AST link and TOC navigation, `<X1Mouse>` and `<X2Mouse>` jump navigation, Named Pipe RPC server discovery, orphaned `%LOCALAPPDATA%\tree-sitter\lock\*.lock` reaping, and live `:Theme` switching.
   - Zero-dependency `config/vim/_vimrc` deployed to `$HOME\_vimrc` and `$HOME\.vimrc` with inline 17-theme TrueColor and 256-color support and `:Theme` command.
5. **Filesystem listings, system monitor, and language tools**: Configured for `eza`, `uutils` `ls`, `btop4win`, `tealdeer`, and `clangd`:
   - `eza` (`e`, `el`, `elm`, `et`, `elt`, `elx`) and `LS_COLORS` (`ls`, `ll`, `la`, `l`) are dynamically re-tinted by `bin/theme.ps1` across all 17 palettes.
   - Declarative configurations are deployed for `btop4win` (`config/btop/btop.conf` and 17 themes), `tealdeer` (`config/tealdeer/config.toml`), and `clangd` (`config/clangd/config.yaml`).
6. **Oh My Posh prompt and Command Prompt AutoRun**: Configured in `p10k_single_line.omp.json`, `autorun.cmd`, and `macros.doskey`:
   - Unified on the active theme's `BASE02` shelf with compiled disk caching (`$HOME\.cache\powershell\omp_init.ps1`), `"streaming": 150` persistent daemon rendering, dynamic holiday OS icon (`_HS_PROMPT_OS_ICON`), clickable OSC 8 `<branch>@<N>` GitHub and GitLab PR hyperlinks (`_WS_GIT_PR_LABEL` and `_WS_GIT_PR_URL`), and persistent right status anchor (`\uF00C` and `\uF00D`).
   - `config/cmd/autorun.cmd` and `config/cmd/macros.doskey` provide low-latency native `cmd.exe` parity (`chcp 65001 >nul`, `FORCE_HYPERLINK=1`, `JQ_COLORS`, dynamic `theme_env.cmd` and `mise_paths.cmd` hooks, `cmd.d\*.cmd` drop-ins, `doskey cat=`, and single-spawn `doskey /macrofile` alias parity).

## 6. Developer shortcuts, aliases, and Git safety guards

- **File and system tools**: `b` invokes `bat` (falling back cleanly when `bat` is absent), `cat` runs raw `uutils` `cat.exe`, `ds` invokes `dust`, `btop` invokes `btop4win`, `update` invokes `update-system`, and `theme` invokes `bin/theme.ps1`.
- **IDE and editor suite**: `ide`, `ide2` (`ide --2pane`), `ide3` (`ide --3pane`), `idek` (`ide --kill`), `qide` and `quit` (`ide --quit`), `icd` (`ide --cd` plus shell `Set-Location`), `v` (RPC-aware `ide --open-or-edit` inside IDE sessions, falling back to `nvim` or `vim`), and `vi` and `vim` mapped to `nvim`.
- **Git suite and safety guards**:
  - **Shortcut parity**: `gco`, `gcb`, `gcm`, `ga`, `gaa`, `gst`, `gss`, `gd`, `gds`, `gl`, `gp`, `gb`, `gba`, `gbd`, `gsta`, `gstp`, `gstl`, `glog`, `glo`, `grb`, `grbc`, `grba`, `gcommit`, `gamend`, `gup`, `gprune`, `gpurge`, `gsync`, `guser-branch`.
  - **Safe vs destructive branch cleanup**: `gprune` deletes merged local branches only (`git branch -d`) after `git fetch --prune`, whereas `gpurge` force-deletes unmerged local branches (`git branch -D`) behind an interactive confirmation prompt (`-Force` or `-y` for non-interactive scripts).
  - **Primary-branch and dirty-tree guards**: `guser-branch` refuses to rename `main` or `master` and strips redundant `$env:USERNAME/` or `$env:USER/` prefixes; `gsync` verifies a clean tracked working tree before rebasing onto `origin/main` or `origin/master`; `gl` and `gup` use `--rebase --autostash`, and `gp` sets upstream (`-u origin HEAD`) automatically when needed.
- **Directory and polyglot helpers**: `go-testall`, `go-buildall`, `go-lint`, `yaml-lint`, `tf`, `fs`, `Format-PathTree`, `ls`, `ll`, `la`, `l`, `lt`, `e`, `el`, `elm`, `et`, `elt`, `elx`, plus compatibility wrappers `go_testall`, `go_buildall`, `go_lint`, `yaml_lint`, and `fix-abcxyz-branch-name`.

## 7. Component structure, multi-file contracts, and code style

- **Standardized multi-file component contracts**:
  - **CLI utility**: Every tool in `bin/` requires `bin/<name>.ps1` (`CRLF`), `bin/<name>.cmd` (`CRLF`), a wrapper or alias in `module/Utilities.ps1` or `module/Developer.ps1`, an export in `module/WindowsSettings.psd1`, tab completion in `module/Completions.ps1`, a `doskey` macro in `config/cmd/macros.doskey`, and test coverage in `tests/test_settings.ps1`.
  - **Theme palette**: Every built-in theme in `config/themes/` requires `config/themes/<slug>.theme`, synchronized static assets via `bin/theme.ps1 --sync-assets` (`config/bat/themes/*-TrueColor.tmTheme`, `config/btop/themes/*.theme`, `config/terminal/windows-settings.json`, `config/terminal/settings.json`), and a matching entry in standalone `config/vim/_vimrc`.
  - **Language highlighting**: Every supported language requires a fixture in `sample-code/`, a standalone `.sublime-syntax` grammar in `config/bat/syntaxes/`, a Tree-sitter `.scm` query in `config/nvim/queries/` or `config/nvim/after/queries/`, and an extension mapping in `config/colors/LS_COLORS`.
  - **No extraneous or ad-hoc files**: Extraneous scratch scripts, temporary patch files, `tmp_*` folders, or `.bak` backups in the repository tree are prohibited. Scratch work belongs in `<appDataDir>\brain\<conversation-id>\scratch\` or `$env:TEMP`.
  - **Single canonical agent guidelines file**: Maintain a single root `AGENTS.md` file (supported natively across Antigravity, Claude Code, and Codex). Do not create duplicate `CLAUDE.md` or `.agents/AGENTS.md` files or symlinks.
- **Internal PowerShell script section ordering**:
  1. Optional comment-based help (`<# .SYNOPSIS ... #>`), `[CmdletBinding()]`, and `param(...)` block.
  2. `$ErrorActionPreference = 'Stop'` and strict execution settings.
  3. Constants, defaults, and canonical path resolution (`Join-Path` and `Split-Path`).
  4. Private helper functions using singular nouns and avoiding state-changing verbs on pure helpers.
  5. `-DryRun` and mode dispatch followed by the main execution entrypoint.
- **Identifier anti-shadowing and encoding discipline**:
  - Never use parameter or local variable names that shadow PowerShell automatic variables (`$args`, `$input`, `$Host`, `$HOME`, `$PID`, `$PROFILE`, `$Error`, `$Matches`, `$PSItem`).
  - Any `.ps1` file containing literal non-ASCII Unicode characters requires a UTF-8 BOM (or codepoint escapes via `[char]0x...` or `` "`u{...}" ``) to satisfy `PSUseBOMForUnicodeEncodedFile`.

## 8. Documentation roles, boundaries, and continuous learning

- **User-facing documentation**: `README.md` is reserved strictly for end-users. Covers installation, quick-start workflows, `setup.ps1` flags, IDE layouts and keybinding tables, theme management, shell shortcuts, standalone utilities, and local customization without internal plumbing or agent directives.
- **Contributor-facing documentation**: `CONTRIBUTING.md` is the dedicated guide for human contributors covering prerequisites, safe `-DryRun` testing, multi-file component contracts, static analysis, and pull request guidelines.
- **Agent and architectural invariants**: `AGENTS.md` is the single authoritative reference at the repository root encoding architecture invariants, palette specifications, multi-file contracts, technical writing rules, and verification checklists.
- **Mandatory documentation synchronization**: Whenever aliases, functions, CLI utilities, themes, setup parameters, or governance workflows change, update `README.md`, `CONTRIBUTING.md`, `AGENTS.md`, and `llms.txt` in the same pull request.
- **Persist user corrections**: Whenever an agent receives feedback, corrections, or instructions regarding repository conventions, encode the underlying principle into `AGENTS.md` before concluding the task.

## 9. Pull request workflow and PowerShell Markdown escaping

- **Branch naming**: Use descriptive branch prefixes (`feat/*`, `fix/*`, `perf/*`, `docs/*`, `ci/*`).
- **Imperative commits and PR titles**: Write standalone imperative commit subjects and PR titles (such as `Add Zellij session monitor` or `Adopt technical writing and typography conventions`) adhering to Principle VI in Section 11.
- **Pull request description synchronization**: Complete `.github/PULL_REQUEST_TEMPLATE.md` thoroughly. Whenever subsequent commits in a pull request branch modify, fix, or expand upon the original changeset (such as CI adjustments, bug fixes, or refactoring), proactively update the pull request description via `gh pr edit --body-file <path>` to reflect the latest state.
- **Avoid inline backtick expansion in PowerShell commands**:
  - In PowerShell (`pwsh`), the backtick (`` ` ``) is the native escape character. Passing Markdown strings containing inline code (such as `` `eza` `` or `` `node` ``) inside double quotes (`"..."`) causes PowerShell to evaluate escape sequences (` `e `, ` `n `, ` `t `), corrupting GitHub pull requests, issues, or commit bodies.
  - **File-based arguments**: When creating or editing pull requests, issues, or commits, write the body to a scratch file and pass `--body-file <path>` or `git commit -F <path>`.
  - **Single-quoted strings and here-strings**: When passing inline Markdown in PowerShell, enclose it in single quotes (`'...'`) or single-quoted here-strings (`@' ... '@`) so zero escape interpretation occurs. Never run `gh pr create --body "..."` with embedded backticks.

## 10. Verification checklist and definition of done

Before completing any task, run and verify all of the following succeed without errors or warnings:

1. **Run static analysis**:
   ```powershell
   Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
   ```
2. **Run the automated validation suite**:
   ```powershell
   $null | pwsh -NoProfile -File ./tests/test_settings.ps1
   ```
   Verify all 237+ tests pass across all 8 test modules:
   - `[1/8]` PowerShell script and module syntax
   - `[2/8]` JSON, KDL, YAML, theme, query, governance, documentation typography, and manifest validity
   - `[3/8]` `WindowsSettings` module import, aliases, and function exports (82 functions)
   - `[4/8]` Native CLI utilities and pipeline handling (`sum`, `gen-passwd`, `repeat-until-success`, `theme`, `ide`, `update-system`)
   - `[5/8]` Git workflow behavior and safety guards (`gsync`, `gprune`, `gpurge`, `guser-branch`, `fix-abcxyz-branch-name`)
   - `[6/8]` Completions, `cmd.exe` AutoRun, and prompt rendering (including OSC 8 PR badge hyperlinks)
   - `[7/8]` Path invariants, byte-level `CRLF` and `LF` line endings, startup hygiene, and dual-execution wrappers
   - `[8/8]` Setup script idempotency, `-DryRun`, `-Theme`, clean `-Uninstall*`, and backup policy
3. **Verify path and line-ending invariants**: Confirm `git diff` introduces zero hardcoded personal paths and preserves `CRLF` on `.ps1`, `.psm1`, `.psd1`, `.cmd`, `.bat`, and `.doskey` files and `LF` on all config and documentation files.
4. **Synchronize documentation**: Confirm `README.md`, `CONTRIBUTING.md`, `AGENTS.md`, and `llms.txt` reflect the latest changes and pass documentation typography and link validation.

## 11. Documentation architecture and technical writing style for agents

Technical documentation in this repository is engineered for cognitive efficiency, instant scannability, and long-term accuracy. It communicates system mental models and mechanical precision without marketing prose, conversational filler, or typographic clutter.

These guidelines synthesize the Google Developer Documentation Style Guide, Matthew Butterick's *Practical Typography*, Diátaxis, Google Engineering Practices, and Chris Beams' Git commit conventions. Any agent drafting, modifying, or refactoring documentation (`README.md`, `CONTRIBUTING.md`, `AGENTS.md`, `SECURITY.md`, `llms.txt`, PR descriptions, issues, comments, and commit messages) must adhere to the following 6 principles:

### Principle I: Intent-driven architecture (Diátaxis and macro-to-micro flow)

Separate documentation by reader intent rather than mixing tutorials, reference tables, and design history in a single stream:

- **Quick start (Tutorial)**: The shortest command sequence to reach a working state. Omit alternative flags, edge cases, and architectural history.
- **Task guides (How-to)**: Goal-oriented recipes written in the imperative mood for readers who already know the basics.
- **Lookup tables (Reference)**: Austere, factual tables and schemas that mirror the codebase without narrative prose.
- **Architecture (Explanation)**: System topology, design rationale, and trade-offs ("why"), organized from macro mental model down to runtime mechanics and concrete toolchains:
  - **Tier 1 (mental model and spatial architecture)**: System topology, geometry, layout, purpose, and visual metaphors (such as Inverted-T 3-pane versus 2-pane geometry and session isolation).
  - **Tier 2 (first-principles structural layers)**: Conceptual decoupling and behavioral tiers (such as the 4 keybinding layers: app-local, workspace navigation, editor and explorer, and clickable links and clipboard).
  - **Tier 3 (runtime engines and automation)**: Execution mechanics, event loops, caching, and edge-case mitigation (such as Named Pipe RPC synchronization, Oh My Posh session cache rotation, and orphaned parser lock reaping).
  - **Tier 4 (toolchains, plugins, and integrations)**: Concrete tool configurations, LSP servers, syntax parsers, and Windows Terminal fragment integrations.

### Principle II: Dual representation rule (prose and lookup tables)

- Interactive keybindings, CLI flags, environment variables, and shell shortcuts must never exist exclusively inside paragraph prose.
- Represent them in two places:
  - Conceptually within their structural section (explaining how they fit the workflow, why they are mapped, and how they avoid domain conflicts).
  - Tabularly in a dedicated reference table ([IDE workspace keybindings and navigation](README.md#ide-workspace-keybindings-and-navigation), [Git and shell shortcuts](README.md#git-and-shell-shortcuts), [Standalone utilities](README.md#standalone-utilities-bin)) with sentence-case column headers for fast lookup.
- Use tables only for genuine two-dimensional data (items sharing three or more attributes, or structured key-value lookups), never for single-column lists.

### Principle III: The non-accretion rule (holistic maintenance)

- When introducing or modifying features, never append a standalone bullet point or note to the end of an existing section.
- Review the surrounding section holistically:
  - Integrate the change into its proper architectural tier or table.
  - Prune superseded or redundant statements so the document reads as a single cohesive draft.

### Principle IV: High information density and zero fluff

- **No marketing or conversational filler**: Omit buzzwords ("effortlessly", "blazing fast", "seamlessly", "flawless") and preambles ("Note that...", "In this section we will...", "It is worth mentioning...").
- **Concrete semantic payload**: Every sentence must state exact technical nouns, flags, file paths, key combinations, and deterministic runtime behaviors.
- **User-facing readability versus internal specification**: In `README.md`, communicate what features do and how to use them in clear, scannable prose. Never chain long sequences of internal variable names, Tree-sitter S-expressions, or repetitive RGB hex codes in a single paragraph—keep low-level implementation mechanics in `AGENTS.md`.
- **Zero aspirational documentation**: Document only behavior that is implemented, tested, and verified against the current codebase.

### Principle V: Typography and formatting restraint (Google Style Guide, Butterick)

- **One format per span**: Never combine bold, italics, code font, or hyperlinks on the same text (no bolded code spans, no bolded links, no bold-italics, and no bolded first-column table cells).
- **Strict role separation**:
  - **Code font**: Use backticks strictly for literal code, CLI commands, flags (`--3pane`, `-DryRun`), file paths (`config/zellij/config.kdl`, `init.lua`), configuration keys, and keyboard shortcuts (`Alt+h`, `Space e`, `Ctrl+Click`). Keep sentence punctuation outside the backticks.
  - **Bold**: Use `**...**` only for UI labels and run-in headings at the start of list items followed by a colon (`:`). Never use bold for mid-sentence emphasis or whole clauses.
  - **Italics**: Use `_..._` or `*...*` only when introducing or defining a term on first use, or for titles of standalone works.
- **Sentence-case headings**: Use sentence case for all document titles, section headings, and table column headers (capitalize only the first word and proper nouns), with no trailing punctuation.
- **Zero yellow and zero artificial bold in headings**: Never use yellow in Markdown headings and never apply bold font styles across entire headings (`bold = false`).
- **No decorative symbols or math arrows in prose**: Omit decorative emojis, GitHub emoji shortcodes, LaTeX math arrows (`$\rightarrow$`, `$\leftrightarrow$`, `$\gg$`), ASCII arrows (`->`, `<->`, `=>`), and inequality signs (`<`, `>`) as prose connectors. Write plain verbs ("maps to", "takes precedence over") instead.
- **No horizontal section dividers**: Do not place horizontal rules (`---`) between sections; Markdown headings already provide structural hierarchy.
- **Clean punctuation**:
  - **Parentheses**: Use sparingly and keep short. Never place critical requirements inside parentheses, never nest parentheses, and never pack long lists of code spans inside parentheses mid-sentence. Avoid optional plurals like `file(s)`.
  - **Slashes**: Do not use slashes (`/`) in prose to join alternatives (write "or" or "and" instead of `read/write` or `and/or`). Reserve `/` for file paths, URLs, and literal commands or key chords.
  - **Dashes**: Use hyphens (`-`) for compound modifiers, "to" for ranges, and unspaced em-dashes (`—`) sparingly for clause breaks. Never use dashes to separate a list term from its definition; use a colon after run-in list headings.
- **List discipline**:
  - Use numbered lists strictly for sequential steps where order matters; use bulleted lists for non-sequential sets.
  - Keep list items parallel in grammatical structure and consistent in terminal punctuation.
  - Avoid italic parenthetical asides like `*(Note: ...)*`. If a detail matters, state it as a normal sentence; reserve callout blocks (`> [!IMPORTANT]`) for destructive hazards or critical prerequisites.

### Principle VI: Surface-specific standards

- **READMEs**:
  - Open with a concise two-to-three sentence summary of what the tool does and which platforms it targets.
  - Follow immediately with a table of contents, a minimal quick-start block, command-line options, task guides, reference tables, and testing commands.
  - Keep developer internals, build pipeline mechanics, and agent instructions out of user-facing READMEs.
- **Pull request descriptions (Google CL Description Guide)**:
  - **Title**: A standalone imperative sentence summarizing the change.
  - **Summary ("why" before "what")**: Explain the problem or limitation in the prior code and why this design was chosen. Group changes by subsystem or behavior rather than repeating the line-by-line diff.
  - **Lean templates**: Keep pull request templates concise (`## Summary`, `## Architecture and safety checklist`, and `## Verification`) with plain-text checkboxes and zero decorative emojis.
- **Issues**:
  - **Bug reports**: Include factual sections for affected component, environment, numbered steps to reproduce, expected behavior, and actual behavior (with exact terminal output in a fenced code block).
  - **Feature proposals**: State the workflow problem or use case before proposing a CLI or schema design.
- **Code and review comments**:
  - **Doc comments**: Exported functions and modules state their contract and error behavior in complete sentences.
  - **Implementation comments**: Explain why a non-obvious constraint or workaround exists, never what the code literally does.
  - **Review comments**: Critique the code rather than the author, explain the underlying engineering principle, and prefix non-blocking polish suggestions with `Nit:`.
- **Commit messages (Chris Beams' 7 Rules)**:
  - **Subject line**: Imperative mood ("If applied, this commit will..."), capitalized, no trailing period, targeting 50 characters (hard cap at 72).
  - **Blank line**: Separate the subject from the body with a single blank line.
  - **Body**: Wrap at 72 characters in plain text (avoid heavy Markdown formatting in commit bodies). Explain what problem existed and why the change was made, placing issue references in trailers at the bottom.
