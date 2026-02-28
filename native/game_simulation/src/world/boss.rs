//! Path: native/game_simulation/src/world/boss.rs
//! Summary: ボス状態（BossState）

use crate::entity_params::BossParams;

/// ボス物理状態
///
/// I-2: ボス種別の概念（kind_id）を Rust から除去。
/// ボス種別は Elixir 側 Rule state で管理し、spawn_boss NIF 呼び出し時に
/// 物理パラメータ（radius, render_kind, max_hp 等）のみ Rust に渡す。
/// Phase 3-B: AI ロジックは Elixir 側に移管済み。Rust はボスの物理的な存在のみ管理する。
pub struct BossState {
    pub x:           f32,
    pub y:           f32,
    pub hp:          f32,
    pub max_hp:      f32,
    /// Elixir から set_boss_velocity NIF で注入される速度ベクトル
    pub vx:          f32,
    pub vy:          f32,
    /// Elixir から set_boss_invincible NIF で注入される無敵フラグ
    pub invincible:  bool,
    /// Elixir 側 AI が使用するフェーズタイマー（Rust は更新しない、初期値のみ設定）
    pub phase_timer: f32,
    /// 描画用スプライト種別（spawn_boss NIF で Elixir から注入）
    pub render_kind:      u8,
    /// 当たり判定半径（spawn_boss NIF で Elixir から注入）
    pub radius:           f32,
    /// 接触ダメージ毎秒（spawn_boss NIF で Elixir から注入）
    pub damage_per_sec:   f32,
}

impl BossState {
    /// `bp` は呼び出し元で `params.get_boss(kind_id).clone()` して渡す。
    /// （可変借用と不変借用の競合を避けるため、テーブルではなく値を受け取る）
    pub fn new(x: f32, y: f32, bp: &BossParams) -> Self {
        Self {
            x, y,
            hp:            bp.max_hp,
            max_hp:        bp.max_hp,
            vx:            0.0,
            vy:            0.0,
            invincible:    false,
            phase_timer:   bp.special_interval,
            render_kind:   bp.render_kind,
            radius:        bp.radius,
            damage_per_sec: bp.damage_per_sec,
        }
    }
}
