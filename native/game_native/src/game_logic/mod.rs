//! Path: native/game_native/src/game_logic/mod.rs
//! Summary: 物理ステップ・Chase AI・イベント drain

mod chase_ai;
mod events;
mod physics_step;
mod systems;

pub use chase_ai::{
    find_nearest_enemy, find_nearest_enemy_excluding, find_nearest_enemy_spatial,
    find_nearest_enemy_spatial_excluding, update_chase_ai, update_chase_ai_simd,
};
pub(crate) use events::drain_frame_events_inner;
pub(crate) use physics_step::physics_step_inner;
pub(crate) use systems::spawn::get_spawn_positions_around_player;

/// ベンチマーク用の physics_step 実行ヘルパー。
///
/// NIF 境界を通さずに GameWorldInner へ直接ステップを適用する。
pub fn run_physics_step_for_bench(world: &mut crate::world::GameWorldInner, delta_ms: f64) {
    physics_step_inner(world, delta_ms);
}
