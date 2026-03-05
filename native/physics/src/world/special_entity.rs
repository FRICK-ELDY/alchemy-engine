//! Path: native/physics/src/world/special_entity.rs
//! Summary: 衝突判定用スナップショット（Elixir SSoT 移行後）
//!
//! Rust は永続状態を持たず、毎フレーム Elixir から注入される。
//! HP・速度は Elixir が管理し、Rust は衝突判定とイベント発行のみ行う。

/// 特殊エンティティ（ボス等）の衝突用スナップショット
///
/// Elixir が毎フレーム set_special_entity_snapshot NIF で注入する。
/// 永続状態を持たず、1 tick 分のスナップショットのみ。
#[derive(Clone, Debug, Default)]
pub struct SpecialEntitySnapshot {
    pub x: f32,
    pub y: f32,
    pub radius: f32,
    pub damage_per_sec: f32,
    pub invincible: bool,
}
