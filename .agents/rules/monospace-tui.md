---
trigger: glob
globs: bin/ide.ps1, libexec/ide/**/*.ps1, libexec/theme/{Generators,Preview}.ps1, config/zellij/**/*.kdl, plugin/ws-bar/src/**/*.rs, config/nvim/lua/solarized/{ide,plugins}.lua
---

# Monospace TUI design standard and project rules

When designing, implementing, refactoring, or reviewing terminal UI surfaces in `bin/ide.ps1`, `libexec/ide/`,
`libexec/theme/{Generators,Preview}.ps1`, `config/zellij/**/*.kdl`, `plugin/ws-bar/src/`, or
`config/nvim/lua/solarized/{ide,plugins}.lua`, follow the embedded Monospace Design TUI (`mono-tui v0.2.5`)
specification alongside the project overrides and conventions declared in this file.

## Reference hierarchy

Consult these documents in precedence order (higher overrides lower when rules conflict):

1. **Project overrides and conventions**: The `[OVERRIDE]`, `[WAIVE]`, and `[P#]` entries in this file.
2. **Design and interaction standard**: [standard.md](../skills/mono-tui-design/references/standard.md) for screen
   and workflow archetypes, keyboard ergonomics, focus navigation, elevation, layout responsiveness, and content
   formatting.
3. **Rendering and implementation reference**: [rendering.md](../skills/mono-tui-design/references/rendering.md) for
   Unicode box-drawing tables, layout geometry, ANSI color tiers, component measurements, and color capability
   degradation.
4. **Canonical pattern library**: [patterns.md](../skills/mono-tui-design/references/patterns.md) for reusable
   interaction patterns (`Footer Command Bar`, `Focused Surface`, `Master-Detail`, `Expand-to-Focus`,
   `Object-Local Actions`, `Selection Grammar`, and `Live Drill-Down`) and audit checklists.
5. **Skill workflows**: [mono-tui-design](../skills/mono-tui-design/SKILL.md) for designing and implementing TUI
   features, and [mono-tui-audit](../skills/mono-tui-audit/SKILL.md) for auditing existing TUI views.

## Screen and workflow archetype mapping

The `bin/ide.ps1` terminal workspace, multi-session fleet switcher, and WASM status chrome map to the following
`mono-tui` archetypes:

*   **Workspace multiplexer shell** (`config/zellij/config.kdl`, `config/zellij/layouts/ide-{3,2}pane.kdl`,
    `plugin/ws-bar/src/`, and `libexec/ide/Workspace.ps1`): `§11.1` dashboard and operational cockpit header (1-line
    `BASE02` `ws-bar` `compact-bar` shelf with `Focused Surface` `▸` role pills for `AI`, `Editor`, and `Shell`,
    inline mode-contextual `TMUX`, `RESIZE`, and `SCROLL` key hints, and clickable urgent attention and fleet counters)
    framing frameless Level 1 panes for the AI Agent CLI, `§11.4` Neovim `Editor`, and interactive PowerShell `Shell`
    in Inverted-T (3-pane default) or side-by-side (`--2pane`) geometry.
*   **Multi-session workspace switcher** (`ide -s` or `ide switch` in `libexec/ide/{Fleet,Modals,Workspace}.ps1`):
    `§11.5` fuzzy finder paired with a responsive `Master-Detail` split view (`§12.4` search-act and `§12.3`
    monitor-respond workflows). On terminals at or above `90` columns, the left region renders the urgency-ordered
    `fzf` session list across live and saved workspaces while the right preview pane streams `--follow` ANSI viewport
    snapshots (`zellij action dump-screen --ansi` for active sessions or recent Git commits for stopped sessions,
    labeled `[PREVIEW]` versus `[LIVE]` for the attached workspace) without mutating live pane geometry. Pressing
    `Alt+n` (`ide new`) enters an `Expand-to-Focus` `New IDE >` workspace-creation card (`Tab` agent cycling and
    `Alt+2` layout toggle), `Alt+o` (`ide dir`) enters the `fzf` existing-directory picker with `90`-column responsive
    directory and VCS previews (`ide _internal dir-preview`), and `Alt+r` (`ide agent`) opens the compact AI Agent
    switch and in-place restart selector.
