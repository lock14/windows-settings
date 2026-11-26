mod links;
mod palette;
mod render;
mod roles;

use std::cmp::{max, min};
use std::collections::BTreeMap;
use std::path::PathBuf;

use zellij_tile::prelude::actions::Action;
use zellij_tile::prelude::*;

use links::{build_ide_link_highlights, plan_pane_link_highlights};
use palette::ThemePalette;
use render::{render_shelf, ClickTarget, HitRegion, RenderContext};
use roles::{
    classify_ide_roles, current_session_items, find_role_pane_id_including_exited, IdeRole,
    RoleStrip,
};

#[derive(Default)]
struct State {
    mode_info: ModeInfo,
    palette: ThemePalette,
    tabs: Vec<TabInfo>,
    panes: PaneManifest,
    global_attention: Option<GlobalAttention>,
    previous_role: Option<IdeRole>,
    current_role: Option<IdeRole>,
    last_acked_ai: Option<(u32, AttentionStatus)>,
    highlighted_panes: BTreeMap<u32, bool>,
    alt_click_editor_passthrough: Option<bool>,
    pane_cwds: BTreeMap<u32, String>,
    last_regions: Vec<HitRegion>,
    theme_slug: String,
    initial_root: String,
    workdir: String,
    holiday_icon: String,
}

register_plugin!(State);

fn normalize_path_key(raw: &str) -> String {
    raw.trim()
        .replace('/', "\\")
        .trim_end_matches('\\')
        .to_ascii_lowercase()
}

fn compute_subdir_label(initial_root: &str, workdir: &str) -> Option<String> {
    let root_norm = normalize_path_key(initial_root);
    let work_norm = normalize_path_key(workdir);
    if work_norm.is_empty() || root_norm == work_norm {
        return None;
    }
    workdir
        .trim()
        .trim_end_matches(['\\', '/'])
        .rsplit(['\\', '/'])
        .find(|seg| !seg.is_empty())
        .map(str::to_owned)
}

fn quote_pwsh_single(raw: &str) -> String {
    format!("'{}'", raw.replace('\'', "''"))
}

fn build_open_link_pwsh_script(token: &str, cwd: &str, session: &str, pane_tok: &str) -> String {
    format!(
        "$s = (Get-Command ide.ps1 -CommandType ExternalScript -ErrorAction SilentlyContinue | Select-Object -First 1).Source; if (-not $s) {{ $s = Join-Path $HOME 'windows-settings\\bin\\ide.ps1' }}; if ([System.IO.File]::Exists($s)) {{ & $s _internal open-link -- {} {} {} {} }}",
        quote_pwsh_single(token),
        quote_pwsh_single(cwd),
        quote_pwsh_single(session),
        quote_pwsh_single(pane_tok),
    )
}

fn encode_pwsh_utf16le_base64(script: &str) -> String {
    const TABLE: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let bytes: Vec<u8> = script.encode_utf16().flat_map(u16::to_le_bytes).collect();
    let mut out = String::with_capacity(bytes.len().div_ceil(3) * 4);
    for chunk in bytes.chunks(3) {
        let b0 = chunk[0] as u32;
        let b1 = if chunk.len() > 1 { chunk[1] as u32 } else { 0 };
        let b2 = if chunk.len() > 2 { chunk[2] as u32 } else { 0 };
        let triple = (b0 << 16) | (b1 << 8) | b2;
        out.push(TABLE[((triple >> 18) & 0x3F) as usize] as char);
        out.push(TABLE[((triple >> 12) & 0x3F) as usize] as char);
        if chunk.len() > 1 {
            out.push(TABLE[((triple >> 6) & 0x3F) as usize] as char);
        } else {
            out.push('=');
        }
        if chunk.len() > 2 {
            out.push(TABLE[(triple & 0x3F) as usize] as char);
        } else {
            out.push('=');
        }
    }
    out
}

