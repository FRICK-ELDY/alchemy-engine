//! Path: native/game_simulation/src/world/player.rs
//! Summary: プレイヤー状態（座標・入力・HP・無敵タイマー）

/// プレイヤー状態
pub struct PlayerState {
    pub x:                f32,
    pub y:                f32,
    pub input_dx:         f32,
    pub input_dy:         f32,
    pub hp:               f32,
    pub invincible_timer: f32,
}