*   **Keybinding cheatsheet and fleet status table** (`ide keys` in `libexec/ide/Modals.ps1` and `ide list` in
    `libexec/ide/Fleet.ps1`): Contextual two-column modal overlay (`Alt+?`, `Space ?`, `Ctrl+b ?`, or `F1`) rendering
    a spacious `108×34` (`<= 104×30` inner) sheet on standard and wide canvases with automatic `80×24` (`<= 76×22`)
    compact fallback, and `§R4.6` aligned fleet table pairing status colors with non-color markers (`▸` active,
    `!` attention, `[unsaved]` dirty guard).

## Project overrides and conventions

The sections below document every intentional `[OVERRIDE]` and `[WAIVE]` against the upstream `mono-tui v0.2.5`
specification alongside `windows-settings` project conventions (`[P1]` through `[P4]`).

### [OVERRIDE] §6.1 single-line calm workspace borders and rounded popup borders

*   **Original**: Applications MUST NOT use double-line borders for Level 0–2 elements. Applications MUST NOT use single-line borders for Level 3–4 elements.
*   **Project rule**: Main `ide` workspace split panes (`AI`, `Editor`, `Shell`) run frameless (`pane_frames false` in
    `config/zellij/config.kdl`) while Zellij frame tokens (`config/zellij/themes/windows-settings.kdl`), Neovim split
    dividers (`WinSeparator` and `FloatBorder`), and `fzf` switcher frames (`libexec/ide/{Fleet,Modals}.ps1`) stay
    unified in calm single-line `BASE01` so structural lines never render high-chroma seams or compete with content
    (`AGENTS.md` and `docs/color-architecture.md` Pillar I). Active pane focus is communicated through the `ws-bar`
    top shelf `▸` role indicator in workspaces and through left-aligned `▸` and `[LIVE]` versus `[PREVIEW]` border
    labels inside switcher modals. Level 3 and Level 4 Zellij floating panes and `fzf` frames (`--border=rounded` with
    `border`, `separator`, and `label` pinned to `BASE01`, and `spinner` colored `CYAN` only while `WORKING` `--follow`
    previews stream, masked to `BASE03` under `NO_MOTION=1` or `REDUCE_MOTION=1` per `§10.3`) use single-line rounded
    borders (`╭╮╰╯`) rather than double-line `═║╔╗╚╝` characters.
*   **Reason**: Eliminates high-chroma border distraction across frameless Zellij panes and Neovim splits while
    maintaining unmistakable `Focused Surface` label differentiation (`§5.5` and `§9.6`).

### [OVERRIDE] §6.3 left-aligned pane border titles with explicit preview versus live mode

*   **Original**: Window and panel titles MUST be centered in the top border row:
*   **Project rule**: `fzf` `--border-label` and `--preview-label` headers in `libexec/ide/{Fleet,Modals}.ps1`
    left-align container titles in the top border (`▸ Sessions` on the left list; `[PREVIEW]` when streaming read-only
    ANSI viewport output versus `▸ ... [LIVE]` when highlighting the currently attached workspace).
*   **Reason**: Anchors scan lines to the left margin above left-aligned session rows and makes preview versus
    attached state immediately legible (`patterns.md` `Focused Surface`).

### [OVERRIDE] §6.6 rounded corners for interactive popup and fuzzy-finder containers

*   **Original**: Rounded corner characters (`╭╮╰╯`) MAY be used for cosmetic, non-interactive containers (e.g., decorative cards, informational callouts). Rounded corners MUST NOT be used for interactive windows, dialogs, or panels that participate in the elevation system.
*   **Project rule**: Interactive Zellij floating command modals (`floating true` in `config/zellij/config.kdl` and
    `libexec/ide/Modals.ps1`) and `fzf` pickers (`--border=rounded` in `libexec/ide/{Fleet,Modals}.ps1` and
    `libexec/theme/Preview.ps1`) use rounded `╭╮╰╯` corners as the workstation's unified overlay frame geometry.
*   **Reason**: Visually separates transient overlay modals (`Alt+s`, `Alt+n`, `Alt+o`, `Alt+r`, `Alt+m`, `Alt+?`) from
    the rectilinear `─│` splits of the underlying `ide` workspace.

### [OVERRIDE] §1.6 90-column side-by-side split breakpoint for the workspace switcher

