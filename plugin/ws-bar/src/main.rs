mod palette;
mod render;
mod roles;

use std::cmp::{max, min};
use std::collections::BTreeMap;

use zellij_tile::prelude::actions::Action;
use zellij_tile::prelude::*;

use palette::ThemePalette;
use render::{render_shelf, ClickTarget, HitRegion, RenderContext};
use roles::{classify_ide_roles, current_session_items, IdeRole, RoleStrip};

#[derive(Default)]
struct State {
    mode_info: ModeInfo,
    palette: ThemePalette,
    tabs: Vec<TabInfo>,
    panes: PaneManifest,
    global_attention: Option<GlobalAttention>,
    previous_role: Option<IdeRole>,
    current_role: Option<IdeRole>,
    last_regions: Vec<HitRegion>,
    theme_slug: String,
    initial_root: String,
    workdir: String,
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

fn apply_kv_state_updates(
    payload: Option<&str>,
    args: &BTreeMap<String, String>,
    theme_slug: &mut String,
    initial_root: &mut String,
    workdir: &mut String,
) -> bool {
    let mut changed = false;
    let mut apply_pair = |k: &str, v: &str| {
        let key = k.trim().to_ascii_lowercase();
        let val = v.trim();
        match key.as_str() {
            "theme" if *theme_slug != val => {
                *theme_slug = val.to_owned();
                changed = true;
            }
            "root" if *initial_root != val => {
                *initial_root = val.to_owned();
                changed = true;
            }
            "workdir" if *workdir != val => {
                *workdir = val.to_owned();
                changed = true;
            }
            _ => {}
        }
    };

    for (k, v) in args {
        apply_pair(k, v);
    }
    if let Some(raw) = payload {
        for entry in raw.split(['\n', ';']) {
            if let Some((k, v)) = entry.split_once('=') {
                apply_pair(k, v);
            }
        }
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

    fn activate_role(&self, clicked: IdeRole) {
        let strip = self.compute_roles();
        let Some(slot) = strip.slot(clicked) else {
            return;
        };
        if slot.hidden {
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
                show_pane_with_id(PaneId::Terminal(target_slot.pane_id), false, true);
            } else {
                focus_terminal_pane(target_slot.pane_id, false, false);
            }
        }
    }

    fn ensure_role(&self, role: IdeRole) {
        let strip = self.compute_roles();
        let Some(slot) = strip.slot(role) else {
            return;
        };
        if slot.hidden {
            show_pane_with_id(PaneId::Terminal(slot.pane_id), false, true);
        } else if !slot.focused {
            focus_terminal_pane(slot.pane_id, false, false);
        }
    }

    fn toggle_role(&self, role: IdeRole) {
        let strip = self.compute_roles();
        let Some(slot) = strip.slot(role) else {
            return;
        };
        if slot.hidden {
            show_pane_with_id(PaneId::Terminal(slot.pane_id), false, true);
        } else if strip.visible_tiled_count > 1 {
            if slot.focused {
                let fallback = self.bounce_target(role, &strip);
                if fallback != role {
                    if let Some(fb_slot) = strip.slot(fallback) {
                        focus_terminal_pane(fb_slot.pane_id, false, false);
                    }
                }
            }
            hide_pane_with_id(PaneId::Terminal(slot.pane_id));
        }
    }

    fn run_ide_background_flag(flag: &str) {
        let cmd = CommandToRun::new_with_args("cmd.exe", vec!["/d", "/c", "ide.cmd", flag]);
        let _ = open_command_pane_background(cmd, BTreeMap::new());
    }

    fn launch_session_manager() {
        let initial = actions::initial_panes_from_cli(
            Vec::new(),
            Some("session-manager".to_owned()),
            None,
            std::path::PathBuf::new(),
            false,
            false,
        );
        if let Some(Some(CommandOrPlugin::Plugin(plugin))) = initial.map(|mut v| v.pop()) {
            let action = Action::LaunchOrFocusPlugin {
                plugin,
                should_float: true,
                move_to_focused_tab: true,
                should_open_in_place: false,
                close_replaced_pane: false,
                skip_cache: false,
                tab_id: None,
            };
            run_action(action, BTreeMap::new());
        }
    }

    fn handle_left_click(&self, col: usize) {
        let Some(region) = self.last_regions.iter().find(|r| r.contains(col)) else {
            return;
        };
        match region.target {
            ClickTarget::SessionCard | ClickTarget::SessionManager => {
                Self::launch_session_manager();
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
                Self::run_ide_background_flag("--toggle-monitor");
            }
            ClickTarget::Help => {
                Self::run_ide_background_flag("--toggle-keys");
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
        );
        set_selectable(false);
        request_permission(&[
            PermissionType::ReadApplicationState,
            PermissionType::ChangeApplicationState,
            PermissionType::ReadCliPipes,
            PermissionType::ReadSessionEnvironmentVariables,
            PermissionType::RunActionsAsUser,
            PermissionType::RunCommands,
        ]);
        subscribe(&[
            EventType::ModeUpdate,
            EventType::TabUpdate,
            EventType::PaneUpdate,
            EventType::Mouse,
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
                changed
            }
            Event::PaneUpdate(manifest) => {
                let changed = self.panes != manifest;
                self.panes = manifest;
                let strip = self.compute_roles();
                self.record_focus_transition(&strip);
                changed
            }
            Event::GlobalAttentionUpdate(global) => {
                let changed = self.global_attention.as_ref() != Some(&global);
                self.global_attention = Some(global);
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
            ),
            _ => false,
        }
    }

    fn render(&mut self, _rows: usize, cols: usize) {
        let roles = self.compute_roles();
        let subdir = compute_subdir_label(&self.initial_root, &self.workdir);
        let rendered = render_shelf(&RenderContext {
            cols,
            palette: &self.palette,
            mode_info: &self.mode_info,
            tabs: &self.tabs,
            roles: &roles,
            global_attention: self.global_attention.as_ref(),
            theme_slug: &self.theme_slug,
            subdir_label: subdir.as_deref(),
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
        assert_eq!(
            compute_subdir_label(r"D:\src\repo", r"D:\src\repo"),
            None
        );
        assert_eq!(
            compute_subdir_label(r"D:\src\repo\", "d:/src/repo"),
            None
        );
        assert_eq!(
            compute_subdir_label(r"D:\src\repo", r"D:\src\repo\plugin\ws-bar\"),
            Some("ws-bar".to_owned())
        );
    }

    #[test]
    fn parses_pipe_kv_state_updates_idempotently() {
        let mut theme = String::new();
        let mut root = String::new();
        let mut workdir = String::new();
        let args = BTreeMap::new();
        assert!(apply_kv_state_updates(
            Some("theme=christmas;root=D:\\repo;workdir=D:\\repo\\sub"),
            &args,
            &mut theme,
            &mut root,
            &mut workdir,
        ));
        assert_eq!(theme, "christmas");
        assert_eq!(root, r"D:\repo");
        assert_eq!(workdir, r"D:\repo\sub");
        assert!(!apply_kv_state_updates(
            Some("theme=christmas;root=D:\\repo;workdir=D:\\repo\\sub"),
            &args,
            &mut theme,
            &mut root,
            &mut workdir,
        ));
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
                quota: false,
            }),
            editor: Some(RoleSlot {
                role: IdeRole::Editor,
                pane_id: 1,
                focused: true,
                hidden: false,
                label: "Editor".to_owned(),
                attention: AttentionStatus::Idle,
                quota: false,
            }),
            shell: Some(RoleSlot {
                role: IdeRole::Shell,
                pane_id: 2,
                focused: false,
                hidden: false,
                label: "Shell".to_owned(),
                attention: AttentionStatus::Idle,
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
}
