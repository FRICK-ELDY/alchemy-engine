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
    /// R-W1: Elixir の WeaponFormulas.effective_cooldown で事前計算して注入する値。
    /// クールダウン計算の SSoT を contents に移行。
    pub cooldown_sec: f32,
    /// R-W2: Elixir の WeaponFormulas.effective_damage で事前計算して注入する値。
    /// damage 計算の SSoT を contents に移行。
    pub precomputed_damage: i32,
}

impl WeaponSlot {
    pub fn new(kind_id: u8) -> Self {
        Self {
            kind_id,
            level: 1,
            cooldown_timer: 0.0,
            cooldown_sec: 1.0,
            precomputed_damage: 0,
        }
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
                whip_range_per_level: None,
                aura_radius_per_level: None,
                chain_count_per_level: None,
            }],
            bosses: vec![],
        }
    }

    #[test]
    fn weapon_slot_bullet_count() {
        let tables = make_test_tables();
        let mut slot = WeaponSlot::new(0);
        slot.precomputed_damage = 12; // R-W2: Elixir から注入する想定
        assert_eq!(
            slot.bullet_count(tables.get_weapon(0).expect("weapon 0 should exist")),
            1
        );
    }
}