*   **Original**: | Compact | 40–79 | Region A collapses; Region C hidden or stacked below B; footer reduces to single row |
*   **Project rule**: `$SideBySideMinCols = 90` in `libexec/ide/{Fleet,Modals}.ps1` and `libexec/theme/Preview.ps1`
    gates two-pane side-by-side preview splits on `>= 90` columns. Below `90` columns (including `80×24` minimum viable
    terminals, `§1.5`, and `50%` split panes), `ide switch` (`down:50%:wrap:noinfo`) and `bin/theme.ps1`
    (`down:58%:nowrap:noinfo`) automatically stack their preview pane below the `fzf` list. Inside Neovim
    (`config/nvim/lua/solarized/plugins.lua`), Telescope uses `layout_strategy = "flex"` (`flip_columns = 110`) to
    stack file paths and code previews vertically inside narrow Editor splits, while `mini.files` scales `width_focus`
    below `80` columns so split Editor panes retain their right-hand preview window down to `42` columns.
*   **Reason**: Side-by-side horizontal splits below `90` to `110` columns crush multi-column tables, file paths, and
    code previews into `< 38` columns, whereas vertical stacking and proportional split scaling preserve legibility.

### [OVERRIDE] §1.4 and §R4.11 top-bar mode hints and middle-dot-separated width-fitted fzf footers

*   **Original**: Format: `F1 Help  F5 Refresh  / Filter  q Quit` — key name followed by action label, separated by 2+ spaces. (CUA §1 function key area, Norton Commander F-key bar)
*   **Project rule**: In the main `ide` workspace, persistent bottom rows belong exclusively to inner applications
    (Oh My Posh shell prompt and Neovim statusline), so workspace-level `TMUX`, `RESIZE`, `SCROLL`, fleet, and
    `Help (Alt+?)` discoverability lives in the 1-row top `ws-bar` WASM status shelf (`plugin/ws-bar/src/render.rs` and
    `libexec/theme/Generators.ps1`, `docs/color-architecture.md` Pillar VIII), scaling across `cols >= 120` (full key
    hints), `105` (holiday and subdirectory pills), and `95` (`80×24` compact role tabs and `[A]`, `[E]`, `[T]` parked
    markers). Inside `fzf` pickers (`libexec/ide/{Fleet,Modals}.ps1`), footer `--border-label` hints join actions with
    middle-dot separators (`" · "`, `U+00B7`) fitted to the exact pane width so narrow splits never clip an action
    mid-word.
*   **Reason**: Preserves zero-clutter bottom statuslines for shells and Neovim while keeping top-bar chrome and `fzf`
    command bars self-teaching and truncation-safe across all terminal widths.

### [OVERRIDE] §2.2 and §2.8 4-layer spatial Alt navigation, fzf Tab multi-select, and fuzzy input

*   **Original**: All single-letter key bindings MUST be case-insensitive — `r` and `R` trigger the same action, `d` and `D` trigger the same action, etc. Applications MUST bind both cases but MUST display only the lowercase form in the footer key strip.
*   **Project rule**: Inside `ide` workspaces, unmodified printable keys and `Ctrl+h/j/k/l` belong strictly to the
    active foreground application (`Layer 1`), while `Alt`-modified chords (`Alt+h/j/k/l`, `Alt+a/e/t`, `Alt+s`,
    `Alt+n`, `Alt+o`, `Alt+r`, `Alt+m`, `Alt+q`, `Alt+?`) and `Shift`-distinct counterparts (`Alt+Shift+H/J/K/L` swap,
    `Alt+Shift+A/E/T` park, `Alt+Shift+S` next attention, `Alt+Shift+Q` force-quit) govern workspace actions
    (`Layer 2`). Inside `ide -s` (`§11.5` fuzzy layer), all printable characters feed the `fzf` filter, `Tab` toggles
    multi-session selection (`--multi`) for batch `Ctrl+y` acknowledgment and `Ctrl+x` quit, `F5` and `Ctrl+r` reload
    the fleet list, and `F1` and `Alt+?` open the contextual keybinding cheatsheet (`ide keys`, which closes on `q`,
    `Q`, `Esc`, `?`, `Alt+?`, `F1`, `Space`, or `Enter`).
