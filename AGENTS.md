# Agent guidelines and repository architecture for windows-settings

This repository provides automated workstation provisioning, dotfiles, a 22-theme 24-bit TrueColor palette engine, shell environments, and developer toolchains for Windows 10 and Windows 11 across PowerShell 7+, Zellij `0.46+`, Oh My Posh, Neovim, Command Prompt (`cmd.exe`), and Windows Terminal.

Any AI agent modifying this repository must adhere to the invariants below and consult the linked specifications in `docs/` and `.agents/` when modifying syntax, themes, IDE internals, TUI surfaces, or documentation:

- [Visual precision and semantic color architecture](docs/color-architecture.md): Solarized Dark 14-slot specification, 22-theme palette rules, Universal semantic color contract, Pillars I through IX, and Tree-sitter and Sublime syntax rules.
- [IDE workspace, multiplexer, and portable shell architecture](docs/ide-architecture.md): Frameless Zellij `0.46+` geometry, `ws-bar` WASM top shelf, direct `.NET NamedPipeClientStream` Neovim MsgPack-RPC, `fzf` fleet switcher, hook-only `OSC 7501` AI state machine, OSC 8 routing, and portable `_vimrc` and `autorun.cmd` contracts.
- [Monospace TUI design standard and project rules](.agents/rules/monospace-tui.md): `mono-tui v0.2.5` responsive `90`-column versus `80×24` layout breakpoints, width-fitted `fzf` command bars, calm `BASE01` borders with `[PREVIEW]` versus `[LIVE]` badges, 4-tier color capability degradation, and Nerd Font ASCII fallback (paired with [mono-tui-design](.agents/skills/mono-tui-design/SKILL.md) and [mono-tui-audit](.agents/skills/mono-tui-audit/SKILL.md)).
- [Documentation architecture and technical writing style](docs/writing-style.md): Diátaxis macro-to-micro hierarchy, dual representation rule, non-accretion rule, Google and Butterick typography rules, PowerShell backtick-escaping discipline, and PR and commit conventions.

## 1. Non-negotiable core invariants and guardrails

