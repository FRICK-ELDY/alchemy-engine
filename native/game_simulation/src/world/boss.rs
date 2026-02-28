//! Path: native/game_simulation/src/world/boss.rs
//! Summary: ボス状態（BossState）

use crate::entity_params::EntityParamTables;

/// ボス状態（kind_id: u8 で参照）
pub struct BossState {
    pub kind_id:          u8,
    pub x:                f32,
    pub y:                f32,
    pub hp:               f32,
    pub max_hp:           f32,
    pub phase_timer:      f32,
    pub invincible:       bool,
    pub invincible_timer: f32,
    pub is_dashing:       bool,
    pub dash_timer:       f32,
    pub dash_vx:          f32,
    pub dash_vy:          f32,
}

impl BossState {
    /// `params` は `GameWorldInner::params` を渡す。
    pub fn new(kind_id: u8, x: f32, y: f32, params: &EntityParamTables) -> Self {
        let bp = params.get_boss(kind_id);
        Self {
            kind_id,
            x, y,
            hp:               bp.max_hp,
            max_hp:           bp.max_hp,
            phase_timer:      bp.special_interval,
            invincible:       false,
            invincible_timer: 0.0,
            is_dashing:       false,
            dash_timer:       0.0,
            dash_vx:          0.0,
            dash_vy:          0.0,
        }
    }
}