fn is_editor_pane_focused(panes: &[PaneInfo], strip: &RoleStrip, floating_visible: bool) -> bool {
    let editor_id = strip.editor.as_ref().map(|e| e.pane_id);
    panes
        .iter()
        .filter(|p| {
            !p.is_plugin
                && !p.exited
                && p.is_selectable
                && p.is_focused
                && p.is_floating == floating_visible
        })
        .any(|p| {
            (!p.is_floating && editor_id == Some(p.id))
                || p.title.trim().eq_ignore_ascii_case("nvim")
                || p.title.trim().eq_ignore_ascii_case("vim")
        })
}

fn mousebinds_kdl_for_editor_focus(editor_focused: bool) -> String {
    let alt_left = if editor_focused {
        "Click"
    } else {
        "GroupToggle"
    };
    format!(
        "mouse_click_through false\nmousebinds {{\n    shared {{\n        bind \"Alt Left\" on=\"content\" {{ {alt_left}; }}\n        bind \"Ctrl Left\" on=\"content\" {{ Click; }}\n        bind \"Alt Right\" on=\"content\" {{ PassToApp; }}\n    }}\n}}\n"
    )
}

fn apply_kv_state_updates(
    payload: Option<&str>,
    args: &BTreeMap<String, String>,
    theme_slug: &mut String,
    initial_root: &mut String,
    workdir: &mut String,
    holiday_icon: &mut String,
) -> bool {
    let mut changed = false;
    let mut explicit_holiday_icon = false;
    let mut theme_mutated = false;

    let mut apply_pair = |k: &str, v: &str| {
        let key = k.trim().to_ascii_lowercase();
        let val = v.trim();
        match key.as_str() {
            "theme" => {
                if *theme_slug != val {
                    *theme_slug = val.to_owned();
                    theme_mutated = true;
                    changed = true;
                }
            }
            "root" if *initial_root != val => {
                *initial_root = val.to_owned();
                changed = true;
            }
            "workdir" if *workdir != val => {
                *workdir = val.to_owned();
                changed = true;
            }
            "holiday_icon" | "icon" => {
                explicit_holiday_icon = true;
                if *holiday_icon != val {
                    *holiday_icon = val.to_owned();
                    changed = true;
                }
            }
            _ => {}
        }
    };

    for (k, v) in args {
        apply_pair(k, v);
    }
    if let Some(raw) = payload {
        let trimmed = raw.trim_matches(['\r', '\n']);
        if !trimmed.is_empty() {
            if trimmed.contains('=') {
                for entry in trimmed.split(['\n', ';']) {
                    if let Some((k, v)) = entry.split_once('=') {
                        apply_pair(k, v);
                    }
                }
            } else {
                let parts: Vec<&str> = trimmed.split(';').collect();
                if let Some(t) = parts.first().map(|s| s.trim()).filter(|s| !s.is_empty()) {
                    apply_pair("theme", t);
                }
                if let Some(r) = parts.get(1).map(|s| s.trim()).filter(|s| !s.is_empty()) {
                    apply_pair("root", r);
                }
                if let Some(w) = parts.get(2).map(|s| s.trim()).filter(|s| !s.is_empty()) {
                    apply_pair("workdir", w);
                }
                if let Some(ic) = parts.get(3) {
                    apply_pair("holiday_icon", ic);
                }
            }
        }
    }

    if theme_mutated && !explicit_holiday_icon && !holiday_icon.is_empty() {
        holiday_icon.clear();
        changed = true;
    }
    changed
}

impl State {
    fn sync_session_env(&mut self) {
        let env = get_session_environment_variables();
        if self.theme_slug.is_empty() {
            if let Some(t) = env
                .get("WINDOWS_SETTINGS_THEME")
                .or_else(|| env.get("HOME_SETTINGS_THEME"))
                .map(|s| s.trim())
                .filter(|s| !s.is_empty())
            {
                self.theme_slug = t.to_owned();
            }
        }
        if self.initial_root.is_empty() {
            if let Some(r) = env
                .get("IDE_INITIAL_ROOT")
                .map(|s| s.trim())
                .filter(|s| !s.is_empty())
            {
                self.initial_root = r.to_owned();
            }
        }
        if self.workdir.is_empty() {
            if let Some(w) = env
                .get("IDE_WORKDIR")
                .map(|s| s.trim())
                .filter(|s| !s.is_empty())
            {
                self.workdir = w.to_owned();
            }
        }
        if self.holiday_icon.is_empty() {
            if let Some(ic) = env
                .get("_HS_PROMPT_OS_ICON")
                .map(|s| s.trim())
                .filter(|s| !s.is_empty())
            {
                self.holiday_icon = ic.to_owned();
            }
        }
    }