| Rule | Invariant | Description |
| :--- | :--- | :--- |
| Never | No hardcoded personal paths or internal names | Never commit personal paths (`C:\Users\<username>\`, `/Users/<username>/`, `/home/<username>/`) or company-internal hostnames, short links, monorepo paths, or product names. Use `$HOME`, `$env:USERPROFILE`, `$env:LOCALAPPDATA`, `$env:APPDATA`, `$PROFILE`, `Join-Path`, and `Split-Path`, keeping local hooks in untracked `$HOME\.config\windows-settings\{env.d,aliases.d,functions.d,cmd.d}\` and `$HOME\.config\ide\links.ps1` (`$env:IDE_LINK_RULES`). |
| Never | No CRLF versus LF or BOM violations | Enforced via `.gitattributes`: `.ps1`, `.psm1`, `.psd1`, `.cmd`, `.bat`, and `.doskey` strictly use `CRLF` (`\r\n`) because `cmd.exe` miscalculates byte offsets after `chcp 65001 >nul` on `LF` scripts (including `theme_env.cmd` and `mise_paths.cmd`). `.md`, `.json`, `.kdl`, `.yml`, `.yaml`, `.toml`, `.lock`, `.rs`, `.lua`, `.scm`, `.theme`, `.tmTheme`, `.sublime-syntax`, `.gitconfig`, `.conf`, `.txt`, and `LICENSE` strictly use `LF` (`\n`). Any `.ps1` with literal non-ASCII characters requires a UTF-8 BOM or `[char]0x...` escapes (`PSUseBOMForUnicodeEncodedFile`). |
| Never | No destructive overwrites, non-idempotency, or missing dry-run | Create `.bak_<timestamp>` backups before modifying user files (skipping unchanged files), deploy Windows Terminal JSON Fragments under `%LOCALAPPDATA%\Microsoft\Windows Terminal\Fragments\WindowsSettings\` while preserving user profiles across `LocalState`, `Microsoft.WindowsTerminal_8wekyb3d8bbwe`, and `Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe`, avoid duplicate profile or `git config --global include.path` entries, keep GUI apps opt-in (`-Gui` or `-WithGUI`), set `$ErrorActionPreference = 'Stop'` with graceful prerequisite checks (`winget`, `zellij`, `oh-my-posh`, `fzf`, `git`, `gh`, `wt`), and honor `-DryRun` or `--dry-run` across `setup.ps1`, `bootstrap.ps1`, `bin/theme.ps1`, `bin/ide.ps1`, `bin/install-nerd-fonts.ps1`, and `bin/update-system.ps1`. |
| Never | No legacy CLI shims, shadowed variables, or unguarded Git ops | Remove obsolete CLI flags cleanly so unknown options fail fast; never shadow PowerShell automatic variables (`$args`, `$input`, `$Host`, `$HOME`, `$PID`, `$PROFILE`, `$Error`, `$Matches`, `$PSItem`); keep `gprune` to merged branches (`git branch -d`) while `gpurge` requires confirmation (`-Force` or `-y`) before `git branch -D`; refuse renaming `main` or `master` in `guser-branch`; and verify clean tracked trees in `gsync`. |
| Never | No recursive startup scans, sync spawns, or alias collisions | Keep `$PROFILE` to 1 line (`Import-Module WindowsSettings -DisableNameChecking -ErrorAction SilentlyContinue`) targeting sub-10ms warm startup. Never run `Get-ChildItem -Recurse` or `Get-Command` `PATH` scans during module load; rely on timestamp-validated caches in `$HOME\.cache\{powershell,windows-settings}\` and `%LOCALAPPDATA%\cmd\` (`omp_init.ps1` with `"streaming": 150` and `"native_status": true`, `mise_paths.{ps1,cmd}`, `zoxide`, `gh`, `theme_env.{ps1,cmd}`), rotate `$env:POSH_SESSION_ID` and `$global:_ompStreamingState.ServeProcess` on theme switches, refresh `<branch>@<N>` PR and MR badges asynchronously (see [docs/ide-architecture.md](docs/ide-architecture.md#links-inline-images-clipboard-and-portable-shell-parity)), and un-alias `cat`, `sort`, `tee`, `diff`, `echo`, `sleep`, `ls`, `gcm`, `gl`, and `gp` (`cat` runs `uutils` `cat.exe`; `b` runs `bat`). |
| Never | No EOL Java releases | Provision active Java LTS releases (`java = "lts"`) via `mise.toml`; never target Java 8 or 11. |
| Never | No semantic color or syntax contract violations | Across all 22 built-in themes (14 classic and 8 US Holiday) and 40 languages, keep qualifiers (`std::`, `context.`) and factory calls (`NewService`) in `BASE0`; never fracture compound tokens (Go struct tags, `#[derive]`, `[[nodiscard]]`, `%s`, `'a`, `--custom-prop`, `#002b36`); keep `YELLOW` exclusive to control flow; keep `bold = false` on Markdown headings; keep TOML `[table]` Blue, `key =` Green, and timestamps Magenta; keep `.ps1`, `.psm1`, and `.psd1` in `BASE0` in `LS_COLORS` with crypto keys Magenta (`35`), archives Orange (`91`), and media Violet (`95`); and never remap classic physical hues or collide `GREEN`, `YELLOW`, and `RED` in holidays (see [docs/color-architecture.md](docs/color-architecture.md)). |
| Never | No Tree-sitter, LSP, or headless Neovim traps | Guard contextual keywords (`(?<!\.)`, `(?!\s*:)`), never rely on `@none` for `BASE0` resets, supersede upstream `url` metadata across the 13 base `.scm` queries in `config/nvim/queries/` without `;; extends` and never duplicate `queries/` and `after/queries/` (43 queries total with 30 extensions), use `#set! priority 130` on compound selector leaves, place generic catch-alls before `#lua-match?`, set `fg = "NONE"` on `DiagnosticUnderline*`, disable remote schema fetches (`jsonls`, `yamlls`), reap `%LOCALAPPDATA%\tree-sitter\lock\*.lock`, and run headless Neovim (`tests/sync-treesitter.lua`, `setup/modules/50-Neovim.ps1`) with `-i NONE`, `GIT_DEFAULT_REF_FORMAT=files`, and no multi-line `-c` strings. |
| Never | No root Ctrl+hjkl steals, tray daemons, or remapped :q | Keep `Ctrl+hjkl` internal to Neovim splits (`Alt+hjkl` universal), keep Zellij attention strictly in-terminal (`tray_icon false`, `desktop_notifications` disabled, `track_commands false`, `attention_muted=true` on `Editor`, and `zellij terminal --standalone` for `--desktop`), use direct `.NET NamedPipeClientStream` MsgPack-RPC (`\\.\pipe\nvim-ide-<session>`) owned exclusively by `Editor` (`SolarizedIdeSocket`), drive AI state strictly via `ide state` and `ide ack` across Antigravity, Claude Code, and Codex CLI (`setup/modules/75-AiHooks.ps1`), and never remap `:q`, `:wq`, `:qa`, or `:wqa` (use `:Q`, `:Quit`, `Space q`, `Alt+q`, `qide`, `quit`, or `idek`; see [docs/ide-architecture.md](docs/ide-architecture.md)). |
| Never | No duplicate agent files, scratch clutter, or unescaped backticks | Keep a single root `AGENTS.md` (never create `CLAUDE.md` or `.agents/AGENTS.md` or commit `target/`, `*.wasm`, `tmp_*`, or `.bak` files). Because `` ` `` is PowerShell's escape character, never pass Markdown backticks inside `"..."`; use `--body-file <path>`, `git commit -F <path>`, or single-quoted `@' ... '@` here-strings (see [docs/writing-style.md](docs/writing-style.md)). |
| Always | Dual-execution binaries and standalone _vimrc and autorun.cmd parity | Every `bin/` tool ships `<name>.ps1` paired with `<name>.cmd`, `config/vim/_vimrc` stays a zero-dependency 22-theme file (`$HOME\_vimrc` and `$HOME\.vimrc`), and `config/cmd/{autorun.cmd,macros.doskey}` provide native `cmd.exe` `BASE02` shelf prompt, `theme_env.cmd`, `mise_paths.cmd`, and `doskey /macrofile` parity. |
| Always | Clean entrypoint, setup/, libexec/, lua/solarized/, and fixtures boundaries | Keep `setup.ps1`, `bootstrap.ps1`, `bin/ide.ps1`, `bin/theme.ps1`, and `config/nvim/init.lua` thin. Place installer helpers and stages in `setup/{lib,modules}/*.ps1`, private libraries in `libexec/{ide,theme}/*.ps1` (keeping `bin/` restricted to the 7 user executables), Neovim modules in `config/nvim/lua/solarized/*.lua`, WASM sources in `plugin/ws-bar/`, and fixtures in `tests/fixtures/sample-code/`. |

## 2. Component matrix and associated test suites

| Component | Repository source | Target system location | Associated test coverage |
| :--- | :--- | :--- | :--- |
| Provisioning CLI and bootstrapper | `setup.ps1` and `bootstrap.ps1` | Root orchestrators (`.\setup.ps1`, `irm ... \| iex`) | `tests/test_settings.ps1`, `tests/suites/` |
| Installer libraries and stages | `setup/lib/*.ps1` and `setup/modules/*.ps1` (`00` through `99`) | Runtime for `setup.ps1` and `bin/update-system.ps1` | `tests/test_settings.ps1` (`setup`, `-DryRun`, `-Uninstall*`, backups) |
| Dual-execution CLI utilities | `bin/*.{ps1,cmd}` (`gen-passwd`, `ide`, `install-nerd-fonts`, `repeat-until-success`, `sum`, `theme`, `update-system`) | Registered in User `$env:Path` | `tests/test_settings.ps1` (CLI utilities, `.cmd` wrappers) |
| Internal IDE and theme packages | `libexec/ide/*.ps1` and `libexec/theme/*.ps1` | Private libraries dot-sourced by `bin/{ide,theme}.ps1` and `module/Developer.ps1` | `tests/test_settings.ps1` (`ide` subcommands, 22-theme sync) |
| PowerShell module, OMP, and cmd.exe | `module/*.{psd1,psm1,ps1}`, `config/powershell/*`, `config/cmd/{autorun.cmd,macros.doskey}` | `$HOME\Documents\PowerShell\Modules\WindowsSettings\`, `$PROFILE`, `$HOME\.poshthemes\`, `%LOCALAPPDATA%\cmd\` | `tests/test_settings.ps1` (82 exports, Git guards, completions, prompts) |
| Neovim, Tree-sitter, and Vim | `config/nvim/` (`init.lua`, `lua/solarized/*.lua`, `ftplugin/java.lua`, `queries/`, `after/queries/`) and `config/vim/_vimrc` | `$env:LOCALAPPDATA\nvim\`, `$HOME\_vimrc`, `$HOME\.vimrc` | `tests/test_settings.ps1` (43 `.scm` queries, `_vimrc`), `tests/sync-treesitter.lua` |
| Zellij workspace and WASM top bar | `config/zellij/` (`config.kdl`, `layouts/ide-{3,2}pane.kdl`, `themes/windows-settings.kdl`) and `plugin/ws-bar/` | `%APPDATA%\Zellij\config\` and `%APPDATA%\Zellij\data\plugins\windows-settings-bar.wasm` | `tests/test_settings.ps1` (`zellij setup --check`), `cargo test` |
| Themes, fragments, and CLI configs | `config/themes/*.theme` (22), `config/bat/`, `config/colors/LS_COLORS`, `config/terminal/`, `config/{btop,git,tealdeer,clangd}/` | `$HOME\.config\windows-settings\themes\`, `%APPDATA%\bat\`, `%LOCALAPPDATA%\Microsoft\Windows Terminal\Fragments\WindowsSettings\` | `tests/test_settings.ps1` (22 themes, 37 grammars, fragments, `btop4win`) |
| Polyglot toolchains and DSC | `mise.toml` and `configuration.dsc.yaml` | `$HOME\.config\mise\config.toml` and WinGet DSC v3 | `tests/test_settings.ps1` (DSC v3 and `mise.toml`) |
| Monospace TUI rules and skills | `.agents/rules/monospace-tui.md`, `.agents/skills/mono-tui-{design,audit}/` | `mono-tui v0.2.5` rules governing `bin/ide.ps1`, `libexec/ide/*.ps1`, `libexec/theme/{Generators,Preview}.ps1`, `config/zellij/**/*.kdl`, `plugin/ws-bar/src/**/*.rs`, and `config/nvim/lua/solarized/{ide,plugins}.lua` | `tests/test_settings.ps1`, `tests/lint/Invoke-DocLint.ps1` |
| Test runners, linters, and fixtures | `tests/test_settings.ps1`, `tests/suites/*.ps1`, `tests/lint/Invoke-DocLint.ps1`, `tests/sync-treesitter.lua`, `tests/fixtures/sample-code/*` | Verification and CI gatekeeper harness | `PSScriptAnalyzerSettings.psd1` and all suites |

## 3. Step-by-step task recipes for agents

Follow these workflows when extending toolchains, CLI options, shell modules, themes, plugins, or documentation:

- **Adding or updating a toolchain**: Declare `"lts"` (`java`, `node`) or `"latest"` in `mise.toml`, add WinGet client packages to `configuration.dsc.yaml` and `setup/modules/00-Packages.ps1` if needed, update `README.md`, `llms.txt`, and `tests/`, and run verification.
- **Adding a setup CLI option**: Declare the parameter in `setup.ps1` (and `bootstrap.ps1` if needed), implement `-DryRun` and live behavior in `setup/modules/<NN>-*.ps1`, document in `README.md` and `llms.txt`, and add tests.
- **Adding shell functions, aliases, or completions**: Edit `module/{Navigation,Git,Developer,Utilities,Completions}.ps1` using canonical section ordering (`param`, `$ErrorActionPreference = 'Stop'`, `Join-Path` constants, singular-noun helpers, `-DryRun` dispatch), export public functions in `module/WindowsSettings.psd1`, mirror in `config/cmd/macros.doskey`, update `README.md`, and add tests.
- **Adding a standalone CLI utility**: Create `bin/<name>.ps1` (`CRLF`) and `bin/<name>.cmd` (`CRLF`), place private modules in `libexec/<name>/`, register wrappers and completions in `module/` and `config/cmd/macros.doskey`, document in `README.md`, `CONTRIBUTING.md`, and `llms.txt`, and add tests.
- **Adding or updating a built-in color theme**: Edit `config/themes/<slug>.theme` (`THEME_CATEGORY`, `THEME_ORDER`, 16 core hex slots, plus optional `HOLIDAY_*` metadata), run `pwsh -NoProfile -File ./bin/theme.ps1 --sync-assets`, and check with `--check-assets`.
- **Adding or updating language highlighting**: Add a fixture in `tests/fixtures/sample-code/`, a standalone `.sublime-syntax` in `config/bat/syntaxes/`, a `.scm` query in `config/nvim/queries/` or `config/nvim/after/queries/` (never both), and a mapping in `config/colors/LS_COLORS`.
- **Modifying the Zellij WASM top-bar plugin**: Edit `plugin/ws-bar/src/` (`LF`, never committing `target/` or `*.wasm`), preserve `zellij:bars` fallback, and run `cargo test`, `cargo clippy --target wasm32-wasip1 -- -D warnings`, and `cargo build --release --target wasm32-wasip1`.
- **Updating documentation and pull requests**: Follow [docs/writing-style.md](docs/writing-style.md), synchronize `README.md`, `CONTRIBUTING.md`, `AGENTS.md`, `docs/*.md`, and `llms.txt` in the same PR, persist user corrections in `AGENTS.md`, and update PR bodies via `gh pr edit --body-file <path>`.

## 4. Anti-patterns and common traps

| Anti-pattern | Why it breaks | Correct implementation |
| :--- | :--- | :--- |
| Putting library folders in `bin/` or inlining into entrypoints | Pollutes User `$env:Path` and re-creates monoliths. | Keep `bin/` to 7 executables; put libraries in `libexec/{ide,theme}/`, stages in `setup/`, and Lua modules in `config/nvim/lua/solarized/`. |
| Writing `LF` to `.cmd`, `.bat`, `.doskey`, or `.ps1` files | `cmd.exe` miscalculates byte offsets after `chcp 65001 >nul`. | Enforce `CRLF` on `.ps1`, `.psm1`, `.psd1`, `.cmd`, `.bat`, and `.doskey` (`theme_env.cmd`) and `LF` on configs, Rust, Lua, and docs. |
| Passing Markdown backticks inside double-quoted PowerShell strings | PowerShell expands `` `e ``, `` `n ``, and `` `t `` inside `"..."`, corrupting text. | Use `--body-file <path>`, `git commit -F <path>`, or single-quoted `@' ... '@` here-strings. |
| Using `Get-ChildItem -Recurse` or child spawns in `WindowsSettings.psm1` | Regresses warm PowerShell startup past 10ms. | Dot-source module files explicitly and load compiled caches from `$HOME\.cache\powershell\`. |
| Enabling Zellij `tray_icon`, `desktop_notifications`, or unmuted `Editor` | Spawns OS tray icons, `.desk` daemons, or false `Working` badges. | Keep `tray_icon false`, `track_commands false`, `attention_muted=true` on `Editor`, and `zellij terminal --standalone`. |
| Keeping both `queries/<lang>/` and `after/queries/<lang>/` or `(#set! "url"` | Splits highlight precedence and injects unwanted URL underlines. | Supersede base queries in `config/nvim/queries/` without `;; extends`, or extend in `config/nvim/after/queries/` with `;; extends`. |
| Using `for /f "usebackq"` with leading `"` or unguarded `.cmd` and `.ps1` fallbacks | `cmd.exe /c` strips outer quotes across multiple `"..."` tokens and triggers mutual fork loops. | Redirect stdout to a temp file instead of `for /f`, and guard `.cmd` and `.ps1` fallbacks with `WS_IDE_TOGGLE_FROM_*` env flags. |

## 5. Verification checklist and definition of done

Before concluding any task:

1. **Verify theme asset synchronization and PowerShell static analysis**:
   ```powershell
   pwsh -NoProfile -File ./bin/theme.ps1 --check-assets
   Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
   ```

2. **Verify the Zellij WASM top-bar plugin** (when `cargo` and `wasm32-wasip1` are installed):
   ```powershell
   cargo test --manifest-path plugin/ws-bar/Cargo.toml
   cargo clippy --manifest-path plugin/ws-bar/Cargo.toml --target wasm32-wasip1 -- -D warnings
   cargo build --release --manifest-path plugin/ws-bar/Cargo.toml --target wasm32-wasip1
   ```

3. **Run the automated test and documentation lint suite**:
   ```powershell
   $null | pwsh -NoProfile -File ./tests/test_settings.ps1
   ```

4. **Verify path hygiene, line endings, and agent rule budget**:
   Inspect `git diff` to ensure zero personal paths or untracked scratch artifacts were introduced, `CRLF` and `LF` discipline holds, and `AGENTS.md` stays concise (under 24 KB) by placing deep subsystem specifications in `docs/*.md` and `.agents/`.
