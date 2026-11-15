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
}

register_plugin!(State);

impl State {
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
        match clicked {
            IdeRole::Ai => {
                if strip.editor.is_some() {
                    IdeRole::Editor
                } else if let Some(prev) = self.previous_role.filter(|r| *r != clicked && strip.slot(*r).is_some()) {
                    prev
                } else {
                    clicked
                }
            }
            IdeRole::Editor => {
                if strip.ai.is_some() {
                    IdeRole::Ai
                } else if let Some(prev) = self.previous_role.filter(|r| *r != clicked && strip.slot(*r).is_some()) {
                    prev
                } else {
                    clicked
                }
            }
            IdeRole::Shell => self
                .previous_role
                .filter(|r| *r != IdeRole::Shell && strip.slot(*r).is_some())
                .or_else(|| strip.ai.as_ref().map(|_| IdeRole::Ai))
                .or_else(|| strip.editor.as_ref().map(|_| IdeRole::Editor))
                .unwrap_or(IdeRole::Shell),
        }
    }

    fn activate_role(&self, clicked: IdeRole) {
        let strip = self.compute_roles();
        let Some(slot) = strip.slot(clicked) else {
            return;
        };
        let target_role = if slot.focused && !slot.hidden {
            self.bounce_target(clicked, &strip)
        } else {
            clicked
        };
        if let Some(target_slot) = strip.slot(target_role) {
            focus_terminal_pane(target_slot.pane_id, false, false);
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
            ClickTarget::SessionCard => {
                run_action(Action::ToggleSessionCard, BTreeMap::new());
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
            ClickTarget::SessionManager => {
                Self::launch_session_manager();
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
    fn load(&mut self, _configuration: BTreeMap<String, String>) {
        set_selectable(false);
        request_permission(&[
            PermissionType::ReadApplicationState,
            PermissionType::ChangeApplicationState,
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

    fn render(&mut self, _rows: usize, cols: usize) {
        let roles = self.compute_roles();
        let rendered = render_shelf(&RenderContext {
            cols,
            palette: &self.palette,
            mode_info: &self.mode_info,
            tabs: &self.tabs,
            roles: &roles,
            global_attention: self.global_attention.as_ref(),
        });
        self.last_regions = rendered.regions;
        print!("{}", rendered.ansi);
    }
}