    fn current_session_name(&self) -> Option<String> {
        self.mode_info
            .session_name
            .as_deref()
            .filter(|s| !s.is_empty())
            .or_else(|| {
                self.global_attention
                    .as_ref()
                    .map(|g| g.current_session.as_str())
                    .filter(|s| !s.is_empty())
            })
            .map(str::to_owned)
    }

    fn active_tab_position(&self) -> usize {
        self.tabs
            .iter()
            .find(|t| t.active)
            .map(|t| t.position)
            .unwrap_or(0)
    }

    fn are_floating_visible(&self) -> bool {
        self.tabs
            .iter()
            .find(|t| t.active)
            .map(|t| t.are_floating_panes_visible)
            .unwrap_or(false)
    }

    fn compute_roles(&self) -> RoleStrip {
        let tab_pos = self.active_tab_position();
        let panes = self
            .panes
            .panes
            .get(&tab_pos)
            .map(Vec::as_slice)
            .unwrap_or(&[]);
        let items = current_session_items(self.global_attention.as_ref());
        classify_ide_roles(panes, self.are_floating_visible(), items)
    }

    fn record_focus_transition(&mut self, strip: &RoleStrip) {
        let next_role = strip.focused_role();
        if let Some(role) = next_role {
            if self.current_role.is_some() && self.current_role != Some(role) {
                self.previous_role = self.current_role;
            }
            self.current_role = Some(role);
        }
    }

    fn maybe_auto_ack_focused_ai(&mut self, strip: &RoleStrip) {
        let Some(ai) = strip.ai.as_ref() else {
            self.last_acked_ai = None;
            return;
        };
        if !ai.attention_unseen {
            self.last_acked_ai = None;
            return;
        }
        if !ai.focused {
            return;
        }
        let key = (ai.pane_id, ai.attention);
        if self.last_acked_ai == Some(key) {
            return;
        }
        let Some(session) = self.current_session_name() else {
            return;
        };
        self.last_acked_ai = Some(key);
        mark_session_pane_seen(&session, PaneId::Terminal(ai.pane_id));
        let cmd =
            CommandToRun::new_with_args("cmd.exe", vec!["/d", "/c", "ide.cmd", "ack", &session]);
        let _ = open_command_pane_background(cmd, BTreeMap::new());
    }

    fn bounce_target(&self, clicked: IdeRole, strip: &RoleStrip) -> IdeRole {
        if let Some(prev) = self
            .previous_role
            .filter(|r| *r != clicked && strip.slot(*r).is_some_and(|s| !s.hidden))
        {
            return prev;
        }
        let candidates = match clicked {
            IdeRole::Ai => [IdeRole::Editor, IdeRole::Shell],
            IdeRole::Editor => [IdeRole::Ai, IdeRole::Shell],
            IdeRole::Shell => [IdeRole::Ai, IdeRole::Editor],
        };
        for cand in candidates {
            if strip.slot(cand).is_some_and(|s| !s.hidden) {
                return cand;
            }
        }
        clicked
    }

    fn focus_tiled_pane(&self, pane_id: u32) {
        if self.are_floating_visible() {
            let _ = hide_floating_panes(None);
        }
        focus_terminal_pane(pane_id, false, false);
    }

    fn activate_role(&self, clicked: IdeRole) {
        let strip = self.compute_roles();
        let Some(slot) = strip.slot(clicked) else {
            return;
        };
        if slot.hidden {
            if self.are_floating_visible() {
                let _ = hide_floating_panes(None);
            }
            show_pane_with_id(PaneId::Terminal(slot.pane_id), false, true);
            return;
        }
        let target_role = if slot.focused {
            self.bounce_target(clicked, &strip)
        } else {
            clicked
        };
        if let Some(target_slot) = strip.slot(target_role) {
            if target_slot.hidden {
                if self.are_floating_visible() {
                    let _ = hide_floating_panes(None);
                }
                show_pane_with_id(PaneId::Terminal(target_slot.pane_id), false, true);
            } else {
                self.focus_tiled_pane(target_slot.pane_id);
            }
        }
    }

