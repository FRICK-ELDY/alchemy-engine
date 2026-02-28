//! Path: native/game_simulation/src/weapon.rs
//! Summary: 武器スロット管理（WeaponSlot）
//!
//! Phase 3-A: WeaponKind enum を除去。
//! パラメータは EntityParamTables 経由で参照する。

use crate::entity_params::{FirePattern, WeaponParams};

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

/// 武器の `as_u8` ID と現在レベルから、アップグレード説明行を返す。HUD のレベルアップカード用。
/// `tables` は `GameWorldInner::params` を渡す。
pub fn weapon_upgrade_desc(
    weapon_id: u8,
    current_lv: u32,
    tables: &crate::entity_params::EntityParamTables,
) -> Vec<String> {
    if tables.weapons.is_empty() {
        return vec!["Upgrade weapon".to_string()];
    }
    let wp = match tables.weapons.get(weapon_id as usize) {
        Some(w) => w,
        None => return vec!["Upgrade weapon".to_string()],
    };
    let next = current_lv + 1;

    let slot = |lv: u32| WeaponSlot { kind_id: weapon_id, level: lv.max(1), cooldown_timer: 0.0 };
    let dmg = |lv: u32| slot(lv).effective_damage(wp);
    let cd  = |lv: u32| slot(lv).effective_cooldown(wp);
    let bullets = |lv: u32| wp.bullet_count(lv.max(1));

    match wp.fire_pattern {
        FirePattern::Aimed => {
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
        FirePattern::FixedUp => vec![
            format!("DMG: {} -> {}", dmg(current_lv), dmg(next)),
            format!("CD:  {:.1}s -> {:.1}s", cd(current_lv), cd(next)),
            "Throws upward".to_string(),
        ],
        FirePattern::Radial => {
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
        FirePattern::Whip => vec![
            format!("DMG: {} -> {}", dmg(current_lv), dmg(next)),
            format!("CD:  {:.1}s -> {:.1}s", cd(current_lv), cd(next)),
            format!(
                "Range: {}px -> {}px",
                wp.whip_range(current_lv.max(1)) as u32,
                wp.whip_range(next) as u32,
            ),
            "Fan sweep (108°)".to_string(),
        ],
        FirePattern::Piercing => vec![
            format!("DMG: {} -> {}", dmg(current_lv), dmg(next)),
            format!("CD:  {:.1}s -> {:.1}s", cd(current_lv), cd(next)),
            "Piercing shot".to_string(),
        ],
        FirePattern::Chain => vec![
            format!("DMG: {} -> {}", dmg(current_lv), dmg(next)),
            format!("CD:  {:.1}s -> {:.1}s", cd(current_lv), cd(next)),
            format!(
                "Chain: {} -> {} targets",
                wp.chain_count_for_level(current_lv.max(1)),
                wp.chain_count_for_level(next),
            ),
        ],
        FirePattern::Aura => vec![
            format!("DMG: {} -> {}", dmg(current_lv), dmg(next)),
            format!("CD:  {:.1}s -> {:.1}s", cd(current_lv), cd(next)),
            format!(
                "Radius: {}px -> {}px",
                wp.aura_radius(current_lv.max(1)) as u32,
                wp.aura_radius(next) as u32,
            ),
        ],
    }
}


#[cfg(test)]
mod tests {
    use super::*;
    use crate::entity_params::{EntityParamTables, FirePattern, WeaponParams};

    fn make_test_tables() -> EntityParamTables {
        EntityParamTables {
            enemies: vec![],
            weapons: vec![
                WeaponParams {
                    cooldown: 1.0,
                    damage: 10,
                    as_u8: 0,
                    bullet_table: Some(vec![0, 1, 1, 2, 2, 3, 3, 4, 4]),
                    fire_pattern: FirePattern::Aimed,
                    range: 0.0,
                    chain_count: 0,
                },
            ],
            bosses: vec![],
        }
    }

    #[test]
    fn weapon_slot_bullet_count() {
        let tables = make_test_tables();
        let slot = WeaponSlot::new(0);
        assert_eq!(slot.bullet_count(tables.get_weapon(0).expect("weapon 0 should exist")), 1);
    }

    #[test]
    fn weapon_slot_effective_damage() {
        let tables = make_test_tables();
        let mut slot = WeaponSlot::new(0);
        slot.level = 2;
        assert_eq!(slot.effective_damage(tables.get_weapon(0).expect("weapon 0 should exist")), 12);
    }
}
