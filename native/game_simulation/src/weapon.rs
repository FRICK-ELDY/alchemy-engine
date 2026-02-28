//! Path: native/game_core/src/weapon.rs
//! Summary: 武器種類・クールダウン・発射ロジックの共通定義

use crate::constants::{BULLET_DAMAGE, WEAPON_COOLDOWN};
use crate::entity_params::{lightning_chain_count, whip_range, WeaponParams, WEAPON_ID_AXE,
                          WEAPON_ID_CROSS, WEAPON_ID_FIREBALL, WEAPON_ID_LIGHTNING,
                          WEAPON_ID_MAGIC_WAND, WEAPON_ID_WHIP};

pub const MAX_WEAPON_LEVEL: u32 = 8;
pub const MAX_WEAPON_SLOTS: usize = 6;

// ─── WeaponKind ───────────────────────────────────────────────
#[derive(Clone, Copy, PartialEq, Debug)]
pub enum WeaponKind {
    MagicWand,
    Axe,
    Cross,
    /// 近距離扇状薙ぎ払い（弾丸を生成しない直接判定）
    Whip,
    /// 敵を貫通する炎弾
    Fireball,
    /// 最近接から連鎖する電撃（最大 chain_count 体）
    Lightning,
}

impl WeaponKind {
    pub fn cooldown(&self) -> f32 {
        match self {
            WeaponKind::MagicWand => WEAPON_COOLDOWN,
            WeaponKind::Axe       => 1.5,
            WeaponKind::Cross     => 2.0,
            WeaponKind::Whip      => 1.0,
            WeaponKind::Fireball  => 1.0,
            WeaponKind::Lightning => 1.0,
        }
    }

    pub fn damage(&self) -> i32 {
        match self {
            WeaponKind::MagicWand => BULLET_DAMAGE,
            WeaponKind::Axe       => 25,
            WeaponKind::Cross     => 15,
            WeaponKind::Whip      => 30,
            WeaponKind::Fireball  => 20,
            WeaponKind::Lightning => 15,
        }
    }

    pub fn name(&self) -> &'static str {
        match self {
            WeaponKind::MagicWand => "magic_wand",
            WeaponKind::Axe       => "axe",
            WeaponKind::Cross     => "cross",
            WeaponKind::Whip      => "whip",
            WeaponKind::Fireball  => "fireball",
            WeaponKind::Lightning => "lightning",
        }
    }

    pub fn bullet_count_table(&self) -> Option<&'static [usize]> {
        match self {
            WeaponKind::MagicWand => Some(&[0, 1, 1, 2, 2, 3, 3, 4, 4]),
            WeaponKind::Cross     => Some(&[0, 4, 4, 4, 8, 8, 8, 8, 8]),
            _                     => None,
        }
    }

    pub fn whip_range(&self, level: u32) -> f32 {
        120.0 + (level as f32 - 1.0) * 20.0
    }

    pub fn lightning_chain_count(&self, level: u32) -> usize {
        2 + level as usize / 2
    }

    pub fn as_u8(&self) -> u8 {
        match self {
            WeaponKind::MagicWand => 0,
            WeaponKind::Axe => 1,
            WeaponKind::Cross => 2,
            WeaponKind::Whip => 3,
            WeaponKind::Fireball => 4,
            WeaponKind::Lightning => 5,
        }
    }
}

// ─── WeaponSlot ───────────────────────────────────────────────
pub struct WeaponSlot {
    pub kind_id:        u8,
    pub level:          u32,
    pub cooldown_timer: f32,
}

impl WeaponSlot {
    pub fn new(kind_id: u8) -> Self {
        Self { kind_id, level: 1, cooldown_timer: 0.0 }
    }

    pub fn effective_cooldown(&self) -> f32 {
        let params = WeaponParams::get(self.kind_id);
        let base = params.cooldown;
        (base * (1.0 - (self.level as f32 - 1.0) * 0.07)).max(base * 0.5)
    }

    pub fn effective_damage(&self) -> i32 {
        let params = WeaponParams::get(self.kind_id);
        let base = params.damage;
        base + (self.level as i32 - 1) * (base / 4).max(1)
    }

    pub fn bullet_count(&self) -> usize {
        let params = WeaponParams::get(self.kind_id);
        params.bullet_count(self.level)
    }
}

// ─── UI 用アップグレード説明（レベルアップカード表示）───────────────

