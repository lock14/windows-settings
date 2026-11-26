use std::collections::BTreeMap;

use zellij_tile::prelude::{HighlightLayer, HighlightStyle, PaneInfo, RegexHighlight};

use crate::roles::RoleStrip;

pub const URL_PATTERN: &str =
    r#"(?:https?|file)://[^\s<>()\[\]{}"'`]+(?:\([^\s<>()\[\]{}"'`]*\)[^\s<>()\[\]{}"'`]*)*"#;

pub const MD_LINK_PATTERN: &str =
    r#"\[(?:`[^`\r\n]+`|[^\[\]\r\n]+)\]\([^\s()]+(?:\([^\s()]*\)[^\s()]*)*\)"#;

pub const PATH_PATTERN: &str = r#"(?:[A-Za-z]:[\\/]|~[\\/]|\.{1,2}[\\/]|//[A-Za-z0-9_.-]+/|\.?[A-Za-z0-9_.-]+(?:[\\/][A-Za-z0-9_.()-]+)+)(?::[Ll]?[0-9]+(?::[0-9]+)?(?:-[Ll]?[0-9]+)?|#[A-Za-z0-9_.:-]+)?"#;

pub const FILE_PATTERN: &str = r#"(?:(?:\.[A-Za-z0-9_.-]+|\b[A-Za-z0-9_][A-Za-z0-9_.-]*)\.(?:md|markdown|rst|txt|ps1|psm1|psd1|cmd|bat|doskey|json|jsonc|kdl|toml|ya?ml|lua|rs|go|py|js|mjs|cjs|ts|tsx|jsx|c|cc|cpp|cxx|h|hh|hpp|cs|java|kt|kts|scala|swift|zig|rb|php|sh|bash|zsh|fish|vim|scm|theme|tmTheme|gitconfig|conf|cfg|ini|properties|proto|sql|graphql|gql|tf|tfvars|hcl|css|scss|html|xml|svg|diff|patch|lock|lean|ex|exs|erl|hs|ml|mli|bzl|bazel)|\.(?:gitattributes|gitignore|gitconfig|editorconfig)|\b(?:_vimrc|LICENSE|Makefile|Dockerfile|Containerfile|Justfile|BUILD))(?::[Ll]?[0-9]+(?::[0-9]+)?(?:-[Ll]?[0-9]+)?|#[A-Za-z0-9_.:-]+)?\b"#;

fn make_highlight(kind: &str, pattern: &str, layer: HighlightLayer) -> RegexHighlight {
    let mut context = BTreeMap::new();
    context.insert("kind".to_owned(), kind.to_owned());
    RegexHighlight {
        pattern: pattern.to_owned(),
        style: HighlightStyle::None,
        layer,
        context,
        on_hover: true,
        bold: false,
        italic: false,
        underline: true,
        tooltip_text: Some("Open in IDE".to_owned()),
    }
}

pub fn build_ide_link_highlights() -> Vec<RegexHighlight> {
    vec![
        make_highlight("url", URL_PATTERN, HighlightLayer::Tool),
        make_highlight("md_link", MD_LINK_PATTERN, HighlightLayer::Tool),
        make_highlight("path", PATH_PATTERN, HighlightLayer::Hint),
        make_highlight("file", FILE_PATTERN, HighlightLayer::Hint),
    ]
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LinkHighlightSyncPlan {
    pub to_enable: Vec<u32>,
    pub to_clear: Vec<u32>,
}

/// Reconcile which terminal panes should carry `Alt+Click` regex link highlights.
///
/// The `Editor` pane (`nvim`) is deliberately excluded so `<M-LeftMouse>` and `<C-LeftMouse>`
/// pass straight through to Neovim's conceal-aware Tree-sitter AST and LSP definition handler,
/// while `AI`, `Shell`, and auxiliary terminal panes highlight URLs, paths, and doc filenames
/// on hover and dispatch `Event::HighlightClicked` into `ide _internal open-link`.
pub fn plan_pane_link_highlights(
    panes: &[PaneInfo],
    strip: &RoleStrip,
    applied: &mut BTreeMap<u32, bool>,
) -> LinkHighlightSyncPlan {
    let editor_id = strip.editor.as_ref().map(|e| e.pane_id);
    let mut live_ids = Vec::new();
    let mut to_enable = Vec::new();
    let mut to_clear = Vec::new();

    for pane in panes.iter().filter(|p| !p.is_plugin && !p.exited && p.is_selectable) {
        live_ids.push(pane.id);
        let is_editor = editor_id == Some(pane.id)
            || pane.title.trim().eq_ignore_ascii_case("nvim")
            || pane.title.trim().eq_ignore_ascii_case("vim");
        if is_editor {
            if applied.get(&pane.id) == Some(&true) {
                to_clear.push(pane.id);
            }
            applied.insert(pane.id, false);
        } else if applied.get(&pane.id) != Some(&true) {
            to_enable.push(pane.id);
            applied.insert(pane.id, true);
        }
    }

    applied.retain(|id, _| live_ids.contains(id));

    LinkHighlightSyncPlan {
        to_enable,
        to_clear,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::roles::classify_ide_roles;

    fn make_pane(id: u32, title: &str, cmd: Option<&str>) -> PaneInfo {
        PaneInfo {
            id,
            is_plugin: false,
            is_focused: false,
            is_selectable: true,
            title: title.to_owned(),
            terminal_command: cmd.map(str::to_owned),
            ..Default::default()
        }
    }

    #[test]
    fn highlights_ai_and_shell_while_excluding_editor() {
        let mut panes = vec![
            make_pane(0, "AI (agy)", Some("ide.cmd _internal pane-init ai")),
            make_pane(1, "Editor", Some("ide.cmd _internal pane-init editor")),
            make_pane(2, "Shell", Some("ide.cmd _internal pane-init term")),
        ];
        let mut applied = BTreeMap::new();
        let strip = classify_ide_roles(&panes, false, &[]);
        let plan1 = plan_pane_link_highlights(&panes, &strip, &mut applied);
        assert_eq!(plan1.to_enable, vec![0, 2]);
        assert!(plan1.to_clear.is_empty());

        // Idempotent on unchanged subsequent PaneUpdate events
        let plan2 = plan_pane_link_highlights(&panes, &strip, &mut applied);
        assert!(plan2.to_enable.is_empty());
        assert!(plan2.to_clear.is_empty());

        // If a shell pane launches standalone nvim, clear highlights so Neovim owns Alt+Click
        panes[2].title = "nvim".to_owned();
        let plan3 = plan_pane_link_highlights(&panes, &strip, &mut applied);
        assert!(plan3.to_enable.is_empty());
        assert_eq!(plan3.to_clear, vec![2]);
    }

    #[test]
    fn builds_four_hover_only_highlight_layers() {
        let specs = build_ide_link_highlights();
        assert_eq!(specs.len(), 4);
        assert!(specs.iter().all(|h| h.on_hover && h.underline && !h.bold));
        assert_eq!(specs[0].layer, HighlightLayer::Tool);
        assert_eq!(specs[2].layer, HighlightLayer::Hint);
    }
}
