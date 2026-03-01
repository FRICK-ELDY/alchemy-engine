//! Path: native/game_physics/src/world/player.rs
//! Summary: 繝励Ξ繧､繝､繝ｼ迥ｶ諷具ｼ亥ｺｧ讓吶・蜈･蜉帙・HP繝ｻ辟｡謨ｵ繧ｿ繧､繝槭・・・

/// 繝励Ξ繧､繝､繝ｼ迥ｶ諷・
pub struct PlayerState {
    pub x:                f32,
    pub y:                f32,
    pub input_dx:         f32,
    pub input_dy:         f32,
    pub hp:               f32,
    pub invincible_timer: f32,
}
