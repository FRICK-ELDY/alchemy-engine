//! Path: native/nif/src/nif/save_nif.rs
//! Summary: セーブ・ロード NIF

use super::util::lock_poisoned_err;
use physics::constants::PARTICLE_RNG_SEED;
use physics::item::ItemWorld;
use physics::world::{BulletWorld, GameWorld};
use rustler::{Atom, NifResult, ResourceArc};

use crate::{ok, EnemyWorld, ParticleWorld};

/// Phase 3-B: exp/level は Elixir 側 GenServer state で管理するため SaveSnapshot から除外。
/// weapon_slots は weapon-slots SSoT 移行によりコンテンツ層が管理。Rust は関与しない。
#[derive(Debug, Clone, rustler::NifMap)]
pub struct SaveSnapshot {
    pub player_hp: f32,
    pub player_x: f32,
    pub player_y: f32,
    pub player_max_hp: f32,
    pub elapsed_seconds: f32,
}

#[rustler::nif]
pub fn get_save_snapshot(world: ResourceArc<GameWorld>) -> NifResult<SaveSnapshot> {
    let w = world.0.read().map_err(|_| lock_poisoned_err())?;
    Ok(SaveSnapshot {
        player_hp: w.player_hp_injected,
        player_x: w.player.x,
        player_y: w.player.y,
        player_max_hp: w.player_max_hp,
        elapsed_seconds: w.elapsed_seconds,
    })
}

#[rustler::nif]
pub fn load_save_snapshot(
    world: ResourceArc<GameWorld>,
    snapshot: SaveSnapshot,
) -> NifResult<Atom> {
    let mut w = world.0.write().map_err(|_| lock_poisoned_err())?;

    // player_hp, invincible_timer は contents SSoT。build_loaded_scene_state で
    // Playing に渡し、初回 on_nif_sync で set_player_snapshot が注入する。
    w.player_hp_injected = snapshot.player_hp;
    w.player_invincible_timer_injected = 0.0;
    w.player.x = snapshot.player_x;
    w.player.y = snapshot.player_y;
    w.player.input_dx = 0.0;
    w.player.input_dy = 0.0;

    w.player_max_hp = snapshot.player_max_hp;
    w.elapsed_seconds = snapshot.elapsed_seconds;

    w.enemies = EnemyWorld::new();
    w.bullets = BulletWorld::new();
    w.particles = ParticleWorld::new(PARTICLE_RNG_SEED);
    w.items = ItemWorld::new();
    w.special_entity_snapshot = None;
    w.frame_events.clear();
    w.magnet_timer = 0.0;
    w.score_popups.clear();
    w.collision.dynamic.clear();
    w.score = 0;
    w.kill_count = 0;

    Ok(ok())
}
