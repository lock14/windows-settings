use std::fmt::Write;
use zellij_tile::prelude::{PaletteColor, Styling};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Rgb(pub u8, pub u8, pub u8);

/// 14-slot TrueColor palette mapped from `ModeInfo.style.colors` (`windows-settings.kdl`),
/// defaulting to the canonical Ethan Schoonover Solarized Dark specification.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ThemePalette {
    pub base03: Rgb,
    pub base02: Rgb,
    pub base01: Rgb,
    pub base00: Rgb,
    pub base0: Rgb,
    pub base1: Rgb,
    pub yellow: Rgb,
    pub orange: Rgb,
    pub red: Rgb,
    pub magenta: Rgb,
    pub violet: Rgb,
    pub blue: Rgb,
    pub cyan: Rgb,
    pub green: Rgb,
}

impl Default for ThemePalette {
    fn default() -> Self {
        Self {
            base03: Rgb(0x00, 0x2B, 0x36),
            base02: Rgb(0x07, 0x36, 0x42),
            base01: Rgb(0x58, 0x6E, 0x75),
            base00: Rgb(0x65, 0x7B, 0x83),
            base0: Rgb(0x83, 0x94, 0x96),
            base1: Rgb(0x93, 0xA1, 0xA1),
            yellow: Rgb(0xB5, 0x89, 0x00),
            orange: Rgb(0xCB, 0x4B, 0x16),
            red: Rgb(0xDC, 0x32, 0x2F),
            magenta: Rgb(0xD3, 0x36, 0x82),
            violet: Rgb(0x6C, 0x71, 0xC4),
            blue: Rgb(0x26, 0x8B, 0xD2),
            cyan: Rgb(0x2A, 0xA1, 0x98),
            green: Rgb(0x85, 0x99, 0x00),
        }
    }
}

fn extract_rgb(color: PaletteColor, fallback: Rgb) -> Rgb {
    match color {
        PaletteColor::Rgb((r, g, b)) => Rgb(r, g, b),
        PaletteColor::EightBit(_) => fallback,
    }
}

impl ThemePalette {
    pub fn from_styling(styling: &Styling) -> Self {
        let def = Self::default();
        let mp = &styling.multiplayer_user_colors;
        let frame_base = styling
            .frame_unselected
            .map(|f| f.base)
            .unwrap_or(styling.frame_selected.base);

        Self {
            base03: extract_rgb(styling.table_cell_unselected.background, def.base03),
            base02: extract_rgb(styling.text_unselected.background, def.base02),
            base01: extract_rgb(frame_base, def.base01),
            base00: extract_rgb(mp.player_9, def.base00),
            base0: extract_rgb(styling.text_unselected.base, def.base0),
            base1: extract_rgb(mp.player_10, def.base1),
            magenta: extract_rgb(mp.player_1, def.magenta),
            blue: extract_rgb(mp.player_2, def.blue),
            violet: extract_rgb(mp.player_3, def.violet),
            yellow: extract_rgb(mp.player_4, def.yellow),
            cyan: extract_rgb(mp.player_5, def.cyan),
            orange: extract_rgb(mp.player_6, def.orange),
            red: extract_rgb(mp.player_7, def.red),
            green: extract_rgb(mp.player_8, def.green),
        }
    }

    pub fn write_sgr(&self, out: &mut String, fg: Rgb) {
        let Rgb(fr, fg_g, fb) = fg;
        let Rgb(br, bg_g, bb) = self.base02;
        let _ = write!(out, "\x1b[0;38;2;{fr};{fg_g};{fb};48;2;{br};{bg_g};{bb}m");
    }
}