    fn ensure_role(&self, role: IdeRole) {
        let strip = self.compute_roles();
        let Some(slot) = strip.slot(role) else {
            return;
        };
        if slot.hidden {
            if self.are_floating_visible() {
                let _ = hide_floating_panes(None);
            }
            show_pane_with_id(PaneId::Terminal(slot.pane_id), false, true);
        } else if !slot.focused {
            self.focus_tiled_pane(slot.pane_id);
        }
    }

    fn toggle_role(&self, role: IdeRole) {
        let strip = self.compute_roles();
        let Some(slot) = strip.slot(role) else {
            return;
        };
        if slot.hidden {
            if self.are_floating_visible() {
                let _ = hide_floating_panes(None);
            }
            show_pane_with_id(PaneId::Terminal(slot.pane_id), false, true);
        } else if strip.visible_tiled_count > 1 {
            if slot.focused {
                let fallback = self.bounce_target(role, &strip);
                if fallback != role {
                    if let Some(fb_slot) = strip.slot(fallback) {
                        self.focus_tiled_pane(fb_slot.pane_id);
                    }
                }
            }
            hide_pane_with_id(PaneId::Terminal(slot.pane_id));
        }
    }

    fn respawn_ai_pane(&self) {
        let tab_pos = self.active_tab_position();
        let panes = self
            .panes
            .panes
            .get(&tab_pos)
            .map(Vec::as_slice)
            .unwrap_or(&[]);
        let strip = self.compute_roles();
        let target_id = strip
            .ai
            .as_ref()
            .map(|s| s.pane_id)
            .or_else(|| find_role_pane_id_including_exited(panes, IdeRole::Ai));
        let Some(pane_id) = target_id else {
            return;
        };
        let mut cmd = CommandToRun::new_with_args("ide.cmd", vec!["_internal", "pane-init", "ai"]);
        let cwd_str = if !self.workdir.is_empty() {
            Some(self.workdir.as_str())
        } else if !self.initial_root.is_empty() {
            Some(self.initial_root.as_str())
        } else {
            None
        };
        if let Some(dir) = cwd_str {
            cmd.cwd = Some(PathBuf::from(dir));
        }
        let _ = open_command_pane_in_place_of_pane_id(
            PaneId::Terminal(pane_id),
            cmd,
            true,
            BTreeMap::new(),
        );
    }

    fn run_ide_toggle_modal(modal: &str) {
        let cmd = CommandToRun::new_with_args(
            "cmd.exe",
            vec!["/d", "/c", "ide.cmd", "_internal", "toggle-modal", modal],
        );
        let _ = open_command_pane_background(cmd, BTreeMap::new());
    }

    fn sync_pane_link_highlights(&mut self, strip: &RoleStrip) {
        let tab_pos = self.active_tab_position();
        let panes = self
            .panes
            .panes
            .get(&tab_pos)
            .map(Vec::as_slice)
            .unwrap_or(&[]);
        let plan = plan_pane_link_highlights(panes, strip, &mut self.highlighted_panes);
        for clear_id in plan.to_clear {
            clear_pane_highlights(PaneId::Terminal(clear_id));
        }
        if !plan.to_enable.is_empty() {
            let highlights = build_ide_link_highlights();
            for enable_id in plan.to_enable {
                if let std::collections::btree_map::Entry::Vacant(slot) =
                    self.pane_cwds.entry(enable_id)
                {
                    if let Ok(cwd) = get_pane_cwd(PaneId::Terminal(enable_id)) {
                        let cwd_str = cwd.to_string_lossy().into_owned();
                        if !cwd_str.is_empty() {
                            slot.insert(cwd_str);
                        }
                    }
                }
                set_pane_regex_highlights(PaneId::Terminal(enable_id), highlights.clone());
            }
        }
        let live_set: Vec<u32> = panes
            .iter()
            .filter(|p| !p.is_plugin && !p.exited)
            .map(|p| p.id)
            .collect();
        self.pane_cwds.retain(|id, _| live_set.contains(id));
    }

