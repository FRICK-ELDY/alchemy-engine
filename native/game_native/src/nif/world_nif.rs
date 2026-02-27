//! Path: native/game_native/src/nif/world_nif.rs
//! Summary: ワールド作成・入力・スポーン・障害物設定 NIF

use super::util::lock_poisoned_err;
use crate::game_logic::get_spawn_positions_around_player;
use crate::world::{GameWorld, GameWorldInner, PlayerState};
use game_core::constants::{CELL_SIZE, PARTICLE_RNG_SEED, PLAYER_SIZE, SCREEN_HEIGHT, SCREEN_WIDTH};
use game_core::item::ItemWorld;
use game_core::physics::rng::SimpleRng;
use game_core::physics::spatial_hash::CollisionWorld;
use game_core::weapon::WeaponSlot;
use rustler::types::list::ListIterator;
use rustler::{Atom, NifResult, ResourceArc, Term};
use std::sync::RwLock;

use crate::{ok, BulletWorld, EnemyWorld, ParticleWorld};

#[rustler::nif]
pub fn create_world() -> ResourceArc<GameWorld> {
    ResourceArc::new(GameWorld(RwLock::new(GameWorldInner {
        frame_id:           0,
        player:             PlayerState {
            x:                SCREEN_WIDTH  / 2.0 - PLAYER_SIZE / 2.0,
            y:                SCREEN_HEIGHT / 2.0 - PLAYER_SIZE / 2.0,
            input_dx:         0.0,
            input_dy:         0.0,
            hp:               100.0,
            invincible_timer: 0.0,
        },
        enemies:            EnemyWorld::new(),
        bullets:            BulletWorld::new(),
        particles:          ParticleWorld::new(PARTICLE_RNG_SEED),
        items:              ItemWorld::new(),
        magnet_timer:       0.0,
        rng:                SimpleRng::new(12345),
        collision:          CollisionWorld::new(CELL_SIZE),
        obstacle_query_buf: Vec::new(),
        last_frame_time_ms: 0.0,
        elapsed_seconds:    0.0,
        player_max_hp:      100.0,
        exp:                0,
        level:              1,
        weapon_slots:       vec![WeaponSlot::new(0)], // MagicWand
        boss:               None,
        frame_events:       Vec::new(),
        weapon_choices:     Vec::new(),
        score_popups:       Vec::new(),
        prev_player_x:      SCREEN_WIDTH  / 2.0 - PLAYER_SIZE / 2.0,
        prev_player_y:      SCREEN_HEIGHT / 2.0 - PLAYER_SIZE / 2.0,
        prev_tick_ms:       0,
        curr_tick_ms:       0,
    })))
}

#[rustler::nif]
pub fn set_player_input(world: ResourceArc<GameWorld>, dx: f64, dy: f64) -> NifResult<Atom> {
    let mut w = world.0.write().map_err(|_| lock_poisoned_err())?;
    w.player.input_dx = dx as f32;
    w.player.input_dy = dy as f32;
    Ok(ok())
}

#[rustler::nif]
pub fn spawn_enemies(world: ResourceArc<GameWorld>, kind_id: u8, count: usize) -> NifResult<Atom> {
    let mut w = world.0.write().map_err(|_| lock_poisoned_err())?;
    let positions = get_spawn_positions_around_player(&mut w, count);
    w.enemies.spawn(&positions, kind_id);
    Ok(ok())
}

/// フェーズ2: Elixir 側の権威ある HP を Rust に注入する（毎フレーム呼ばれる）
#[rustler::nif]
pub fn set_player_hp(world: ResourceArc<GameWorld>, hp: f64) -> NifResult<Atom> {
    let mut w = world.0.write().map_err(|_| lock_poisoned_err())?;
    w.player.hp = hp as f32;
    Ok(ok())
}

/// フェーズ3: Elixir 側の権威あるレベル・EXP を Rust に注入する（毎フレーム呼ばれる）
#[rustler::nif]
pub fn set_player_level(world: ResourceArc<GameWorld>, level: u32, exp: u32) -> NifResult<Atom> {
    let mut w = world.0.write().map_err(|_| lock_poisoned_err())?;
    w.level = level;
    w.exp = exp;
    Ok(ok())
}

/// フェーズ3: Elixir 側の権威ある経過時間を Rust に注入する（毎フレーム呼ばれる）
#[rustler::nif]
pub fn set_elapsed_seconds(world: ResourceArc<GameWorld>, elapsed: f64) -> NifResult<Atom> {
    let mut w = world.0.write().map_err(|_| lock_poisoned_err())?;
    w.elapsed_seconds = elapsed as f32;
    Ok(ok())
}

/// フェーズ4: Elixir 側の権威あるボス HP を Rust に注入する（毎フレーム呼ばれる）
#[rustler::nif]
pub fn set_boss_hp(world: ResourceArc<GameWorld>, hp: f64) -> NifResult<Atom> {
    let mut w = world.0.write().map_err(|_| lock_poisoned_err())?;
    if let Some(boss) = &mut w.boss {
        boss.hp = hp as f32;
    }
    Ok(ok())
}

#[rustler::nif]
pub fn set_map_obstacles(world: ResourceArc<GameWorld>, obstacles_term: Term) -> NifResult<Atom> {
    let list: ListIterator = obstacles_term.decode()?;
    let mut obstacles: Vec<(f32, f32, f32, u8)> = Vec::new();
    for item in list {
        let tuple: (f64, f64, f64, u32) = item.decode()?;
        obstacles.push((
            tuple.0 as f32,
            tuple.1 as f32,
            tuple.2 as f32,
            tuple.3 as u8,
        ));
    }
    let mut w = world.0.write().map_err(|_| lock_poisoned_err())?;
    w.collision.rebuild_static(&obstacles);
    Ok(ok())
}
