//! Path: native/game_nif/src/nif/save_nif.rs
//! Summary: セーブ・ロード NIF

use super::util::lock_poisoned_err;
use game_physics::world::{BulletWorld, GameWorld};
use game_physics::constants::PARTICLE_RNG_SEED;
use game_physics::item::ItemWorld;
use game_physics::weapon::WeaponSlot;
use rustler::{Atom, NifResult, ResourceArc};

use crate::{ok, EnemyWorld, ParticleWorld};

#[derive(Debug, Clone, rustler::NifMap)]
pub struct WeaponSlotSave {
    pub kind_id: u8,
    pub level:   u32,
}

/// Phase 3-B: exp/level は Elixir 側 GenServer state で管理するため SaveSnapshot から除外。
/// セーブ・ロード時は Elixir 側が exp/level を別途保存・復元する。
#[derive(Debug, Clone, rustler::NifMap)]
pub struct SaveSnapshot {
    pub player_hp:       f32,
    pub player_x:        f32,
    pub player_y:        f32,
    pub player_max_hp:   f32,
    pub elapsed_seconds: f32,
    pub weapon_slots:    Vec<WeaponSlotSave>,
}

#[rustler::nif]
pub fn get_save_snapshot(world: ResourceArc<GameWorld>) -> NifResult<SaveSnapshot> {
    let w = world.0.read().map_err(|_| lock_poisoned_err())?;
    let weapon_slots = w.weapon_slots
        .iter()
        .map(|s| WeaponSlotSave { kind_id: s.kind_id, level: s.level })
        .collect();
    Ok(SaveSnapshot {
        player_hp:       w.player.hp,
        player_x:        w.player.x,
        player_y:        w.player.y,
        player_max_hp:   w.player_max_hp,
        elapsed_seconds: w.elapsed_seconds,
        weapon_slots,
    })
}

#[rustler::nif]
pub fn load_save_snapshot(world: ResourceArc<GameWorld>, snapshot: SaveSnapshot) -> NifResult<Atom> {
    let mut w = world.0.write().map_err(|_| lock_poisoned_err())?;

    w.player.hp               = snapshot.player_hp;
    w.player.x                = snapshot.player_x;
    w.player.y                = snapshot.player_y;
    w.player.input_dx         = 0.0;
    w.player.input_dy         = 0.0;
    w.player.invincible_timer = 0.0;

    w.player_max_hp   = snapshot.player_max_hp;
    w.elapsed_seconds = snapshot.elapsed_seconds;

    let mut slots: Vec<WeaponSlot> = snapshot.weapon_slots
        .into_iter()
        .map(|s| WeaponSlot { kind_id: s.kind_id, level: s.level, cooldown_timer: 0.0 })
        .collect();
    if slots.is_empty() { slots.push(WeaponSlot::new(0)); }
    w.weapon_slots = slots;

    w.enemies   = EnemyWorld::new();
    w.bullets   = BulletWorld::new();
    w.particles = ParticleWorld::new(PARTICLE_RNG_SEED);
    w.items     = ItemWorld::new();
    w.boss      = None;
    w.frame_events.clear();
    w.magnet_timer = 0.0;
    w.score_popups.clear();
    w.collision.dynamic.clear();
    w.score      = 0;
    w.kill_count = 0;

    Ok(ok())
}
