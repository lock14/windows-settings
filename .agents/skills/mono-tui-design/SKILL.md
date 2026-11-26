---
name: mono-tui-design
description: Design and build terminal user interfaces for windows-settings (`bin/ide.ps1`, `libexec/ide/`, `config/zellij/`, `plugin/ws-bar/`, and `libexec/theme/`) following the Monospace Design TUI (`mono-tui v0.2.5`) specification and project rules. Use when adding, modifying, or styling IDE views, floating panes, layouts, WASM status bars, themes, or keybindings.
---

# Monospace TUI design skill

Use this skill when designing, implementing, or refactoring terminal UI views, Zellij and `ws-bar` chrome, `fzf`
pickers, floating modals, themes, or keyboard interactions in `bin/ide.ps1`, `libexec/ide/`,
`libexec/theme/{Generators,Preview}.ps1`, `config/zellij/**/*.kdl`, `plugin/ws-bar/src/`, or
`config/nvim/lua/solarized/{ide,plugins}.lua`.

## Reference reading order

Always resolve rules in this order (higher overrides lower):

1. [monospace-tui.md](../../rules/monospace-tui.md): Project-specific `[OVERRIDE]`, `[WAIVE]`, and `[P#]` rules for
   `windows-settings`.
2. [standard.md](references/standard.md): The Monospace Design TUI (`mono-tui v0.2.5`) interaction, layout, keyboard,
   and archetype specification.
3. [rendering.md](references/rendering.md): Character encodings, layout geometry, ANSI color palettes, component
   measurements, and color capability degradation (`§R1` to `§R4` and `§R7`).
4. [patterns.md](references/patterns.md): Canonical interaction patterns and audit checklists (`Footer Command Bar`,
   `Focused Surface`, `Master-Detail`, `Expand-to-Focus`, and `Search/Select Set`).
5. [AGENTS.md](../../../AGENTS.md): Repository-wide architecture, 14-slot Solarized and 22-theme palette contract,
   keybinding layers, line-ending discipline, and testing invariants.

## Design and implementation workflow

1. **Identify the screen and workflow archetype**:
   * Map changes to `ide`'s `§11.1` operational cockpit top shelf (`plugin/ws-bar/src/` and `config/zellij/`),
     `§11.5` fuzzy finder and `Master-Detail` workspace switcher (`ide -s` in `libexec/ide/{Fleet,Modals,Workspace}.ps1`),
     `Expand-to-Focus` workspace launcher (`Alt+n` `New IDE >` and `Alt+o` `ide dir`), or responsive `108×34` and
     `80×24` modal overlays (`ide keys` in `libexec/ide/Modals.ps1`).
2. **Apply project overrides, focus clarity, and glyph hygiene**:
   * Keep workspace panes frameless (`pane_frames false` in `config/zellij/config.kdl`) and keep Zellij frame tokens,
     `fzf` borders, and Neovim `WinSeparator` calm in `BASE01` (`[OVERRIDE] §6.1`), distinguishing preview versus
     attached switcher state via left-aligned `[PREVIEW]` versus `▸ ... [LIVE]` top-border labels (`[OVERRIDE] §6.3`).
   * Keep the 14 classic daily-driver themes 100% free of vendor-bitmap emojis, and gate Nerd Font PUA glyphs in
     `bin/ide.ps1` and `libexec/ide/` through `$env:IDE_NERD_FONTS = '0'` and `$env:TERM -eq 'dumb'` ASCII fallback
     (`[P1]`).
   * Derive all colors through the active palette helpers in `libexec/ide/Core.ps1` and
     `libexec/theme/Generators.ps1` (`[OVERRIDE] §R3.2`), supporting 24-bit TrueColor, 256-color, 16-color,
     `TERM=dumb` monochrome SGR attributes, and `NO_COLOR`.
3. **Preserve keyboard layers and CUA dual-key discoverability**:
   * Never bind unmodified printable keys or root `Ctrl+h/j/k/l` in `config/zellij/config.kdl`
     (`[OVERRIDE] §2.2 and §2.8`).
   * Keep `F1` (`ide keys`) and `F5` (`reload`) bound alongside `Alt+?` and `Ctrl+r` inside `ide -s`, and keep footer
     `--border-label` hints width-fitted with `" · "` separators so actions never clip mid-word
     (`[OVERRIDE] §1.4 and §R4.11`).
   * Synchronize any user-facing keybinding or CLI flag across both conceptual prose and reference tables in
     `README.md`.
4. **Enforce defensive rendering, streaming previews, and 80×24 geometry**:
   * Gate two-pane side-by-side `ide -s` (`libexec/ide/{Fleet,Modals}.ps1`) and `bin/theme.ps1`
     (`libexec/theme/Preview.ps1`) layouts on `90` columns (`[OVERRIDE] §1.6`), stacking vertically on narrower
     viewports, flipping Neovim Telescope (`layout_strategy = "flex"`) below `110` columns, and scaling `mini.files`
     below `80` columns so split panes keep their preview windows.
   * Keep `ide keys` within `<= 104` columns and `<= 30` lines inside `108×34` floating panes on standard canvases
     while degrading to `<= 76` columns and `<= 22` lines on `80×24` terminals, scale the top `ws-bar` shelf across
     `120`, `105`, and `95`-column tiers, and fit interactive `ide list`, `ide new`, and `theme --list` and `--preview`
     outputs to the active TTY width without truncating piped output (`[P2]`).
   * Render `ws-bar` purely from event-driven WASM updates without shell polling, and stream deduplicated `fzf`
     `--follow` ANSI previews without resizing background panes (`[P3]`).
5. **Verify with static analysis, WASM builds, and automated tests**:
   * Run `Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1`,
     `cargo test --manifest-path plugin/ws-bar/Cargo.toml`, and `$null | pwsh -NoProfile -File ./tests/test_settings.ps1`
     to validate PowerShell AST hygiene, WASM bar rendering, verbatim `[OVERRIDE]` and `[WAIVE]` freshness,
     documentation links, and all test suites.
