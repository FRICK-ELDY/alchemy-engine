//! Path: native/game_simulation/src/world/boss.rs
//! Summary: ボス状態（BossState）

use crate::entity_params::BossParams;

/// ボス状態（kind_id: u8 で参照）
/// Phase 3-B: AI ロジックは Elixir 側に移管。Rust はボスの物理的な存在（位置・HP・当たり判定）のみ管理する。
pub struct BossState {
    pub kind_id:   u8,
    pub x:         f32,
    pub y:         f32,
    pub hp:        f32,
    pub max_hp:    f32,
    /// Elixir から set_boss_velocity NIF で注入される速度ベクトル
    pub vx:        f32,
    pub vy:        f32,
    /// Elixir から set_boss_invincible NIF で注入される無敵フラグ
    pub invincible: bool,
    /// Elixir 側 AI が使用するフェーズタイマー（Rust は更新しない、初期値のみ設定）
    pub phase_timer: f32,
}

impl BossState {
    /// `bp` は呼び出し元で `params.get_boss(kind_id).clone()` して渡す。
    /// （可変借用と不変借用の競合を避けるため、テーブルではなく値を受け取る）
    pub fn new(kind_id: u8, x: f32, y: f32, bp: &BossParams) -> Self {
        Self {
            kind_id,
            x, y,
            hp:          bp.max_hp,
            max_hp:      bp.max_hp,
            vx:          0.0,
            vy:          0.0,
            invincible:  false,
            phase_timer: bp.special_interval,
        }
    }
}
