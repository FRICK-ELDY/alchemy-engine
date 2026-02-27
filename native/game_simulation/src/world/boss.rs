//! Path: native/game_simulation/src/world/boss.rs
//! Summary: ボス状態（BossState）

use crate::entity_params::BossParams;

/// ボス状態（1.4.7: kind_id で参照。0=SlimeKing, 1=BatLord, 2=StoneGolem）
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
    pub fn new(kind_id: u8, x: f32, y: f32) -> Self {
        let params = BossParams::get(kind_id);
        Self {
            kind_id,
            x, y,
            hp: params.max_hp,
            max_hp: params.max_hp,
            phase_timer: params.special_interval,
            invincible: false,
            invincible_timer: 0.0,
            is_dashing: false,
            dash_timer: 0.0,
            dash_vx: 0.0,
            dash_vy: 0.0,
        }
    }
}