pub fn holiday_emblem(theme_slug: &str) -> Option<(&'static str, &'static str)> {
    let norm = theme_slug.trim().to_ascii_lowercase().replace('_', "-");
    match norm.as_str() {
        "new-years" => Some(("🥂", "🥂 🎆 New Year's")),
        "valentines" => Some(("💘", "💘 🌹 Valentine's")),
        "st-patricks" => Some(("🍀", "🍀 🪙 St. Patrick's")),
        "easter" => Some(("🐣", "🐣 🌷 Easter")),
        "independence-day" => Some(("🎆", "🎆 🗽 4th of July")),
        "halloween" => Some(("🎃", "🎃 👻 Halloween")),
        "thanksgiving" => Some(("🦃", "🦃 🍂 Thanksgiving")),
        "christmas" => Some(("🎄", "🎄 🎅 Christmas")),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use zellij_tile::prelude::{MultiplayerColors, StyleDeclaration};

    #[test]
    fn solarized_dark_defaults_match_canonical_spec() {
        let p = ThemePalette::default();
        assert_eq!(p.base03, Rgb(0x00, 0x2B, 0x36));
        assert_eq!(p.base02, Rgb(0x07, 0x36, 0x42));
        assert_eq!(p.base0, Rgb(0x83, 0x94, 0x96));
        assert_eq!(p.base1, Rgb(0x93, 0xA1, 0xA1));
        assert_eq!(p.blue, Rgb(0x26, 0x8B, 0xD2));
        assert_eq!(p.cyan, Rgb(0x2A, 0xA1, 0x98));
        assert_eq!(p.green, Rgb(0x85, 0x99, 0x00));
        assert_eq!(p.orange, Rgb(0xCB, 0x4B, 0x16));
    }

    #[test]
    fn extracts_all_14_slots_from_zellij_styling() {
        let mut styling = Styling::default();
        styling.table_cell_unselected = StyleDeclaration {
            background: PaletteColor::Rgb((30, 30, 46)),
            ..Default::default()
        };
        styling.text_unselected = StyleDeclaration {
            base: PaletteColor::Rgb((205, 214, 244)),
            background: PaletteColor::Rgb((49, 50, 68)),
            ..Default::default()
        };
        styling.frame_unselected = Some(StyleDeclaration {
            base: PaletteColor::Rgb((108, 112, 134)),
            ..Default::default()
        });
        styling.multiplayer_user_colors = MultiplayerColors {
            player_1: PaletteColor::Rgb((245, 194, 231)),
            player_2: PaletteColor::Rgb((137, 180, 250)),
            player_3: PaletteColor::Rgb((203, 166, 247)),
            player_4: PaletteColor::Rgb((249, 226, 175)),
            player_5: PaletteColor::Rgb((148, 226, 213)),
            player_6: PaletteColor::Rgb((250, 179, 135)),
            player_7: PaletteColor::Rgb((243, 139, 168)),
            player_8: PaletteColor::Rgb((166, 227, 161)),
            player_9: PaletteColor::Rgb((127, 132, 156)),
            player_10: PaletteColor::Rgb((245, 224, 220)),
        };

        let p = ThemePalette::from_styling(&styling);
        assert_eq!(p.base03, Rgb(30, 30, 46));
        assert_eq!(p.base02, Rgb(49, 50, 68));
        assert_eq!(p.base01, Rgb(108, 112, 134));
        assert_eq!(p.base00, Rgb(127, 132, 156));
        assert_eq!(p.base0, Rgb(205, 214, 244));
        assert_eq!(p.base1, Rgb(245, 224, 220));
        assert_eq!(p.blue, Rgb(137, 180, 250));
        assert_eq!(p.cyan, Rgb(148, 226, 213));
        assert_eq!(p.green, Rgb(166, 227, 161));
    }

    #[test]
    fn maps_all_eight_us_holiday_emblems() {
        assert_eq!(holiday_emblem("halloween"), Some(("🎃", "🎃 👻 Halloween")));
        assert_eq!(holiday_emblem("christmas"), Some(("🎄", "🎄 🎅 Christmas")));
        assert_eq!(holiday_emblem("independence_day"), Some(("🎆", "🎆 🗽 4th of July")));
        assert_eq!(holiday_emblem("solarized-dark"), None);
    }
}
