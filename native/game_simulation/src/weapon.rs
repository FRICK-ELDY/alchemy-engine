//! Path: native/game_simulation/src/weapon.rs
//! Summary: 武器スロット管理（WeaponSlot）
//!
//! Phase 3-A: WeaponKind enum を除去。
//! パラメータは EntityParamTables 経由で参照する。

use crate::entity_params::{lightning_chain_count, whip_range, WeaponParams};

pub const MAX_WEAPON_LEVEL: u32 = 8;
pub const MAX_WEAPON_SLOTS: usize = 6;

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

    pub fn effective_cooldown(&self, params: &WeaponParams) -> f32 {
        let base = params.cooldown;
        (base * (1.0 - (self.level as f32 - 1.0) * 0.07)).max(base * 0.5)
    }

    pub fn effective_damage(&self, params: &WeaponParams) -> i32 {
        let base = params.damage;
        base + (self.level as i32 - 1) * (base / 4).max(1)
    }

    pub fn bullet_count(&self, params: &WeaponParams) -> usize {
        params.bullet_count(self.level)
    }
}

// ─── UI 用アップグレード説明（レベルアップカード表示）───────────────

/// 武器名と現在レベルから、アップグレード説明行を返す。HUD のレベルアップカード用。
/// `tables` は `GameWorldInner::params` を渡す。デフォルトテーブルを使う場合は
/// `weapon_upgrade_desc_default` を使用する。
pub fn weapon_upgrade_desc(
    name: &str,
    current_lv: u32,
    tables: &crate::entity_params::EntityParamTables,
) -> Vec<String> {
    let next = current_lv + 1;

    let find_id = |n: &str| -> Option<u8> {
        tables.weapons.iter().find(|w| w.name == n).map(|w| w.as_u8)
    };
    let id = match find_id(name) {
        Some(id) => id,
        None => return vec!["Upgrade weapon".to_string()],
    };

    let slot = |lv: u32| WeaponSlot { kind_id: id, level: lv.max(1), cooldown_timer: 0.0 };
    let wp = tables.get_weapon(id);
    let dmg = |lv: u32| slot(lv).effective_damage(tables.get_weapon(id));
    let cd  = |lv: u32| slot(lv).effective_cooldown(tables.get_weapon(id));
    let bullets = |lv: u32| wp.bullet_count(lv.max(1));

    match name {
        "magic_wand" => {
            let mut lines = vec![
                format!("DMG: {} -> {}", dmg(current_lv), dmg(next)),
                format!("CD:  {:.1}s -> {:.1}s", cd(current_lv), cd(next)),
            ];
            let bullets_now  = bullets(current_lv);
            let bullets_next = bullets(next);
            if bullets_next > bullets_now {
                lines.push(format!("Shots: {} -> {} (+)", bullets_now, bullets_next));
            } else {
                lines.push(format!("Shots: {}", bullets_now));
            }
            lines
        }
        "axe" => vec![
            format!("DMG: {} -> {}", dmg(current_lv), dmg(next)),
            format!("CD:  {:.1}s -> {:.1}s", cd(current_lv), cd(next)),
            "Throws upward".to_string(),
        ],
        "cross" => {
            let dirs_now  = if current_lv == 0 || current_lv <= 3 { 4 } else { 8 };
            let dirs_next = if next <= 3 { 4 } else { 8 };
            let mut lines = vec![
                format!("DMG: {} -> {}", dmg(current_lv), dmg(next)),
                format!("CD:  {:.1}s -> {:.1}s", cd(current_lv), cd(next)),
            ];
            if dirs_next > dirs_now {
                lines.push(format!("Dirs: {} -> {} (+)", dirs_now, dirs_next));
            } else {
                lines.push(format!("{}-way fire", dirs_now));
            }
            lines
        }
        "whip" => vec![
            format!("DMG: {} -> {}", dmg(current_lv), dmg(next)),
            format!("CD:  {:.1}s -> {:.1}s", cd(current_lv), cd(next)),
            format!(
                "Range: {}px -> {}px",
                whip_range(id, current_lv.max(1)) as u32,
                whip_range(id, next) as u32,
            ),
            "Fan sweep (108°)".to_string(),
        ],
        "fireball" => vec![
            format!("DMG: {} -> {}", dmg(current_lv), dmg(next)),
            format!("CD:  {:.1}s -> {:.1}s", cd(current_lv), cd(next)),
            "Piercing shot".to_string(),
        ],
        "lightning" => vec![
            format!("DMG: {} -> {}", dmg(current_lv), dmg(next)),
            format!("CD:  {:.1}s -> {:.1}s", cd(current_lv), cd(next)),
            format!(
                "Chain: {} -> {} targets",
                lightning_chain_count(id, current_lv.max(1)),
                lightning_chain_count(id, next),
            ),
        ],
        _ => vec!["Upgrade weapon".to_string()],
    }
}

/// デフォルトパラメータテーブルを使う `weapon_upgrade_desc` のラッパー。
/// `game_render` など `GameWorldInner` を持たないクレートから呼び出す用。
pub fn weapon_upgrade_desc_default(name: &str, current_lv: u32) -> Vec<String> {
    weapon_upgrade_desc(name, current_lv, &crate::entity_params::EntityParamTables::default())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::entity_params::{EntityParamTables, WEAPON_ID_MAGIC_WAND};

    #[test]
    fn weapon_slot_bullet_count() {
        let tables = EntityParamTables::default();
        let slot = WeaponSlot::new(WEAPON_ID_MAGIC_WAND);
        assert_eq!(slot.bullet_count(tables.get_weapon(WEAPON_ID_MAGIC_WAND)), 1);
    }

    #[test]
    fn weapon_slot_effective_damage() {
        let tables = EntityParamTables::default();
        let mut slot = WeaponSlot::new(WEAPON_ID_MAGIC_WAND);
        slot.level = 2;
        assert_eq!(slot.effective_damage(tables.get_weapon(WEAPON_ID_MAGIC_WAND)), 12);
    }
}
