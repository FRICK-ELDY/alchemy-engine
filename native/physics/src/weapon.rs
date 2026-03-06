//! Path: native/physics/src/weapon.rs
//! Summary: 武器スロット管理（WeaponSlot）
//!
//! Phase 3-A: WeaponKind enum を除去。
//! パラメータは EntityParamTables 経由で参照する。

use crate::entity_params::WeaponParams;

pub const MAX_WEAPON_LEVEL: u32 = 8;
pub const MAX_WEAPON_SLOTS: usize = 6;

// ─── WeaponSlot ───────────────────────────────────────────────

pub struct WeaponSlot {
    pub kind_id: u8,
    pub level: u32,
    pub cooldown_timer: f32,
}

impl WeaponSlot {
    pub fn new(kind_id: u8) -> Self {
        Self {
            kind_id,
            level: 1,
            cooldown_timer: 0.0,
        }
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

// R-W1: weapon_upgrade_desc は contents の WeaponFormulas.weapon_upgrade_descs へ移行済み。
// レベルアップカード表示は Elixir 側で完結する。

#[cfg(test)]
mod tests {
    use super::*;
    use crate::entity_params::{EntityParamTables, FirePattern, WeaponParams};

    fn make_test_tables() -> EntityParamTables {
        EntityParamTables {
            enemies: vec![],
            weapons: vec![WeaponParams {
                cooldown: 1.0,
                damage: 10,
                as_u8: 0,
                bullet_table: Some(vec![0, 1, 1, 2, 2, 3, 3, 4, 4]),
                fire_pattern: FirePattern::Aimed,
                range: 0.0,
                chain_count: 0,
            }],
            bosses: vec![],
        }
    }

    #[test]
    fn weapon_slot_bullet_count() {
        let tables = make_test_tables();
        let slot = WeaponSlot::new(0);
        assert_eq!(
            slot.bullet_count(tables.get_weapon(0).expect("weapon 0 should exist")),
            1
        );
    }

    #[test]
    fn weapon_slot_effective_damage() {
        let tables = make_test_tables();
        let mut slot = WeaponSlot::new(0);
        slot.level = 2;
        assert_eq!(
            slot.effective_damage(tables.get_weapon(0).expect("weapon 0 should exist")),
            12
        );
    }
}