    fn sync_alt_click_mousebinds(&mut self, strip: &RoleStrip) {
        let tab_pos = self.active_tab_position();
        let panes = self
            .panes
            .panes
            .get(&tab_pos)
            .map(Vec::as_slice)
            .unwrap_or(&[]);
        let editor_focused = is_editor_pane_focused(panes, strip, self.are_floating_visible());
        if self.alt_click_editor_passthrough != Some(editor_focused) {
            self.alt_click_editor_passthrough = Some(editor_focused);
            reconfigure(mousebinds_kdl_for_editor_focus(editor_focused), false);
        }
    }

    fn dispatch_highlighted_link_click(&self, pane_id: u32, matched_string: &str) {
        let trimmed = matched_string.trim();
        if trimmed.is_empty() {
            return;
        }
        let cwd = self
            .pane_cwds
            .get(&pane_id)
            .map(String::as_str)
            .filter(|s| !s.is_empty())
            .or_else(|| (!self.workdir.is_empty()).then_some(self.workdir.as_str()))
            .or_else(|| (!self.initial_root.is_empty()).then_some(self.initial_root.as_str()))
            .unwrap_or("");
        let sess = self.current_session_name().unwrap_or_default();
        let pane_tok = format!("terminal_{pane_id}");
        let script = build_open_link_pwsh_script(trimmed, cwd, &sess, &pane_tok);
        let encoded = encode_pwsh_utf16le_base64(&script);
        let cmd = CommandToRun::new_with_args(
            "pwsh.exe",
            vec![
                "-NoLogo",
                "-NoProfile",
                "-NonInteractive",
                "-ExecutionPolicy",
                "Bypass",
                "-EncodedCommand",
                &encoded,
            ],
        );
        let _ = open_command_pane_background(cmd, BTreeMap::new());
    }

    fn handle_left_click(&self, col: usize) {
        let Some(region) = self.last_regions.iter().find(|r| r.contains(col)) else {
            return;
        };
        match region.target {
            ClickTarget::SessionCard | ClickTarget::SessionManager => {
                Self::run_ide_toggle_modal("sessions");
            }
            ClickTarget::Role(role) => {
                self.activate_role(role);
            }
            ClickTarget::Zoom => {
                toggle_focus_fullscreen();
            }
            ClickTarget::Tab(pos) => {
                switch_tab_to(pos as u32 + 1);
            }
            ClickTarget::NormalMode => {
                let target_mode = self.mode_info.base_mode.unwrap_or(InputMode::Normal);
                switch_to_input_mode(&target_mode);
            }
            ClickTarget::ToggleSync => {
                run_action(Action::ToggleActiveSyncTab, BTreeMap::new());
            }
            ClickTarget::NextAttention => {
                run_action(Action::GoToNextAttention, BTreeMap::new());
            }
            ClickTarget::Monitor => {
                Self::run_ide_toggle_modal("monitor");
            }
            ClickTarget::Help => {
                Self::run_ide_toggle_modal("keys");
            }
        }
    }

    fn handle_right_click(&self, line: isize, col: usize) {
        let tab_target = self
            .last_regions
            .iter()
            .find(|r| r.contains(col))
            .and_then(|r| r.tab_index);
        let menu_target = match tab_target {
            Some(idx) => ContextMenuTarget::Tab(idx),
            None => ContextMenuTarget::Bar,
        };
        open_context_menu(menu_target, line.max(0) as usize, col);
    }
}

impl ZellijPlugin for State {
    fn load(&mut self, configuration: BTreeMap<String, String>) {
        let _ = apply_kv_state_updates(
            None,
            &configuration,
            &mut self.theme_slug,
            &mut self.initial_root,
            &mut self.workdir,
            &mut self.holiday_icon,
        );
        set_selectable(false);
        request_permission(&[
            PermissionType::ReadApplicationState,
            PermissionType::ChangeApplicationState,
            PermissionType::ReadCliPipes,
            PermissionType::ReadSessionEnvironmentVariables,
            PermissionType::RunActionsAsUser,
            PermissionType::RunCommands,
            PermissionType::Reconfigure,
        ]);
        subscribe(&[
            EventType::ModeUpdate,
            EventType::TabUpdate,
            EventType::PaneUpdate,
            EventType::Mouse,
            EventType::HighlightClicked,
            EventType::CwdChanged,
            EventType::GlobalAttentionUpdate,
            EventType::SessionCountsUpdate,
            EventType::PermissionRequestResult,
        ]);
    }

