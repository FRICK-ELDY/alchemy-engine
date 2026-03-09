//! Path: native/physics/src/world/player.rs
//! Summary: プレイヤー状態（座標・入力）
//!
//! PlayerState SSoT 移行後:
//! - x, y: 物理演算の出力。障害物押し出し・衝突の基準点。
//! - input_dx, input_dy: 毎フレーム set_player_input で注入される入力バッファ。
//! - hp, invincible_timer: contents が SSoT。毎フレーム set_player_snapshot で注入され、
//!   GameWorldInner の player_hp_injected / player_invincible_timer_injected に格納される。
pub struct PlayerState {
    pub x: f32,
    pub y: f32,
    pub input_dx: f32,
    pub input_dy: f32,
}
