//! Path: native/game_physics/src/game_logic/mod.rs
//! Summary: 迚ｩ逅・せ繝・ャ繝励・Chase AI繝ｻ繧ｷ繧ｹ繝・Β鄒､

mod chase_ai;
pub mod systems;

pub use chase_ai::{
    find_nearest_enemy, find_nearest_enemy_spatial,
    find_nearest_enemy_spatial_excluding, update_chase_ai, update_chase_ai_simd,
};

pub mod physics_step;

pub use physics_step::physics_step_inner;