    fn update(&mut self, event: Event) -> bool {
        match event {
            Event::PermissionRequestResult(PermissionStatus::Granted) => {
                set_selectable(false);
                self.sync_session_env();
                let strip = self.compute_roles();
                self.sync_pane_link_highlights(&strip);
                self.sync_alt_click_mousebinds(&strip);
                true
            }
            Event::ModeUpdate(mode_info) => {
                let new_palette = ThemePalette::from_styling(&mode_info.style.colors);
                let changed = self.mode_info != mode_info || self.palette != new_palette;
                self.palette = new_palette;
                self.mode_info = mode_info;
                changed
            }
            Event::TabUpdate(tabs) => {
                let changed = self.tabs != tabs;
                self.tabs = tabs;
                let strip = self.compute_roles();
                self.sync_pane_link_highlights(&strip);
                self.sync_alt_click_mousebinds(&strip);
                changed
            }
            Event::PaneUpdate(manifest) => {
                let changed = self.panes != manifest;
                self.panes = manifest;
                let strip = self.compute_roles();
                self.record_focus_transition(&strip);
                self.maybe_auto_ack_focused_ai(&strip);
                self.sync_pane_link_highlights(&strip);
                self.sync_alt_click_mousebinds(&strip);
                changed
            }
            Event::CwdChanged(PaneId::Terminal(pane_id), cwd_path, _) => {
                let cwd_str = cwd_path.to_string_lossy().into_owned();
                if !cwd_str.is_empty() {
                    self.pane_cwds.insert(pane_id, cwd_str);
                }
                false
            }
            Event::HighlightClicked {
                pane_id: PaneId::Terminal(pane_id),
                matched_string,
                ..
            } => {
                self.dispatch_highlighted_link_click(pane_id, &matched_string);
                false
            }
            Event::GlobalAttentionUpdate(global) => {
                let changed = self.global_attention.as_ref() != Some(&global);
                self.global_attention = Some(global);
                let strip = self.compute_roles();
                self.maybe_auto_ack_focused_ai(&strip);
                changed
            }
            Event::SessionCountsUpdate(_) => true,
            Event::Mouse(mouse) => {
                match mouse {
                    Mouse::LeftClick(_, col) => {
                        self.handle_left_click(col);
                    }
                    Mouse::RightClick(line, col) => {
                        self.handle_right_click(line, col);
                    }
                    Mouse::ScrollUp(_) if self.tabs.len() > 1 => {
                        let cur = self.active_tab_position() + 1;
                        let next = min(cur + 1, self.tabs.len());
                        switch_tab_to(next as u32);
                    }
                    Mouse::ScrollDown(_) if self.tabs.len() > 1 => {
                        let cur = self.active_tab_position() + 1;
                        let prev = max(cur.saturating_sub(1), 1);
                        switch_tab_to(prev as u32);
                    }
                    _ => {}
                }
                false
            }
            _ => false,
        }
    }

    fn pipe(&mut self, pipe_message: PipeMessage) -> bool {
        if let PipeSource::Cli(input_pipe_id) = &pipe_message.source {
            unblock_cli_pipe_input(input_pipe_id);
        }
        match pipe_message.name.as_str() {
            "ws-ide-role" => {
                let cmd = pipe_message
                    .payload
                    .as_deref()
                    .unwrap_or("")
                    .trim()
                    .to_ascii_lowercase();
                match cmd.as_str() {
                    "focus:ai" => self.activate_role(IdeRole::Ai),
                    "focus:editor" => self.activate_role(IdeRole::Editor),
                    "focus:shell" | "focus:term" => self.activate_role(IdeRole::Shell),
                    "ensure:ai" => self.ensure_role(IdeRole::Ai),
                    "ensure:editor" => self.ensure_role(IdeRole::Editor),
                    "ensure:shell" | "ensure:term" => self.ensure_role(IdeRole::Shell),
                    "toggle:ai" => self.toggle_role(IdeRole::Ai),
                    "toggle:editor" => self.toggle_role(IdeRole::Editor),
                    "toggle:shell" | "toggle:term" => self.toggle_role(IdeRole::Shell),
                    "respawn:ai" => self.respawn_ai_pane(),
                    _ => {}
                }
                false
            }
            "ws-ide-state" => apply_kv_state_updates(
                pipe_message.payload.as_deref(),
                &pipe_message.args,
                &mut self.theme_slug,
                &mut self.initial_root,
                &mut self.workdir,
                &mut self.holiday_icon,
            ),
            _ => false,
        }
    }

