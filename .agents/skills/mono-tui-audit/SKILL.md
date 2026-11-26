---
name: mono-tui-audit
description: Audit `windows-settings` terminal UI code (`bin/ide.ps1`, `libexec/ide/`, `config/zellij/`, `plugin/ws-bar/`, `libexec/theme/`, and `config/nvim/lua/solarized/ide.lua`) against the Monospace Design TUI (`mono-tui v0.2.5`) specification and `.agents/rules/monospace-tui.md`. Use when reviewing TUI changes, checking `80×24` layout and color degradation compliance, or diagnosing visual, preview, and keyboard bugs.
---

# Monospace TUI audit skill

Use this skill when auditing or reviewing `bin/ide.ps1`, `libexec/ide/`, `libexec/theme/{Generators,Preview}.ps1`,
`config/zellij/**/*.kdl`, `plugin/ws-bar/src/`, or `config/nvim/lua/solarized/{ide,plugins}.lua` against the Monospace
Design TUI (`mono-tui v0.2.5`) specification and `windows-settings` project rules.

## Audit reference order

1. [monospace-tui.md](../../rules/monospace-tui.md): Load all `[OVERRIDE]`, `[WAIVE]`, and `[P#]` entries first.
   Never flag an intentional project override or waiver as a violation; instead, verify the code follows the stated
   "Project rule" entry.
2. [standard.md](../mono-tui-design/references/standard.md): Check keyboard navigation, focus indicators, `80×24`
   minimum dimensions, layout responsiveness, and color independence rules that are not overridden.
3. [rendering.md](../mono-tui-design/references/rendering.md): Check `§R1` to `§R4` and `§R7` rendering rules (box
   alignment, SGR reset discipline, component measurements, and 4-tier color capability degradation).
4. [patterns.md](../mono-tui-design/references/patterns.md): Compare against `Footer Command Bar`, `Focused Surface`,
   `Master-Detail`, `Expand-to-Focus`, and `Search/Select Set` checklists.
5. [AGENTS.md](../../../AGENTS.md): Verify repository-wide glyph hygiene, zero-polling WASM status chrome, public
   path and `CRLF` versus `LF` line-ending hygiene, and test coverage.

## Step-by-step audit checklist

1. **Glyph, theme, and color capability degradation**:
   * Confirm zero decorative emojis appear in `solarized-dark` or any of the 14 classic daily-driver themes, and
     confirm `$env:IDE_NERD_FONTS = '0'` and `$env:TERM -eq 'dumb'` omit PUA icons cleanly across `ide list`, `ide -s`,
     `ide _internal session-preview`, and `ide keys` (`[P1]`).
   * Confirm palette and cheatsheet renderers in `libexec/ide/{Core,Modals}.ps1` honor `NO_COLOR`, `TERM=dumb`
     monochrome SGR attributes, 256-color, 16-color, and 24-bit TrueColor (`[OVERRIDE] §R3.2`, `§5.6`, and `§R7.1`),
     and pair every status color with a non-color text or symbol indicator (`§5.3`).
2. **Container framing, focused-surface cues, and preview clarity**:
   * Confirm workspace panes remain frameless (`pane_frames false`) while Zellij theme borders, `fzf` frames, and
     Neovim `WinSeparator` stay unified in calm `BASE01`, and confirm switcher panes render explicit `[PREVIEW]` versus
     `▸ ... [LIVE]` left-aligned top-border labels (`[OVERRIDE] §6.1`, `§6.3`, `§6.6`, and `patterns.md`
     `Focused Surface`).
3. **Width math, 80×24 responsiveness, and footer parity**:
   * Confirm `$SideBySideMinCols = 90` (`libexec/ide/{Fleet,Modals}.ps1` and `libexec/theme/Preview.ps1`) stacks
     vertically below `90` columns (`[OVERRIDE] §1.6`), footer `--border-label` builders pack complete `" · "`-separated
     hints within the pane width with zero mid-word clipping (`[OVERRIDE] §1.4 and §R4.11`), top `ws-bar` chrome scales
     cleanly across `120`, `105`, and `95`-column tiers, Neovim Telescope (`flex`) and `mini.files` adapt inside narrow
     split panes, and `ide keys` fits inside `108×34` (`<= 104` columns and `<= 30` lines) while degrading cleanly to
     `<= 76×22` on `80×24` viewports (`[P2]`).
   * Confirm cell-width and truncation helpers (`…`, `[OVERRIDE] §R1.7`) in `libexec/ide/Core.ps1`,
     `libexec/theme/Preview.ps1`, and `plugin/ws-bar/src/render.rs` preserve East Asian wide-char and tab alignment,
     keep `theme --preview` strictly rectangular, and append `\x1b[0m` on styled lines while leaving piped CLI outputs
     untruncated.
4. **Keyboard layers, WASM bar reactivity, and zero-jank previews**:
   * Confirm zero unmodified printable or root `Ctrl+h/j/k/l` bindings exist in `config/zellij/config.kdl`, and confirm
     `F1` (`ide keys`) and `F5` (`reload`) work alongside `Alt+?` and `Ctrl+r` inside `ide -s`
     (`[OVERRIDE] §2.2 and §2.8`).
   * Confirm `ws-bar` updates strictly from event-driven Zellij events and `ws-ide-state` messages without shell
     polling, and confirm `ide -s` `--follow` previews stream deduplicated frames without resizing background workspace
     panes (`[P3]`).
5. **Override freshness and lint parity**:
   * Run `$null | pwsh -NoProfile -File ./tests/test_settings.ps1` (and `tests/lint/Invoke-DocLint.ps1` when present)
     to verify every `### [OVERRIDE]` and `### [WAIVE]` section in `.agents/rules/monospace-tui.md` contains a verbatim
     `**Original**:` quote from `standard.md`, `rendering.md`, or `patterns.md`, and all documentation links and
     keybinding tables stay synchronized.

## Audit report format

Group findings by severity:

* **Blocking violations**: Rules broken in `monospace-tui.md`, `standard.md`, or `rendering.md` with file path, line
  range, section reference, and concrete fix.
* **Non-blocking polish**: Minor layout, readability, or test coverage improvements prefixed with `Nit:`.
* **Verified compliant areas**: Summary of audited checks that passed.
