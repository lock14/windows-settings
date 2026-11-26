use zellij_tile::graphemes::display_width;
use zellij_tile::prelude::{AttentionStatus, GlobalAttention, InputMode, ModeInfo, TabInfo};

use crate::palette::{holiday_emblem, Rgb, ThemePalette};
use crate::roles::{IdeRole, RoleSlot, RoleStrip};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ClickTarget {
    SessionCard,
    Role(IdeRole),
    Zoom,
    Tab(usize),
    NormalMode,
    ToggleSync,
    NextAttention,
    SessionManager,
    Monitor,
    Help,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct HitRegion {
    pub start_col: usize,
    pub end_col: usize,
    pub target: ClickTarget,
    pub tab_index: Option<usize>,
}

impl HitRegion {
    pub fn contains(&self, col: usize) -> bool {
        col >= self.start_col && col < self.end_col
    }
}

#[derive(Debug, Clone)]
struct Span {
    text: String,
    fg: Rgb,
    target: Option<ClickTarget>,
    tab_index: Option<usize>,
}

impl Span {
    fn plain(text: impl Into<String>, fg: Rgb) -> Self {
        Self {
            text: text.into(),
            fg,
            target: None,
            tab_index: None,
        }
    }

    fn clickable(text: impl Into<String>, fg: Rgb, target: ClickTarget) -> Self {
        let tab_index = match target {
            ClickTarget::Tab(pos) => Some(pos),
            _ => None,
        };
        Self {
            text: text.into(),
            fg,
            target: Some(target),
            tab_index,
        }
    }

    fn width(&self) -> usize {
        display_width(&self.text)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum DetailLevel {
    Full,
    NoMonitor,
    NoKeyHints,
    CompactPills,
    Minimal,
}

impl DetailLevel {
    const ALL: [DetailLevel; 5] = [
        DetailLevel::Full,
        DetailLevel::NoMonitor,
        DetailLevel::NoKeyHints,
        DetailLevel::CompactPills,
        DetailLevel::Minimal,
    ];
}

pub struct RenderContext<'a> {
    pub cols: usize,
    pub palette: &'a ThemePalette,
    pub mode_info: &'a ModeInfo,
    pub tabs: &'a [TabInfo],
    pub roles: &'a RoleStrip,
    pub global_attention: Option<&'a GlobalAttention>,
    pub theme_slug: &'a str,
    pub subdir_label: Option<&'a str>,
    pub holiday_icon: Option<&'a str>,
}

#[derive(Debug, Default)]
pub struct RenderedBar {
    pub ansi: String,
    pub regions: Vec<HitRegion>,
}

fn displayed_session_name(mode_info: &ModeInfo) -> String {
    if mode_info.mode == InputMode::RenameSession {
        return match mode_info.session_name.as_deref() {
            Some(name) if !name.is_empty() => name.to_owned(),
            _ => "Enter name...".to_owned(),
        };
    }
    mode_info
        .session_name
        .as_deref()
        .filter(|s| !s.is_empty())
        .unwrap_or("workspace")
        .to_owned()
}

fn resolve_session_icon<'a>(ctx: &'a RenderContext<'a>) -> &'a str {
    ctx.holiday_icon
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .or_else(|| holiday_emblem(ctx.theme_slug).map(|(ic, _)| ic))
        .unwrap_or("\u{EBC8}")
}

fn truncate_to_cols(text: &str, max_cols: usize) -> String {
    if max_cols == 0 {
        return String::new();
    }
    if display_width(text) <= max_cols {
        return text.to_owned();
    }
    if max_cols == 1 {
        return "\u{2026}".to_owned();
    }
    let mut out = String::new();
    let mut used = 0;
    for ch in text.chars() {
        let mut buf = [0u8; 4];
        let w = display_width(ch.encode_utf8(&mut buf));
        if used + w + 1 > max_cols {
            break;
        }
        out.push(ch);
        used += w;
    }
    out.push('\u{2026}');
    out
}

fn role_unfocused_color(slot: &RoleSlot, p: &ThemePalette) -> Rgb {
    match slot.attention {
        AttentionStatus::NeedsYou if slot.quota => p.yellow,
        AttentionStatus::NeedsYou => p.orange,
        AttentionStatus::Failed => p.red,
        AttentionStatus::Done => p.green,
        AttentionStatus::Working => p.cyan,
        _ if slot.hidden => p.base01,
        _ => p.base0,
    }
}

fn push_role_badge(
    spans: &mut Vec<Span>,
    slot: &RoleSlot,
    p: &ThemePalette,
    level: DetailLevel,
) {
    let (icon, active_accent, key_normal, key_parked) = match slot.role {
        IdeRole::Ai => ("\u{F06A9}", p.cyan, "(Alt+a)", "[Alt+A]"),
        IdeRole::Editor => ("\u{E6AE}", p.blue, "(Alt+e)", "[Alt+E]"),
        IdeRole::Shell => ("\u{F489}", p.green, "(Alt+t)", "[Alt+T]"),
    };
    let show_keys = matches!(level, DetailLevel::Full | DetailLevel::NoMonitor);
    let target = ClickTarget::Role(slot.role);

    if slot.focused {
        spans.push(Span::clickable(
            format!("\u{25B8} {icon} "),
            active_accent,
            target,
        ));
        let suffix = if show_keys {
            format!("{} {key_normal}", slot.label)
        } else if level == DetailLevel::Minimal {
            String::new()
        } else {
            slot.label.clone()
        };
        if !suffix.is_empty() {
            spans.push(Span::clickable(suffix, p.base1, target));
        }
    } else {
        let fg = role_unfocused_color(slot, p);
        let key_hint = if slot.hidden { key_parked } else { key_normal };
        let label = if show_keys {
            format!("{icon} {} {key_hint}", slot.label)
        } else if level == DetailLevel::Minimal {
            icon.to_owned()
        } else {
            format!("{icon} {}", slot.label)
        };
        spans.push(Span::clickable(label, fg, target));
    }
}

fn build_left_and_center(ctx: &RenderContext<'_>, level: DetailLevel) -> Vec<Span> {
    let p = ctx.palette;
    let mut spans = Vec::with_capacity(16);

    if !ctx.mode_info.style.hide_session_name || ctx.mode_info.mode == InputMode::RenameSession {
        let max_sess = match level {
            DetailLevel::Minimal => 14,
            DetailLevel::CompactPills => 20,
            _ => 28,
        };
        let sess_icon = resolve_session_icon(ctx);
        let sess = truncate_to_cols(&displayed_session_name(ctx.mode_info), max_sess);
        spans.push(Span::clickable(
            format!(" {sess_icon} {sess} "),
            p.blue,
            ClickTarget::SessionCard,
        ));
        spans.push(Span::plain("\u{E0B1} ", p.base00));
    } else {
        spans.push(Span::plain(" ", p.base0));
    }

    let active_tab = ctx.tabs.iter().find(|t| t.active);
    let active_is_ide = active_tab
        .map(|t| t.name.eq_ignore_ascii_case("ide") || ctx.tabs.len() == 1)
        .unwrap_or(true)
        && ctx.roles.has_any();

    if active_is_ide {
        let present_slots: Vec<&RoleSlot> = [
            ctx.roles.ai.as_ref(),
            ctx.roles.editor.as_ref(),
            ctx.roles.shell.as_ref(),
        ]
        .into_iter()
        .flatten()
        .collect();

        for (idx, slot) in present_slots.iter().enumerate() {
            if idx > 0 {
                spans.push(Span::plain(" \u{00B7} ", p.base01));
            }
            push_role_badge(&mut spans, slot, p, level);
        }

        if active_tab.is_some_and(|t| t.is_fullscreen_active) {
            spans.push(Span::plain(" \u{E0B1} ", p.base00));
            let zoom_text = if matches!(level, DetailLevel::Full | DetailLevel::NoMonitor) {
                "\u{F004C} ZOOM (Alt+z)"
            } else {
                "\u{F004C} ZOOM"
            };
            spans.push(Span::clickable(zoom_text, p.orange, ClickTarget::Zoom));
        }

        if ctx.tabs.len() > 1 && level != DetailLevel::Minimal {
            spans.push(Span::plain(" \u{E0B1} ", p.base00));
            let mut first_extra = true;
            for tab in ctx.tabs.iter().filter(|t| !t.active) {
                if !first_extra {
                    spans.push(Span::plain(" ", p.base01));
                }
                first_extra = false;
                let name = truncate_to_cols(&tab.name, 12);
                spans.push(Span::clickable(
                    format!("{}:{name}", tab.position + 1),
                    p.base01,
                    ClickTarget::Tab(tab.position),
                ));
            }
        }
    } else if !ctx.tabs.is_empty() {
        for (idx, tab) in ctx.tabs.iter().enumerate() {
            if idx > 0 {
                spans.push(Span::plain(" \u{00B7} ", p.base01));
            }
            let name = truncate_to_cols(&tab.name, 16);
            if tab.active {
                spans.push(Span::clickable(
                    format!("\u{25B8} {}:{name}", tab.position + 1),
                    p.base1,
                    ClickTarget::Tab(tab.position),
                ));
                if tab.is_fullscreen_active {
                    spans.push(Span::clickable(
                        " \u{F004C} ZOOM",
                        p.orange,
                        ClickTarget::Zoom,
                    ));
                }
            } else {
                spans.push(Span::clickable(
                    format!("{}:{name}", tab.position + 1),
                    p.base01,
                    ClickTarget::Tab(tab.position),
                ));
            }
        }
    }

    spans
}

pub(crate) fn attention_summary(
    global: Option<&GlobalAttention>,
    current_session: Option<&str>,
    p: &ThemePalette,
) -> Option<(String, Rgb)> {
    let global = global?;
    if global.attention_disabled {
        return None;
    }

    let eff_current = current_session
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .or_else(|| {
            let cur = global.current_session.trim();
            if cur.is_empty() {
                None
            } else {
                Some(cur)
            }
        });

    let mut sessions: Vec<(&str, AttentionStatus)> = Vec::new();
    for item in &global.items {
        if item.is_muted() || item.is_current {
            continue;
        }
        if eff_current.is_some_and(|cur| item.session == cur) {
            continue;
        }
        let status = item.item.attention.status;
        let actionable = match status {
            AttentionStatus::NeedsYou | AttentionStatus::Failed => true,
            AttentionStatus::Done => !item.item.attention.seen,
            _ => item.item.attention.from_watch,
        };
        if !actionable {
            continue;
        }
        if !sessions.iter().any(|(s, _)| *s == item.session.as_str()) {
            sessions.push((item.session.as_str(), status));
        }
    }

    let (first_session, top_status) = *sessions.first()?;
    let fg = match top_status {
        AttentionStatus::Failed => p.red,
        AttentionStatus::Done => p.green,
        _ => p.orange,
    };
    let short = truncate_to_cols(first_session, 18);
    let label = if sessions.len() == 1 {
        format!("\u{F009A} {short}")
    } else {
        format!("\u{F009A} {short} +{}", sessions.len() - 1)
    };
    Some((label, fg))
}

fn mode_overlay(
    mode: InputMode,
    p: &ThemePalette,
) -> Option<(&'static str, Rgb, &'static str, &'static str)> {
    match mode {
        InputMode::Normal => None,
        InputMode::Locked => Some((
            "\u{F033E} LOCKED",
            p.red,
            "Ctrl+g unlock",
            "Ctrl+g",
        )),
        InputMode::Tmux => Some((
            "\u{F0633} TMUX",
            p.orange,
            "HJKL resize \u{00B7} |/- split \u{00B7} n/o ws \u{00B7} r refresh \u{00B7} b bar \u{00B7} ? keys \u{00B7} Esc",
            "? keys \u{00B7} Esc",
        )),
        InputMode::Resize => Some((
            "\u{F0655} RESIZE",
            p.orange,
            "h/j/k/l grow \u{00B7} H/J/K/L shrink \u{00B7} =/+/- \u{00B7} Esc normal",
            "hjkl \u{00B7} Esc",
        )),
        InputMode::Pane => Some((
            "\u{EB26} PANE",
            p.orange,
            "n new \u{00B7} d/r split \u{00B7} x close \u{00B7} z zoom \u{00B7} f float \u{00B7} Esc normal",
            "n/x/z \u{00B7} Esc",
        )),
        InputMode::Tab => Some((
            "\u{F0681} TAB",
            p.orange,
            "n new \u{00B7} r rename \u{00B7} x close \u{00B7} h/l switch \u{00B7} s sync \u{00B7} Esc normal",
            "n/r/x \u{00B7} Esc",
        )),
        InputMode::Move => Some((
            "\u{F01DB} MOVE",
            p.orange,
            "h/j/k/l move pane \u{00B7} n/Tab cycle \u{00B7} Esc normal",
            "hjkl \u{00B7} Esc",
        )),
        InputMode::Scroll => Some((
            "\u{F018F} SCROLL",
            p.magenta,
            "j/k scroll \u{00B7} d/u half-page \u{00B7} / search \u{00B7} e edit \u{00B7} Esc clear",
            "j/k \u{00B7} / \u{00B7} Esc",
        )),
        InputMode::EnterSearch => Some((
            "\u{F0349} SEARCH?",
            p.magenta,
            "type query \u{00B7} Enter search \u{00B7} Esc cancel",
            "Enter \u{00B7} Esc",
        )),
        InputMode::Search => Some((
            "\u{F0349} SEARCH",
            p.magenta,
            "n/p next/prev \u{00B7} c case \u{00B7} w wrap \u{00B7} Esc clear",
            "n/p \u{00B7} Esc",
        )),
        InputMode::Session => Some((
            "\u{EBC8} SESSION",
            p.orange,
            "w manager \u{00B7} d detach \u{00B7} c config \u{00B7} Esc normal",
            "w/d \u{00B7} Esc",
        )),
        InputMode::RenameTab | InputMode::RenamePane | InputMode::RenameSession => Some((
            "\u{F03EB} RENAME",
            p.yellow,
            "Enter confirm \u{00B7} Esc cancel",
            "Enter \u{00B7} Esc",
        )),
        InputMode::Prompt => Some((
            "\u{F02FD} PROMPT",
            p.yellow,
            "Enter confirm \u{00B7} Esc cancel",
            "Enter \u{00B7} Esc",
        )),
    }
}

fn build_right(ctx: &RenderContext<'_>, level: DetailLevel) -> Vec<Span> {
    let p = ctx.palette;
    let mut spans = Vec::with_capacity(14);

    if let Some((badge, badge_fg, wide_hints, short_hints)) = mode_overlay(ctx.mode_info.mode, p) {
        spans.push(Span::plain(" \u{E0B3} ", p.base00));
        spans.push(Span::clickable(
            format!("{badge} "),
            badge_fg,
            ClickTarget::NormalMode,
        ));
        if level != DetailLevel::Minimal {
            spans.push(Span::plain("\u{E0B3} ", p.base00));
            let hints = match level {
                DetailLevel::Full | DetailLevel::NoMonitor => format!("{wide_hints} "),
                _ => format!("{short_hints} "),
            };
            spans.push(Span::plain(hints, p.base0));
        }
        return spans;
    }

    let active_tab = ctx.tabs.iter().find(|t| t.active);
    if active_tab.is_some_and(|t| t.is_sync_panes_active) {
        spans.push(Span::plain(" \u{E0B3} ", p.base00));
        spans.push(Span::clickable(
            "\u{F04E6} SYNC ",
            p.red,
            ClickTarget::ToggleSync,
        ));
    }

    if level != DetailLevel::Minimal {
        if let Some(sub) = ctx.subdir_label.map(str::trim).filter(|s| !s.is_empty()) {
            let short_sub = truncate_to_cols(sub, 18);
            spans.push(Span::plain(" \u{E0B3} ", p.base00));
            spans.push(Span::plain(format!("\u{F024B} {short_sub} "), p.blue));
        }
    }

    let current_session = ctx.mode_info.session_name.as_deref();
    if let Some((attn_label, attn_fg)) = attention_summary(ctx.global_attention, current_session, p)
    {
        spans.push(Span::plain(" \u{E0B3} ", p.base00));
        spans.push(Span::clickable(
            format!("{attn_label} "),
            attn_fg,
            ClickTarget::NextAttention,
        ));
    }

    let hol = holiday_emblem(ctx.theme_slug);
    let sess_icon = resolve_session_icon(ctx);

    let total_sessions = ctx
        .global_attention
        .map(|g| g.running().max(1))
        .unwrap_or(1);
    let working_sessions = ctx
        .global_attention
        .map(|g| {
            g.sessions
                .iter()
                .filter(|s| s.attention.counts.working > 0)
                .count()
        })
        .unwrap_or(0);

    spans.push(Span::plain(" \u{E0B3} ", p.base00));
    match level {
        DetailLevel::Full | DetailLevel::NoMonitor => {
            spans.push(Span::clickable(
                format!("{sess_icon} {total_sessions} \u{00B7} "),
                p.base0,
                ClickTarget::SessionManager,
            ));
            let active_fg = if working_sessions > 0 { p.cyan } else { p.base0 };
            spans.push(Span::clickable(
                format!("{working_sessions} active"),
                active_fg,
                ClickTarget::SessionManager,
            ));
            spans.push(Span::clickable(
                " (Alt+s) ",
                p.base0,
                ClickTarget::SessionManager,
            ));
        }
        DetailLevel::NoKeyHints => {
            spans.push(Span::clickable(
                format!("{sess_icon} {total_sessions} \u{00B7} "),
                p.base0,
                ClickTarget::SessionManager,
            ));
            let active_fg = if working_sessions > 0 { p.cyan } else { p.base0 };
            spans.push(Span::clickable(
                format!("{working_sessions} active "),
                active_fg,
                ClickTarget::SessionManager,
            ));
        }
        DetailLevel::CompactPills | DetailLevel::Minimal => {
            let fg = if working_sessions > 0 { p.cyan } else { p.base0 };
            spans.push(Span::clickable(
                format!("{sess_icon} {total_sessions} "),
                fg,
                ClickTarget::SessionManager,
            ));
        }
    }

    if let Some((_, badge)) = hol {
        if matches!(level, DetailLevel::Full | DetailLevel::NoMonitor) && ctx.cols >= 120 {
            spans.push(Span::plain("\u{E0B3} ", p.base00));
            spans.push(Span::plain(format!("{badge} "), p.yellow));
        }
    }

    if level == DetailLevel::Full && ctx.cols >= 140 {
        spans.push(Span::plain("\u{E0B3} ", p.base00));
        spans.push(Span::clickable(
            "\u{F035B} Monitor (Alt+m) ",
            p.base0,
            ClickTarget::Monitor,
        ));
    }

    if level != DetailLevel::Minimal {
        spans.push(Span::plain("\u{E0B3} ", p.base00));
        let help_text = match level {
            DetailLevel::Full | DetailLevel::NoMonitor => "\u{F02D6} Help (Alt+?) ",
            DetailLevel::NoKeyHints => "\u{F02D6} Help ",
            DetailLevel::CompactPills | DetailLevel::Minimal => "\u{F02D6} ",
        };
        spans.push(Span::clickable(help_text, p.base0, ClickTarget::Help));
    }

    spans
}

fn spans_width(spans: &[Span]) -> usize {
    spans.iter().map(Span::width).sum()
}

fn emit_spans(
    spans: &[Span],
    palette: &ThemePalette,
    cursor_col: &mut usize,
    max_cols: usize,
    out: &mut String,
    regions: &mut Vec<HitRegion>,
) {
    for span in spans {
        if *cursor_col >= max_cols {
            break;
        }
        let remaining = max_cols - *cursor_col;
        let text = if span.width() <= remaining {
            span.text.clone()
        } else {
            truncate_to_cols(&span.text, remaining)
        };
        let w = display_width(&text);
        if w == 0 {
            continue;
        }
        palette.write_sgr(out, span.fg);
        out.push_str(&text);

        if let Some(target) = span.target {
            let start = *cursor_col;
            let end = start + w;
            if let Some(last) = regions.last_mut() {
                if last.end_col == start && last.target == target && last.tab_index == span.tab_index
                {
                    last.end_col = end;
                } else {
                    regions.push(HitRegion {
                        start_col: start,
                        end_col: end,
                        target,
                        tab_index: span.tab_index,
                    });
                }
            } else {
                regions.push(HitRegion {
                    start_col: start,
                    end_col: end,
                    target,
                    tab_index: span.tab_index,
                });
            }
        }
        *cursor_col += w;
    }
}

pub fn render_shelf(ctx: &RenderContext<'_>) -> RenderedBar {
    if ctx.cols == 0 {
        return RenderedBar::default();
    }

    let mut chosen = (Vec::new(), Vec::new());
    for level in DetailLevel::ALL {
        let left = build_left_and_center(ctx, level);
        let right = build_right(ctx, level);
        let needed =
            spans_width(&left) + if right.is_empty() { 0 } else { 1 + spans_width(&right) };
        chosen = (left, right);
        if needed <= ctx.cols {
            break;
        }
    }

    let (left_spans, right_spans) = chosen;
    let right_w = spans_width(&right_spans);
    let mut ansi = String::with_capacity(ctx.cols * 4);
    let mut regions = Vec::with_capacity(12);
    let mut col = 0;

    if right_w > 0 && right_w + 4 <= ctx.cols {
        let left_budget = ctx.cols - right_w;
        emit_spans(
            &left_spans,
            ctx.palette,
            &mut col,
            left_budget,
            &mut ansi,
            &mut regions,
        );
        if col < left_budget {
            let pad = left_budget - col;
            ctx.palette.write_sgr(&mut ansi, ctx.palette.base0);
            for _ in 0..pad {
                ansi.push(' ');
            }
            col += pad;
        }
        emit_spans(
            &right_spans,
            ctx.palette,
            &mut col,
            ctx.cols,
            &mut ansi,
            &mut regions,
        );
    } else {
        emit_spans(
            &left_spans,
            ctx.palette,
            &mut col,
            ctx.cols,
            &mut ansi,
            &mut regions,
        );
    }

    if col < ctx.cols {
        let pad = ctx.cols - col;
        ctx.palette.write_sgr(&mut ansi, ctx.palette.base0);
        for _ in 0..pad {
            ansi.push(' ');
        }
    }
    ansi.push_str("\x1b[0m");

    RenderedBar { ansi, regions }
}

#[cfg(test)]
mod tests {
    use super::*;
    use zellij_tile::prelude::{
        AttentionCounts, AttentionItem, GlobalAttentionItem, GlobalSessionAttention, PaneAttention,
        PaneId, SessionAttention,
    };

    fn strip_ansi(raw: &str) -> String {
        let mut out = String::new();
        let mut chars = raw.chars().peekable();
        while let Some(c) = chars.next() {
            if c == '\x1b' && chars.peek() == Some(&'[') {
                chars.next();
                for next in chars.by_ref() {
                    if next.is_ascii_alphabetic() {
                        break;
                    }
                }
                continue;
            }
            out.push(c);
        }
        out
    }

    fn standard_roles() -> RoleStrip {
        RoleStrip {
            ai: Some(RoleSlot {
                role: IdeRole::Ai,
                pane_id: 0,
                focused: true,
                hidden: false,
                label: "AI".to_owned(),
                attention: AttentionStatus::Idle,
                attention_unseen: false,
                quota: false,
            }),
            editor: Some(RoleSlot {
                role: IdeRole::Editor,
                pane_id: 1,
                focused: false,
                hidden: false,
                label: "Editor".to_owned(),
                attention: AttentionStatus::Idle,
                attention_unseen: false,
                quota: false,
            }),
            shell: Some(RoleSlot {
                role: IdeRole::Shell,
                pane_id: 2,
                focused: false,
                hidden: false,
                label: "Shell".to_owned(),
                attention: AttentionStatus::Idle,
                attention_unseen: false,
                quota: false,
            }),
            visible_tiled_count: 3,
        }
    }

    fn ide_tab(zoomed: bool) -> TabInfo {
        TabInfo {
            position: 0,
            name: "ide".to_owned(),
            active: true,
            is_fullscreen_active: zoomed,
            ..Default::default()
        }
    }

    #[test]
    fn renders_exact_column_width_across_viewport_sizes() {
        let palette = ThemePalette::default();
        let mode = ModeInfo {
            mode: InputMode::Normal,
            session_name: Some("windows-settings".to_owned()),
            ..Default::default()
        };
        let tabs = vec![ide_tab(true)];
        let roles = standard_roles();

        for cols in [45, 72, 100, 128, 165] {
            let bar = render_shelf(&RenderContext {
                cols,
                palette: &palette,
                mode_info: &mode,
                tabs: &tabs,
                roles: &roles,
                global_attention: None,
                theme_slug: "",
                subdir_label: None,
                holiday_icon: None,
            });
            let plain = strip_ansi(&bar.ansi);
            assert_eq!(display_width(&plain), cols, "width mismatch at cols={cols}");
        }
    }

    #[test]
    fn wide_shelf_exposes_all_clickable_ide_pills() {
        let palette = ThemePalette::default();
        let mode = ModeInfo {
            mode: InputMode::Normal,
            session_name: Some("windows-settings".to_owned()),
            ..Default::default()
        };
        let tabs = vec![ide_tab(true)];
        let roles = standard_roles();
        let item = AttentionItem {
            pane_id: PaneId::Terminal(0),
            tab_id: 0,
            tab_name: "ide".to_owned(),
            pane_title: "AI".to_owned(),
            attention: PaneAttention {
                status: AttentionStatus::NeedsYou,
                ..Default::default()
            },
        };
        let global = GlobalAttention {
            current_session: "windows-settings".to_owned(),
            sessions: vec![GlobalSessionAttention {
                name: "other-repo".to_owned(),
                is_current: false,
                attention: SessionAttention {
                    status: AttentionStatus::NeedsYou,
                    counts: AttentionCounts {
                        needs_you: 1,
                        working: 1,
                        ..Default::default()
                    },
                    items: vec![item.clone()],
                    ..Default::default()
                },
            }],
            items: vec![GlobalAttentionItem {
                session: "other-repo".to_owned(),
                is_current: false,
                item,
            }],
            ..Default::default()
        };

        let bar = render_shelf(&RenderContext {
            cols: 180,
            palette: &palette,
            mode_info: &mode,
            tabs: &tabs,
            roles: &roles,
            global_attention: Some(&global),
            theme_slug: "",
            subdir_label: None,
            holiday_icon: None,
        });
        let plain = strip_ansi(&bar.ansi);
        assert!(plain.contains("windows-settings"));
        assert!(plain.contains("AI (Alt+a)"));
        assert!(plain.contains("Editor (Alt+e)"));
        assert!(plain.contains("Shell (Alt+t)"));
        assert!(plain.contains("ZOOM (Alt+z)"));
        assert!(plain.contains("other-repo"));
        assert!(plain.contains("1 active (Alt+s)"));
        assert!(plain.contains("Monitor (Alt+m)"));
        assert!(plain.contains("Help (Alt+?)"));

        let targets: Vec<ClickTarget> = bar.regions.iter().map(|r| r.target).collect();
        assert!(targets.contains(&ClickTarget::SessionCard));
        assert!(targets.contains(&ClickTarget::Role(IdeRole::Ai)));
        assert!(targets.contains(&ClickTarget::Role(IdeRole::Editor)));
        assert!(targets.contains(&ClickTarget::Role(IdeRole::Shell)));
        assert!(targets.contains(&ClickTarget::Zoom));
        assert!(targets.contains(&ClickTarget::NextAttention));
        assert!(targets.contains(&ClickTarget::SessionManager));
        assert!(targets.contains(&ClickTarget::Monitor));
        assert!(targets.contains(&ClickTarget::Help));
    }

    #[test]
    fn suppresses_self_session_alerts_on_right_shelf() {
        let palette = ThemePalette::default();
        let item = AttentionItem {
            pane_id: PaneId::Terminal(0),
            tab_id: 0,
            tab_name: "ide".to_owned(),
            pane_title: "AI".to_owned(),
            attention: PaneAttention {
                status: AttentionStatus::NeedsYou,
                ..Default::default()
            },
        };
        let self_only = GlobalAttention {
            current_session: "windows-settings".to_owned(),
            items: vec![GlobalAttentionItem {
                session: "windows-settings".to_owned(),
                is_current: false,
                item: item.clone(),
            }],
            ..Default::default()
        };
        assert_eq!(
            attention_summary(Some(&self_only), Some("windows-settings"), &palette),
            None
        );

        let mixed = GlobalAttention {
            current_session: "windows-settings".to_owned(),
            items: vec![
                GlobalAttentionItem {
                    session: "windows-settings".to_owned(),
                    is_current: true,
                    item: item.clone(),
                },
                GlobalAttentionItem {
                    session: "peer-ws".to_owned(),
                    is_current: false,
                    item,
                },
            ],
            ..Default::default()
        };
        let (lbl, fg) = attention_summary(Some(&mixed), Some("windows-settings"), &palette)
            .expect("peer session alert should render");
        assert_eq!(lbl, "\u{F009A} peer-ws");
        assert_eq!(fg, palette.orange);
    }

    #[test]
    fn tmux_mode_replaces_right_shelf_with_contextual_hints() {
        let palette = ThemePalette::default();
        let mode = ModeInfo {
            mode: InputMode::Tmux,
            session_name: Some("ws".to_owned()),
            ..Default::default()
        };
        let tabs = vec![ide_tab(false)];
        let roles = standard_roles();

        let bar = render_shelf(&RenderContext {
            cols: 140,
            palette: &palette,
            mode_info: &mode,
            tabs: &tabs,
            roles: &roles,
            global_attention: None,
            theme_slug: "",
            subdir_label: None,
            holiday_icon: None,
        });
        let plain = strip_ansi(&bar.ansi);
        assert!(plain.contains("TMUX"));
        assert!(plain.contains("HJKL resize"));
        assert!(plain.contains("r refresh"));
        assert!(bar.regions.iter().any(|r| r.target == ClickTarget::NormalMode));
    }

    #[test]
    fn renders_quota_yellow_subdir_pill_and_holiday_emblem() {
        let palette = ThemePalette::default();
        let mode = ModeInfo {
            mode: InputMode::Normal,
            session_name: Some("ws".to_owned()),
            ..Default::default()
        };
        let tabs = vec![ide_tab(false)];
        let mut roles = standard_roles();
        if let Some(ai) = roles.ai.as_mut() {
            ai.focused = false;
            ai.attention = AttentionStatus::NeedsYou;
            ai.quota = true;
        }
        if let Some(ed) = roles.editor.as_mut() {
            ed.focused = true;
        }
        if let Some(sh) = roles.shell.as_mut() {
            sh.hidden = true;
        }

        let bar = render_shelf(&RenderContext {
            cols: 190,
            palette: &palette,
            mode_info: &mode,
            tabs: &tabs,
            roles: &roles,
            global_attention: None,
            theme_slug: "halloween",
            subdir_label: Some("ws-bar"),
            holiday_icon: None,
        });
        let plain = strip_ansi(&bar.ansi);
        assert!(plain.contains("\u{1F383} ws"));
        assert!(plain.contains("\u{1F383} \u{1F47B} Halloween"));
        assert!(plain.contains("\u{F024B} ws-bar"));
        assert!(plain.contains("Shell [Alt+T]"));
        let Rgb(yr, yg, yb) = palette.yellow;
        assert!(bar.ansi.contains(&format!("38;2;{yr};{yg};{yb};")));
    }
}