*   **Reason**: Prevents Zellij bindings from hijacking PSReadLine, Neovim, or AI CLI keys while supporting
    multi-session batch triage in `fzf`.

### [OVERRIDE] §7.1 and §7.2 zero-bold monospace typography and pointer focus markers

*   **Original**: - Focused text MUST use reverse video (SGR 7).
*   **Project rule**: Across `config/zellij/`, `plugin/ws-bar/src/`, `libexec/theme/Generators.ps1`, and `libexec/ide/`,
    UI labels and status pills keep unbolded typography (`bold = false` in `solarized-dark` and daily-driver themes,
    `docs/color-architecture.md` Pillar I) on TrueColor and 256-color terminals, indicating active pane, tab, and row
    focus via the `▸` (`U+25B8`) pointer glyph paired with `BASE1` on `BASE02` contrast
    (`--color=bg+:BASE02,fg+:BASE1,pointer:GREEN` in `fzf`) rather than full reverse-video bars (`SGR 7`), reserving
    `SGR 1` and `SGR 7` for `TERM=dumb` monochrome degradation (`§R3.4`).
*   **Reason**: Preserves zero-jitter monospace glyph widths and calm `60-30-10` Solarized luminance balance while
    retaining non-color glyph indicators (`▸`, `[LIVE]`, `[PREVIEW]`, `!`, `[unsaved]`) for accessibility (`§5.3`).

### [OVERRIDE] §R3.2 multi-theme 14-slot semantic palette with 4-tier color degradation

*   **Original**: | Primary | 75 (light blue) | 17 (dark blue) | fg #5fafff, bg #00005f |
*   **Project rule**: All `bin/ide.ps1`, `ws-bar`, and Zellij colors derive from the active `windows-settings` theme
    (`libexec/ide/Core.ps1` and `libexec/theme/Generators.ps1`) across the 22 built-in themes (`config/themes/*.theme`)
    and user `$HOME\.config\windows-settings\themes\*.theme` files, degrading across four capability tiers (`§5.6` and
    `§R7.1`): 24-bit TrueColor (`$env:COLORTERM` set to `truecolor` or `24bit`, or Windows Terminal `$env:WT_SESSION`),
    256-color (`256color`), 16-color ANSI, and Monochrome or `NO_COLOR` (`$env:TERM -eq 'dumb'` SGR attributes or empty
    escapes under `$env:NO_COLOR`).
*   **Reason**: Keeps `ide` visually unified with Neovim, `bat`, `delta`, `btop4win`, `eza`, and Oh My Posh while
    remaining clean and operable on restricted SSH, ConPTY, or `NO_COLOR` terminals.

### [OVERRIDE] §R1.7 single-character horizontal ellipsis for truncation

*   **Original**: | `⋯` | MIDLINE HORIZONTAL ELLIPSIS | U+22EF | Truncation indicator |
*   **Project rule**: Truncation helpers in `libexec/ide/Core.ps1` and `plugin/ws-bar/src/render.rs` use the
    single-column horizontal ellipsis `…` (`U+2026`) when truncating session names, branch labels, and hook summary
    messages.
*   **Reason**: `U+2026` has deterministic 1-cell width across standard monospace terminal fonts on Windows Terminal
    and ConPTY.

### [WAIVE] §6.4 drop shadows on Zellij floating panes and switcher modals

*   **Original**: Shadows at Levels 2–4 MUST be rendered as a 2-column × 1-row offset below and to the right of the bordered element.
*   **Project rule**: Do not render `░` (`U+2591`) or custom character-cell drop shadows around Zellij floating command
    panes, `context_menu` overlays, or `fzf` switcher modals.
*   **Reason**: Native Zellij floating pane and menu primitives composite rectangular viewports directly in Rust without
    exposing exterior shadow cells to child processes.

### [WAIVE] §6.5 background scrims behind Zellij floating panes and Expand-to-Focus views

*   **Original**: Level 4 (modal overlay) MUST dim all background content behind the modal. The scrim MUST apply the dim attribute (SGR 2) to all non-modal cells while preserving their character content.
*   **Project rule**: Do not rewrite background pane buffers to simulate an `SGR 2` scrim when opening Zellij floating
    overlays (`Alt+s`, `Alt+n`, `Alt+o`, `Alt+r`, `Alt+m`, `Alt+?`) or `Expand-to-Focus` views.
