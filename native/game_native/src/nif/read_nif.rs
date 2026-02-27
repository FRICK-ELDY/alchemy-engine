//! Path: native/game_native/src/nif/read_nif.rs
//! Summary: 読み取り専用 NIF（get_*、debug_dump_world、is_player_dead）

use super::util::lock_poisoned_err;
use crate::world::GameWorld;
use game_core::entity_params::WeaponParams;
use game_core::util::exp_required_for_next;
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

/// フェーズ1〜4: score/elapsed_seconds/level_up_pending は Elixir 側が権威を持つ。
/// このNIFは後方互換のために残すが、GameEvents では Elixir 側の値を使用する。
#[rustler::nif]
pub fn get_hud_data(world: ResourceArc<GameWorld>) -> NifResult<(f64, f64, u32, f64)> {
    let w = world.0.read().map_err(|_| lock_poisoned_err())?;
    Ok((
        w.player.hp        as f64,
        w.player_max_hp    as f64,
        0,                         // score: Elixir 側が権威
        w.elapsed_seconds  as f64,
    ))
}

/// フェーズ1〜4: 各フィールドの権威は Elixir 側に移行済み。
/// enemy_count/bullet_count/physics_ms は Rust 側の物理状態なので引き続き提供する。
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
        (w.player.hp as f64, w.player_max_hp as f64, 0, w.elapsed_seconds as f64),
        (w.enemies.count, w.bullets.count, w.last_frame_time_ms),
        (w.exp, w.level, false, exp_to_next), // level_up_pending: Elixir 側が権威
        (boss_alive, boss_hp, boss_max_hp),
    ))
}

/// フェーズ3: level_up_pending/exp/level の権威は Elixir 側に移行済み。
/// このNIFは後方互換のために残す。
#[rustler::nif]
pub fn get_level_up_data(world: ResourceArc<GameWorld>) -> NifResult<(u32, u32, bool, u32)> {
    let w = world.0.read().map_err(|_| lock_poisoned_err())?;
    let exp_to_next = exp_required_for_next(w.level).saturating_sub(w.exp);
    Ok((w.exp, w.level, false, exp_to_next)) // level_up_pending: Elixir 側が権威
}

#[rustler::nif]
pub fn get_weapon_levels(world: ResourceArc<GameWorld>) -> NifResult<Vec<(String, u32)>> {
    let w = world.0.read().map_err(|_| lock_poisoned_err())?;
    Ok(w.weapon_slots.iter()
        .map(|s| (WeaponParams::get(s.kind_id).name.to_string(), s.level))
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

/// フェーズ2: 死亡判定は Elixir 側の `player_hp <= 0.0` に移行済み。
/// このNIFは後方互換のために残すが、GameEvents では使用しない。
#[rustler::nif]
pub fn is_player_dead(world: ResourceArc<GameWorld>) -> NifResult<bool> {
    let w = world.0.read().map_err(|_| lock_poisoned_err())?;
    Ok(w.player.hp <= 0.0)
}

/// フェーズ0-2: 移行検証用スナップショット NIF
/// Elixir 側の状態と比較するために Rust 側の現在値を一括取得する
/// フェーズ6 完了後: score/kill_count は Rust 側から削除されたため 0 を返す
#[rustler::nif]
pub fn get_full_game_state(world: ResourceArc<GameWorld>) -> NifResult<(u32, u32, u32, f64, f64, u32)> {
    let w = world.0.read().map_err(|_| lock_poisoned_err())?;
    Ok((
        0,              // score: Elixir 側が権威（フェーズ1で移行済み）
        w.level,        // level: Elixir から注入された値
        w.exp,          // exp: Elixir から注入された値
        w.player.hp as f64,
        w.elapsed_seconds as f64,
        0,              // kill_count: Elixir 側が権威（フェーズ1で移行済み）
    ))
}
