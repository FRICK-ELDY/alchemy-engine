//! Path: native/game_nif/src/nif/read_nif.rs
//! Summary: 読み取り専用 NIF（get_*、debug_dump_world、is_player_dead）

use super::util::lock_poisoned_err;
use game_simulation::world::GameWorld;
use game_simulation::util::exp_required_for_next;
use rustler::{Atom, NifResult, ResourceArc};

use crate::{alive, none};

#[rustler::nif]
pub fn get_player_pos(world: ResourceArc<GameWorld>) -> NifResult<(f64, f64)> {
    let w = world.0.read().map_err(|_| lock_poisoned_err())?;
    Ok((w.player.x as f64, w.player.y as f64))
}

#[rustler::nif]
pub fn get_player_hp(world: ResourceArc<GameWorld>) -> NifResult<f64> {
    let w = world.0.read().map_err(|_| lock_poisoned_err())?;
    Ok(w.player.hp as f64)
}

#[rustler::nif]
pub fn get_bullet_count(world: ResourceArc<GameWorld>) -> NifResult<usize> {
    let w = world.0.read().map_err(|_| lock_poisoned_err())?;
    Ok(w.bullets.count)
}

#[rustler::nif]
pub fn get_frame_time_ms(world: ResourceArc<GameWorld>) -> NifResult<f64> {
    let w = world.0.read().map_err(|_| lock_poisoned_err())?;
    Ok(w.last_frame_time_ms)
}

#[cfg(debug_assertions)]
#[rustler::nif]
pub fn debug_dump_world(world: ResourceArc<GameWorld>) -> NifResult<String> {
    let w = world.0.read().map_err(|_| lock_poisoned_err())?;
    let boss_str = match &w.boss {
        Some(b) => format!("boss hp={:.0}/{:.0}", b.hp, b.max_hp),
        None => "boss=none".to_string(),
    };
    Ok(format!(
        "enemies={} bullets={} player=({:.1},{:.1}) hp={:.0}/{:.0} {}",
        w.enemies.count, w.bullets.count, w.player.x, w.player.y,
        w.player.hp, w.player_max_hp, boss_str
    ))
}

#[cfg(not(debug_assertions))]
#[rustler::nif]
pub fn debug_dump_world(_world: ResourceArc<GameWorld>) -> NifResult<String> {
    Err(rustler::Error::Atom("debug_build_only"))
}

#[rustler::nif]
pub fn get_enemy_count(world: ResourceArc<GameWorld>) -> NifResult<usize> {
    let w = world.0.read().map_err(|_| lock_poisoned_err())?;
    Ok(w.enemies.count)
}

#[rustler::nif]
pub fn get_hud_data(world: ResourceArc<GameWorld>) -> NifResult<(f64, f64, u32, f64)> {
    let w = world.0.read().map_err(|_| lock_poisoned_err())?;
    Ok((w.player.hp as f64, w.player_max_hp as f64, w.score, w.elapsed_seconds as f64))
}

#[rustler::nif]
pub fn get_frame_metadata(world: ResourceArc<GameWorld>) -> NifResult<(
    (f64, f64, u32, f64),
    (usize, usize, f64),
    (u32, u32, bool, u32),
    (bool, f64, f64),
)> {
    let w = world.0.read().map_err(|_| lock_poisoned_err())?;
    let exp_to_next = exp_required_for_next(w.level).saturating_sub(w.exp);
    let (boss_alive, boss_hp, boss_max_hp) = match &w.boss {
        Some(boss) => (true, boss.hp as f64, boss.max_hp as f64),
        None       => (false, 0.0, 0.0),
    };
    Ok((
        (w.player.hp as f64, w.player_max_hp as f64, w.score, w.elapsed_seconds as f64),
        (w.enemies.count, w.bullets.count, w.last_frame_time_ms),
        (w.exp, w.level, false, exp_to_next),
        (boss_alive, boss_hp, boss_max_hp),
    ))
}

#[rustler::nif]
pub fn get_level_up_data(world: ResourceArc<GameWorld>) -> NifResult<(u32, u32, bool, u32)> {
    let w = world.0.read().map_err(|_| lock_poisoned_err())?;
    let exp_to_next = exp_required_for_next(w.level).saturating_sub(w.exp);
    Ok((w.exp, w.level, false, exp_to_next))
}

#[rustler::nif]
pub fn get_weapon_levels(world: ResourceArc<GameWorld>) -> NifResult<Vec<(String, u32)>> {
    let w = world.0.read().map_err(|_| lock_poisoned_err())?;
    Ok(w.weapon_slots.iter()
        .map(|s| (w.params.get_weapon(s.kind_id).name.clone(), s.level))
        .collect())
}

#[rustler::nif]
pub fn get_magnet_timer(world: ResourceArc<GameWorld>) -> NifResult<f64> {
    let w = world.0.read().map_err(|_| lock_poisoned_err())?;
    Ok(w.magnet_timer as f64)
}

#[rustler::nif]
pub fn get_boss_info(world: ResourceArc<GameWorld>) -> NifResult<(Atom, f64, f64)> {
    let w = world.0.read().map_err(|_| lock_poisoned_err())?;
    Ok(match &w.boss {
        Some(boss) => (alive(), boss.hp as f64, boss.max_hp as f64),
        None       => (none(), 0.0, 0.0),
    })
}

#[rustler::nif]
pub fn is_player_dead(world: ResourceArc<GameWorld>) -> NifResult<bool> {
    let w = world.0.read().map_err(|_| lock_poisoned_err())?;
    Ok(w.player.hp <= 0.0)
}

#[rustler::nif]
pub fn get_full_game_state(world: ResourceArc<GameWorld>) -> NifResult<(u32, u32, u32, f64, f64, u32)> {
    let w = world.0.read().map_err(|_| lock_poisoned_err())?;
    Ok((w.score, w.level, w.exp, w.player.hp as f64, w.elapsed_seconds as f64, w.kill_count))
}
