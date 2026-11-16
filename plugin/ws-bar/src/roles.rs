use zellij_tile::prelude::{
    AttentionItem, AttentionStatus, BlockedKind, GlobalAttention, PaneId, PaneInfo,
};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum IdeRole {
    Ai,
    Editor,
    Shell,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RoleSlot {
    pub role: IdeRole,
    pub pane_id: u32,
    pub focused: bool,
    pub hidden: bool,
    pub label: String,
    pub attention: AttentionStatus,
    pub quota: bool,
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct RoleStrip {
    pub ai: Option<RoleSlot>,
    pub editor: Option<RoleSlot>,
    pub shell: Option<RoleSlot>,
    pub visible_tiled_count: usize,
}

impl RoleStrip {
    pub fn focused_role(&self) -> Option<IdeRole> {
        if self.ai.as_ref().is_some_and(|r| r.focused) {
            Some(IdeRole::Ai)
        } else if self.editor.as_ref().is_some_and(|r| r.focused) {
            Some(IdeRole::Editor)
        } else if self.shell.as_ref().is_some_and(|r| r.focused) {
            Some(IdeRole::Shell)
        } else {
            None
        }
    }

    pub fn slot(&self, role: IdeRole) -> Option<&RoleSlot> {
        match role {
            IdeRole::Ai => self.ai.as_ref(),
            IdeRole::Editor => self.editor.as_ref(),
            IdeRole::Shell => self.shell.as_ref(),
        }
    }

    pub fn has_any(&self) -> bool {
        self.ai.is_some() || self.editor.is_some() || self.shell.is_some()
    }
}

fn match_role_from_command(cmd: &str) -> Option<IdeRole> {
    let lower = cmd.to_ascii_lowercase();
    if lower.contains("--pane-init") {
        let tokens: Vec<&str> = lower.split_whitespace().collect();
        for window in tokens.windows(2) {
            if window[0].trim_matches('"') == "--pane-init" {
                match window[1].trim_matches('"') {
                    "ai" => return Some(IdeRole::Ai),
                    "editor" => return Some(IdeRole::Editor),
                    "term" | "shell" => return Some(IdeRole::Shell),
                    _ => {}
                }
            }
        }
    }
    None
}

fn match_role_from_title(title: &str) -> Option<IdeRole> {
    let trimmed = title.trim();
    if trimmed.is_empty() {
        return None;
    }
    let lower = trimmed.to_ascii_lowercase();
    let head = lower
        .split(|c: char| c.is_whitespace() || c == ':' || c == '-' || c == '(' || c == '\\' || c == '/')
        .find(|s| !s.is_empty())
        .unwrap_or(&lower);
    let head_stem = head.strip_suffix(".exe").unwrap_or(head);

    match head_stem {
        "ai" | "agy" | "antigravity" | "claude" | "codex" | "gemini" => Some(IdeRole::Ai),
        "editor" | "nvim" | "vim" => Some(IdeRole::Editor),
        "shell" | "term" | "pwsh" | "powershell" | "cmd" => Some(IdeRole::Shell),
        _ => None,
    }
}

fn detect_ai_label(pane: &PaneInfo, attn_app: Option<&str>) -> String {
    if let Some(app) = attn_app {
        let trimmed = app.trim();
        if !trimmed.is_empty() {
            return normalize_ai_name(trimmed);
        }
    }
    let lower = pane.title.trim().to_ascii_lowercase();
    for known in ["agy", "claude", "codex", "gemini"] {
        if lower == known || lower.starts_with(&format!("{known} ")) || lower.starts_with(&format!("{known}:")) {
            return known.to_owned();
        }
    }
    "AI".to_owned()
}

fn normalize_ai_name(raw: &str) -> String {
    let lower = raw.trim().to_ascii_lowercase();
    match lower.as_str() {
        "antigravity" | "agy" => "agy".to_owned(),
        "claude" | "claude-code" => "claude".to_owned(),
        "codex" => "codex".to_owned(),
        "gemini" | "gemini-cli" => "gemini".to_owned(),
        _ => "AI".to_owned(),
    }
}

fn pane_attention_state(
    pane_id: u32,
    items: &[AttentionItem],
) -> (AttentionStatus, bool, Option<String>) {
    let target = PaneId::Terminal(pane_id);
    for item in items {
        if item.pane_id == target {
            let app = item.attention.detail.app.clone();
            if item.attention.is_muted() {
                return (AttentionStatus::Idle, false, app);
            }
            let status = match item.attention.status {
                AttentionStatus::Done if item.attention.seen => AttentionStatus::Idle,
                other => other,
            };
            let quota = status == AttentionStatus::NeedsYou
                && item.attention.detail.kind == Some(BlockedKind::Auth);
            return (status, quota, app);
        }
    }
    (AttentionStatus::Idle, false, None)
}

pub fn current_session_items(global: Option<&GlobalAttention>) -> &[AttentionItem] {
    let Some(global) = global else {
        return &[];
    };
    global
        .sessions
        .iter()
        .find(|s| s.is_current)
        .map(|s| s.attention.items.as_slice())
        .unwrap_or(&[])
}

pub fn classify_ide_roles(
    panes: &[PaneInfo],
    are_floating_visible: bool,
    attn_items: &[AttentionItem],
) -> RoleStrip {
    let candidates: Vec<&PaneInfo> = panes
        .iter()
        .filter(|p| !p.is_plugin && !p.exited && p.is_selectable)
        .collect();

    let mut ai_pane: Option<&PaneInfo> = None;
    let mut ed_pane: Option<&PaneInfo> = None;
    let mut sh_pane: Option<&PaneInfo> = None;
    let mut used_ids = Vec::with_capacity(3);

    // Pass 1: Explicit `--pane-init <role>` command arguments from ide-3pane.kdl / ide-2pane.kdl.
    for pane in &candidates {
        if let Some(cmd) = pane.terminal_command.as_deref() {
            if let Some(role) = match_role_from_command(cmd) {
                match role {
                    IdeRole::Ai if ai_pane.is_none() => {
                        ai_pane = Some(pane);
                        used_ids.push(pane.id);
                    }
                    IdeRole::Editor if ed_pane.is_none() => {
                        ed_pane = Some(pane);
                        used_ids.push(pane.id);
                    }
                    IdeRole::Shell if sh_pane.is_none() => {
                        sh_pane = Some(pane);
                        used_ids.push(pane.id);
                    }
                    _ => {}
                }
            }
        }
    }

    // Pass 2: Pane title heuristics (`AI`, `Editor`, `Shell`, or active tool binary name).
    for pane in &candidates {
        if used_ids.contains(&pane.id) {
            continue;
        }
        if let Some(role) = match_role_from_title(&pane.title) {
            match role {
                IdeRole::Ai if ai_pane.is_none() => {
                    ai_pane = Some(pane);
                    used_ids.push(pane.id);
                }
                IdeRole::Editor if ed_pane.is_none() => {
                    ed_pane = Some(pane);
                    used_ids.push(pane.id);
                }
                IdeRole::Shell if sh_pane.is_none() => {
                    sh_pane = Some(pane);
                    used_ids.push(pane.id);
                }
                _ => {}
            }
        }
    }

    // Pass 3: Spatial geometry fallback for serialized or renamed tiled panes inside `ide`.
    let mut remaining_tiled: Vec<&PaneInfo> = candidates
        .iter()
        .copied()
        .filter(|p| !used_ids.contains(&p.id) && !p.is_floating && !p.is_suppressed)
        .collect();
    remaining_tiled.sort_by_key(|p| (p.pane_y, p.pane_x, p.id));

    if !remaining_tiled.is_empty() {
        let min_y = remaining_tiled.iter().map(|p| p.pane_y).min().unwrap_or(0);
        for pane in remaining_tiled {
            if ai_pane.is_none() && pane.pane_y == min_y {
                ai_pane = Some(pane);
            } else if ed_pane.is_none() && pane.pane_y == min_y {
                ed_pane = Some(pane);
            } else if sh_pane.is_none() {
                sh_pane = Some(pane);
            }
        }
    }

    let visible_tiled_count = candidates
        .iter()
        .filter(|p| !p.is_floating && !p.is_suppressed)
        .count();

    let build_slot = |role: IdeRole, pane: &PaneInfo| -> RoleSlot {
        let hidden = pane.is_suppressed || (pane.is_floating && !are_floating_visible);
        let focused = pane.is_focused && !hidden;
        let (attention, quota, app) = pane_attention_state(pane.id, attn_items);
        let label = match role {
            IdeRole::Ai => detect_ai_label(pane, app.as_deref()),
            IdeRole::Editor => "Editor".to_owned(),
            IdeRole::Shell => "Shell".to_owned(),
        };
        RoleSlot {
            role,
            pane_id: pane.id,
            focused,
            hidden,
            label,
            attention,
            quota,
        }
    };

    RoleStrip {
        ai: ai_pane.map(|p| build_slot(IdeRole::Ai, p)),
        editor: ed_pane.map(|p| build_slot(IdeRole::Editor, p)),
        shell: sh_pane.map(|p| build_slot(IdeRole::Shell, p)),
        visible_tiled_count,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use zellij_tile::prelude::{MuteScope, PaneAttention};

    fn sample_pane(
        id: u32,
        title: &str,
        cmd: Option<&str>,
        focused: bool,
        x: usize,
        y: usize,
    ) -> PaneInfo {
        PaneInfo {
            id,
            is_plugin: false,
            is_focused: focused,
            is_selectable: true,
            title: title.to_owned(),
            terminal_command: cmd.map(str::to_owned),
            pane_x: x,
            pane_y: y,
            ..Default::default()
        }
    }

    #[test]
    fn classifies_standard_3pane_ide_layout() {
        let panes = vec![
            sample_pane(0, "AI", Some("ide.cmd --pane-init ai"), false, 0, 1),
            sample_pane(1, "nvim", Some("ide.cmd --pane-init editor"), true, 60, 1),
            sample_pane(2, "pwsh", Some("ide.cmd --pane-init term"), false, 0, 30),
        ];
        let strip = classify_ide_roles(&panes, false, &[]);
        assert_eq!(strip.ai.as_ref().map(|s| s.pane_id), Some(0));
        assert_eq!(strip.editor.as_ref().map(|s| s.pane_id), Some(1));
        assert_eq!(strip.shell.as_ref().map(|s| s.pane_id), Some(2));
        assert_eq!(strip.focused_role(), Some(IdeRole::Editor));
    }

    #[test]
    fn classifies_2pane_layout_without_shell() {
        let panes = vec![
            sample_pane(4, "claude", Some("ide.cmd --pane-init ai"), true, 0, 1),
            sample_pane(5, "Editor", Some("ide.cmd --pane-init editor"), false, 60, 1),
        ];
        let strip = classify_ide_roles(&panes, false, &[]);
        assert_eq!(strip.ai.as_ref().map(|s| s.label.as_str()), Some("claude"));
        assert!(strip.editor.is_some());
        assert!(strip.shell.is_none());
        assert_eq!(strip.focused_role(), Some(IdeRole::Ai));
    }

    #[test]
    fn maps_unseen_attention_and_ignores_seen_done_or_muted() {
        let panes = vec![
            sample_pane(10, "AI", Some("ide.cmd --pane-init ai"), false, 0, 1),
            sample_pane(11, "Editor", Some("ide.cmd --pane-init editor"), true, 60, 1),
        ];
        let mut ai_attn = PaneAttention {
            status: AttentionStatus::NeedsYou,
            seen: false,
            ..Default::default()
        };
        ai_attn.detail.app = Some("Antigravity".to_owned());
        let items = vec![
            AttentionItem {
                pane_id: PaneId::Terminal(10),
                tab_id: 0,
                tab_name: "ide".to_owned(),
                pane_title: "AI".to_owned(),
                attention: ai_attn,
            },
            AttentionItem {
                pane_id: PaneId::Terminal(11),
                tab_id: 0,
                tab_name: "ide".to_owned(),
                pane_title: "Editor".to_owned(),
                attention: PaneAttention {
                    status: AttentionStatus::Working,
                    muted: Some(MuteScope::Pane),
                    ..Default::default()
                },
            },
        ];

        let strip = classify_ide_roles(&panes, false, &items);
        let ai = strip.ai.unwrap();
        assert_eq!(ai.attention, AttentionStatus::NeedsYou);
        assert!(!ai.quota);
        assert_eq!(ai.label, "agy");
        assert_eq!(strip.editor.unwrap().attention, AttentionStatus::Idle);
        assert_eq!(strip.visible_tiled_count, 2);
    }

    #[test]
    fn distinguishes_quota_auth_blocks_and_suppressed_panes() {
        let mut ed = sample_pane(21, "Editor", Some("ide.cmd --pane-init editor"), false, 60, 1);
        ed.is_suppressed = true;
        let panes = vec![
            sample_pane(20, "claude", Some("ide.cmd --pane-init ai"), true, 0, 1),
            ed,
        ];
        let mut quota_attn = PaneAttention {
            status: AttentionStatus::NeedsYou,
            seen: false,
            ..Default::default()
        };
        quota_attn.detail.kind = Some(BlockedKind::Auth);
        let items = vec![AttentionItem {
            pane_id: PaneId::Terminal(20),
            tab_id: 0,
            tab_name: "ide".to_owned(),
            pane_title: "claude".to_owned(),
            attention: quota_attn,
        }];
        let strip = classify_ide_roles(&panes, false, &items);
        let ai = strip.ai.unwrap();
        assert_eq!(ai.attention, AttentionStatus::NeedsYou);
        assert!(ai.quota);
        assert!(strip.editor.unwrap().hidden);
        assert_eq!(strip.visible_tiled_count, 1);
    }
}