*   **Reason**: Mutating live ConPTY pane buffers behind a Zellij floating pane would corrupt running TUI applications;
    rounded `BASE01` modal borders clearly bound the overlay surface.

### [P1] Nerd Font workstation icons with zero classic-theme emojis and ASCII opt-out

*   **Project rule**: On provisioned `windows-settings` workstations (`MesloLGS Nerd Font Mono`), `ws-bar` and
    `bin/ide.ps1` use monotone Nerd Font PUA icons (`U+EEB8`, `U+F06A9`, `U+E6AE`, `U+F489`, `U+F009A`) and never emit
    fixed-bitmap color emojis in `solarized-dark` or any of the 14 classic daily-driver themes. Whenever
    `$env:IDE_NERD_FONTS = '0'` (or `$env:IDE_ASCII = '1'` or `$env:TERM -eq 'dumb'`) is set (`libexec/ide/Core.ps1`),
    all `bin/ide.ps1` surfaces (`ide list`, `ide -s`, `ide _internal session-preview`, and `ide keys`) omit PUA
    codepoints and fall back to universal ASCII and standard Unicode markers (`▸`, `*`, `!`, `…`).
*   **Reason**: Preserves crisp monotone iconography on configured workstations while guaranteeing zero tofu (`□`) when
    inspecting sessions from unprovisioned remote or fallback terminals.

### [P2] ANSI-safe East Asian and tab-aware cell width math and responsive popup clamping

*   **Project rule**: All column alignment, truncation, preview fitting, and footer packing in `libexec/ide/`
    (`Core.ps1`, `Fleet.ps1`, `Modals.ps1`), `libexec/theme/Preview.ps1`, and `plugin/ws-bar/src/render.rs` must
    measure visible cell widths accounting for ANSI escapes, tabs, combining marks, and 2-cell CJK or wide glyphs,
    terminate styled lines with `\x1b[0m`, fit interactive TTY table and preview outputs (`ide list`, `theme --list`,
    and strictly rectangular `theme --preview` cards) to the active viewport while leaving piped non-TTY output
    untruncated, and clamp modals (`ide keys` at `108×34` max `104×30` inner body on `>= 108×34` canvases, adapting to
    `<= 76×22` on `80×24` terminals; `ide -s` and `bin/theme.ps1` stacked below `90` columns) so `80×24` terminals and
    split panes never wrap borders or clip critical controls (`§1.5`).
*   **Reason**: Prevents right-edge wrap corruption, CJK and tab bottom-line clipping in `fzf` previews, and modal or
    table overflow on compact terminals and `50%` split panes.

### [P3] zero-polling WASM status chrome and throttled fzf --follow previews

*   **Project rule**: Top `ws-bar` status chrome renders in Rust WASM (`wasm32-wasip1`) strictly from event-driven
    Zellij state updates (`TabUpdate`, `PaneUpdate`, `ModeUpdate`, `SessionUpdate`, and `ws-ide-state` pipe messages)
    with zero background shell polling. Inside `ide -s`, `fzf` `--follow` preview workers
    (`ide _internal session-preview`) stream deduplicated ANSI snapshots (`zellij action dump-screen --ansi`
    continuously only while `WORKING` and throttled VCS metadata) without resizing or mutating background workspace
    panes.
*   **Reason**: Eliminates pane resize storms, scrollback resets, cursor jumps, and subprocess stutter during rapid
    fuzzy navigation.

### [P4] non-TTY, missing-fzf, and fallback backend degradation

*   **Project rule**: When `fzf` is unavailable, `ide switch` degrades cleanly to `ide list` or prints
    `No active IDE sessions.` when empty; when non-interactive, `ide keys` writes the cheatsheet directly to `stdout`
    without blocking on raw console key reads; when `btop4win` (`btop`) is absent, `ide monitor` falls back to the
    built-in PowerShell TUI process monitor; and when Zellij is absent or `--backend wt` is requested, `ide` degrades
    to Windows Terminal split panes.
*   **Reason**: Keeps every `ide` subcommand deterministic and scriptable across minimal runners, CI harnesses, and
    non-interactive shells.