    fn render(&mut self, _rows: usize, cols: usize) {
        let roles = self.compute_roles();
        let subdir = compute_subdir_label(&self.initial_root, &self.workdir);
        let holiday_icon = if self.holiday_icon.is_empty() {
            None
        } else {
            Some(self.holiday_icon.as_str())
        };
        let rendered = render_shelf(&RenderContext {
            cols,
            palette: &self.palette,
            mode_info: &self.mode_info,
            tabs: &self.tabs,
            roles: &roles,
            global_attention: self.global_attention.as_ref(),
            theme_slug: &self.theme_slug,
            subdir_label: subdir.as_deref(),
            holiday_icon,
        });
        self.last_regions = rendered.regions;
        print!("{}", rendered.ansi);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use roles::RoleSlot;

    #[test]
    fn computes_subdir_label_only_when_workdir_diverges() {
        assert_eq!(compute_subdir_label(r"D:\src\repo", r"D:\src\repo"), None);
        assert_eq!(compute_subdir_label(r"D:\src\repo\", "d:/src/repo"), None);
        assert_eq!(
            compute_subdir_label(r"D:\src\repo", r"D:\src\repo\plugin\ws-bar\"),
            Some("ws-bar".to_owned())
        );
    }

    #[test]
    fn parses_pipe_kv_and_positional_4th_holiday_icon_updates() {
        let mut theme = String::new();
        let mut root = String::new();
        let mut workdir = String::new();
        let mut holiday_icon = String::new();
        let args = BTreeMap::new();
        assert!(apply_kv_state_updates(
            Some("theme=christmas;root=D:\\repo;workdir=D:\\repo\\sub;holiday_icon=\u{1F384}"),
            &args,
            &mut theme,
            &mut root,
            &mut workdir,
            &mut holiday_icon,
        ));
        assert_eq!(theme, "christmas");
        assert_eq!(root, r"D:\repo");
        assert_eq!(workdir, r"D:\repo\sub");
        assert_eq!(holiday_icon, "\u{1F384}");
        assert!(!apply_kv_state_updates(
            Some("theme=christmas;root=D:\\repo;workdir=D:\\repo\\sub;holiday_icon=\u{1F384}"),
            &args,
            &mut theme,
            &mut root,
            &mut workdir,
            &mut holiday_icon,
        ));

        assert!(apply_kv_state_updates(
            Some("halloween;D:\\other;D:\\other\\pkg;\u{1F383}"),
            &args,
            &mut theme,
            &mut root,
            &mut workdir,
            &mut holiday_icon,
        ));
        assert_eq!(theme, "halloween");
        assert_eq!(root, r"D:\other");
        assert_eq!(workdir, r"D:\other\pkg");
        assert_eq!(holiday_icon, "\u{1F383}");

        assert!(apply_kv_state_updates(
            Some("theme=nord"),
            &args,
            &mut theme,
            &mut root,
            &mut workdir,
            &mut holiday_icon,
        ));
        assert_eq!(theme, "nord");
        assert_eq!(holiday_icon, "");
    }

    #[test]
    fn bounce_target_prefers_previous_visible_role() {
        let mut state = State {
            previous_role: Some(IdeRole::Shell),
            current_role: Some(IdeRole::Editor),
            ..Default::default()
        };
        let mut strip = RoleStrip {
            ai: Some(RoleSlot {
                role: IdeRole::Ai,
                pane_id: 0,
                focused: false,
                hidden: false,
                label: "AI".to_owned(),
                attention: AttentionStatus::Idle,
                attention_unseen: false,
                quota: false,
            }),
            editor: Some(RoleSlot {
                role: IdeRole::Editor,
                pane_id: 1,
                focused: true,
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
        };
        assert_eq!(state.bounce_target(IdeRole::Editor, &strip), IdeRole::Shell);
        if let Some(sh) = strip.shell.as_mut() {
            sh.hidden = true;
        }
        assert_eq!(state.bounce_target(IdeRole::Editor, &strip), IdeRole::Ai);
        state.previous_role = None;
        assert_eq!(state.bounce_target(IdeRole::Editor, &strip), IdeRole::Ai);
    }

    fn decode_base64_utf16le(encoded: &str) -> String {
        fn val(b: u8) -> Option<u32> {
            match b {
                b'A'..=b'Z' => Some((b - b'A') as u32),
                b'a'..=b'z' => Some((b - b'a' + 26) as u32),
                b'0'..=b'9' => Some((b - b'0' + 52) as u32),
                b'+' => Some(62),
                b'/' => Some(63),
                _ => None,
            }
        }
        let mut raw = Vec::new();
        for chunk in encoded.as_bytes().chunks(4) {
            let v0 = val(chunk[0]).unwrap();
            let v1 = val(chunk[1]).unwrap();
            let triple = (v0 << 18)
                | (v1 << 12)
                | (val(chunk[2]).unwrap_or(0) << 6)
                | val(chunk[3]).unwrap_or(0);
            raw.push(((triple >> 16) & 0xFF) as u8);
            if chunk[2] != b'=' {
                raw.push(((triple >> 8) & 0xFF) as u8);
            }
            if chunk[3] != b'=' {
                raw.push((triple & 0xFF) as u8);
            }
        }
        let units: Vec<u16> = raw
            .chunks_exact(2)
            .map(|pair| u16::from_le_bytes([pair[0], pair[1]]))
            .collect();
        String::from_utf16(&units).unwrap()
    }

    #[test]
    fn encodes_open_link_pwsh_script_as_utf16le_base64_with_escaped_quotes() {
        let script = build_open_link_pwsh_script(
            "[setup.ps1:15](setup.ps1#anchor)",
            r"D:\work\O'Reilly & Sons",
            "windows-settings",
            "terminal_0",
        );
        assert!(script.contains("'[setup.ps1:15](setup.ps1#anchor)'"));
        assert!(script.contains(r"'D:\work\O''Reilly & Sons'"));
        assert!(script.contains("'windows-settings' 'terminal_0'"));
        let encoded = encode_pwsh_utf16le_base64(&script);
        assert_eq!(encoded.len() % 4, 0);
        assert_eq!(decode_base64_utf16le(&encoded), script);
    }

    #[test]
    fn switches_alt_left_mousebind_between_group_toggle_and_editor_click() {
        let mut panes = vec![
            PaneInfo {
                id: 0,
                is_focused: true,
                is_selectable: true,
                title: "AI (agy)".to_owned(),
                terminal_command: Some("ide.cmd _internal pane-init ai".to_owned()),
                ..Default::default()
            },
            PaneInfo {
                id: 1,
                is_focused: false,
                is_selectable: true,
                title: "Editor".to_owned(),
                terminal_command: Some("ide.cmd _internal pane-init editor".to_owned()),
                ..Default::default()
            },
        ];
        let strip_ai = classify_ide_roles(&panes, false, &[]);
        assert!(!is_editor_pane_focused(&panes, &strip_ai, false));
        let ai_kdl = mousebinds_kdl_for_editor_focus(false);
        assert!(ai_kdl.contains("mouse_click_through false"));
        assert!(ai_kdl.contains("bind \"Alt Left\" on=\"content\" { GroupToggle; }"));

        panes[0].is_focused = false;
        panes[1].is_focused = true;
        let strip_ed = classify_ide_roles(&panes, false, &[]);
        assert!(is_editor_pane_focused(&panes, &strip_ed, false));
        assert!(!is_editor_pane_focused(&panes, &strip_ed, true));
        assert!(mousebinds_kdl_for_editor_focus(true)
            .contains("bind \"Alt Left\" on=\"content\" { Click; }"));
    }
}