/// 武器名と現在レベルから、アップグレード説明行を返す。HUD のレベルアップカード用。
pub fn weapon_upgrade_desc(name: &str, current_lv: u32) -> Vec<String> {
    let next = current_lv + 1;
    let slot_now = |id: u8, lv: u32| WeaponSlot { kind_id: id, level: lv.max(1), cooldown_timer: 0.0 };
    let dmg = |id: u8, lv: u32| slot_now(id, lv).effective_damage();
    let cd = |id: u8, lv: u32| slot_now(id, lv).effective_cooldown();
    let bullets = |id: u8, lv: u32| WeaponParams::get(id).bullet_count(lv.max(1));

    match name {
        "magic_wand" => {
            let mut lines = vec![
                format!("DMG: {} -> {}", dmg(WEAPON_ID_MAGIC_WAND, current_lv), dmg(WEAPON_ID_MAGIC_WAND, next)),
                format!("CD:  {:.1}s -> {:.1}s", cd(WEAPON_ID_MAGIC_WAND, current_lv), cd(WEAPON_ID_MAGIC_WAND, next)),
            ];
            let bullets_now = bullets(WEAPON_ID_MAGIC_WAND, current_lv);
            let bullets_next = bullets(WEAPON_ID_MAGIC_WAND, next);
            if bullets_next > bullets_now {
                lines.push(format!("Shots: {} -> {} (+)", bullets_now, bullets_next));
            } else {
                lines.push(format!("Shots: {}", bullets_now));
            }
            lines
        }
        "axe" => vec![
            format!("DMG: {} -> {}", dmg(WEAPON_ID_AXE, current_lv), dmg(WEAPON_ID_AXE, next)),
            format!("CD:  {:.1}s -> {:.1}s", cd(WEAPON_ID_AXE, current_lv), cd(WEAPON_ID_AXE, next)),
            "Throws upward".to_string(),
        ],
        "cross" => {
            let dirs_now = if current_lv == 0 || current_lv <= 3 { 4 } else { 8 };
            let dirs_next = if next <= 3 { 4 } else { 8 };
            let mut lines = vec![
                format!("DMG: {} -> {}", dmg(WEAPON_ID_CROSS, current_lv), dmg(WEAPON_ID_CROSS, next)),
                format!("CD:  {:.1}s -> {:.1}s", cd(WEAPON_ID_CROSS, current_lv), cd(WEAPON_ID_CROSS, next)),
            ];
            if dirs_next > dirs_now {
                lines.push(format!("Dirs: {} -> {} (+)", dirs_now, dirs_next));
            } else {
                lines.push(format!("{}-way fire", dirs_now));
            }
            lines
        }
        "whip" => vec![
            format!("DMG: {} -> {}", dmg(WEAPON_ID_WHIP, current_lv), dmg(WEAPON_ID_WHIP, next)),
            format!("CD:  {:.1}s -> {:.1}s", cd(WEAPON_ID_WHIP, current_lv), cd(WEAPON_ID_WHIP, next)),
            format!(
                "Range: {}px -> {}px",
                whip_range(WEAPON_ID_WHIP, current_lv.max(1)) as u32,
                whip_range(WEAPON_ID_WHIP, next) as u32,
            ),
            "Fan sweep (108°)".to_string(),
        ],
        "fireball" => vec![
            format!("DMG: {} -> {}", dmg(WEAPON_ID_FIREBALL, current_lv), dmg(WEAPON_ID_FIREBALL, next)),
            format!("CD:  {:.1}s -> {:.1}s", cd(WEAPON_ID_FIREBALL, current_lv), cd(WEAPON_ID_FIREBALL, next)),
            "Piercing shot".to_string(),
        ],
        "lightning" => vec![
            format!("DMG: {} -> {}", dmg(WEAPON_ID_LIGHTNING, current_lv), dmg(WEAPON_ID_LIGHTNING, next)),
            format!("CD:  {:.1}s -> {:.1}s", cd(WEAPON_ID_LIGHTNING, current_lv), cd(WEAPON_ID_LIGHTNING, next)),
            format!(
                "Chain: {} -> {} targets",
                lightning_chain_count(WEAPON_ID_LIGHTNING, current_lv.max(1)),
                lightning_chain_count(WEAPON_ID_LIGHTNING, next),
            ),
        ],
        _ => vec!["Upgrade weapon".to_string()],
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::entity_params::WEAPON_ID_MAGIC_WAND;

    #[test]
    fn weapon_slot_bullet_count() {
        let slot = WeaponSlot::new(WEAPON_ID_MAGIC_WAND);
        assert_eq!(slot.bullet_count(), 1);
    }

    #[test]
    fn weapon_slot_effective_damage() {
        let mut slot = WeaponSlot::new(WEAPON_ID_MAGIC_WAND);
        slot.level = 2;
        assert_eq!(slot.effective_damage(), 12);
    }
}
