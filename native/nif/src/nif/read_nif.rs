//! Path: native/nif/src/nif/read_nif.rs
//! Summary: 読み取り専用 NIF（get_*、debug_dump_world、is_player_dead）

use super::util::lock_poisoned_err;
use physics::world::GameWorld;
use rustler::{Atom, NifResult, ResourceArc};

use crate::none;

type FrameMetadata = ((f64, f64, u32, f64), (usize, usize, f64), (bool, f64, f64));

/// プレイヤー座標・フレームID・カウント系（player_x, player_y, frame_id, enemy_count, bullet_count）
type RenderEntitiesPlayer = (f64, f64, u32, usize, usize);
/// ワールドレベルのタイマー状態（magnet_timer, invincible_timer）
/// magnet_timer はアイテム効果、invincible_timer はプレイヤー無敵時間を表す。
/// RenderEntitiesPlayer とは別タプルで返すことで意味的な境界を明確にする。
type RenderEntitiesTimers = (f64, f64);
type RenderEntitiesMoving = (
    Vec<(f64, f64, u32)>,
    Vec<(f64, f64, u32)>,
    Vec<(f64, f64, f64, f64, f64, f64, f64)>,
);
type RenderEntitiesWorld = (
    Vec<(f64, f64, u32)>,
    Vec<(f64, f64, f64, u32)>,
    (Atom, f64, f64, f64, u32),
    Vec<(f64, f64, u32, f64)>,
);
type RenderEntities = (
    RenderEntitiesPlayer,
    RenderEntitiesTimers,
    RenderEntitiesMoving,
    RenderEntitiesWorld,
);

#[rustler::nif]
pub fn get_player_pos(world: ResourceArc<GameWorld>) -> NifResult<(f64, f64)> {
    let w = world.0.read().map_err(|_| lock_poisoned_err())?;
    Ok((w.player.x as f64, w.player.y as f64))
}

#[rustler::nif]
pub fn get_player_hp(world: ResourceArc<GameWorld>) -> NifResult<f64> {
    let w = world.0.read().map_err(|_| lock_poisoned_err())?;
    Ok(w.player_hp_injected as f64)
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
    let boss_str = match &w.special_entity_snapshot {
        Some(_) => "special_entity=snapshot".to_string(),
        None => "special_entity=none".to_string(),
    };
    Ok(format!(
        "enemies={} bullets={} player=({:.1},{:.1}) hp={:.0}/{:.0} {}",
        w.enemies.count,
        w.bullets.count,
        w.player.x,
        w.player.y,
        w.player_hp_injected,
        w.player_max_hp,
        boss_str
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
    Ok((
        w.player_hp_injected as f64,
        w.player_max_hp as f64,
        w.score,
        w.elapsed_seconds as f64,
    ))
}

/// フレームメタデータ。boss_hp / boss_max_hp は Elixir SSoT のため Rust 側では持たず、常に 0.0 を返す。
#[rustler::nif]
pub fn get_frame_metadata(world: ResourceArc<GameWorld>) -> NifResult<FrameMetadata> {
    let w = world.0.read().map_err(|_| lock_poisoned_err())?;
    let (boss_alive, boss_hp, boss_max_hp) = match &w.special_entity_snapshot {
        Some(_) => (true, 0.0, 0.0),
        None => (false, 0.0, 0.0),
    };
    Ok((
        (
            w.player_hp_injected as f64,
            w.player_max_hp as f64,
            w.score,
            w.elapsed_seconds as f64,
        ),
        (w.enemies.count, w.bullets.count, w.last_frame_time_ms),
        (boss_alive, boss_hp, boss_max_hp),
    ))
}

#[rustler::nif]
pub fn get_magnet_timer(world: ResourceArc<GameWorld>) -> NifResult<f64> {
    let w = world.0.read().map_err(|_| lock_poisoned_err())?;
    Ok(w.magnet_timer as f64)
}

#[rustler::nif]
pub fn is_player_dead(world: ResourceArc<GameWorld>) -> NifResult<bool> {
    let w = world.0.read().map_err(|_| lock_poisoned_err())?;
    Ok(w.player_hp_injected <= 0.0)
}

#[rustler::nif]
pub fn get_full_game_state(world: ResourceArc<GameWorld>) -> NifResult<(u32, f64, f64, u32)> {
    let w = world.0.read().map_err(|_| lock_poisoned_err())?;
    Ok((
        w.score,
        w.player_hp_injected as f64,
        w.elapsed_seconds as f64,
        w.kill_count,
    ))
}

/// Phase R-2: 描画に必要なエンティティスナップショットを返す汎用 NIF。
///
/// コンテンツ固有の知識を持たず、物理ワールドの描画用データのみを返す。
/// Elixir 側（contents）がこのデータを使って DrawCommand リストを組み立てる。
///
/// 戻り値（ネストタプル）:
/// ```
/// {
///   {player_x, player_y, frame_id, enemy_count, bullet_count},
///   {enemies, bullets, particles},
///   {items, obstacles, boss, score_popups}
/// }
/// ```
/// - `enemy_count` / `bullet_count`: SoA の `count` フィールドから O(1) で取得した生存数。
///   Elixir 側で `length/1` を使わずに UiCanvas を組み立てるために提供する。
/// - enemies:     `[{x, y, kind_id}]`
/// - bullets:     `[{x, y, render_kind}]`
/// - particles:   `[{x, y, r, g, b, alpha, size}]`
/// - items:       `[{x, y, render_kind}]`
/// - obstacles:   `[{x, y, radius, kind}]`
/// - boss:        `{:none, 0, 0, 0, 0}` または `{:alive, x, y, radius, render_kind}`
/// - score_popups:`[{x, y, value, lifetime}]`
#[rustler::nif]
pub fn get_render_entities(world: ResourceArc<GameWorld>) -> NifResult<RenderEntities> {
    let w = world.0.read().map_err(|_| lock_poisoned_err())?;

    let enemies: Vec<(f64, f64, u32)> = (0..w.enemies.len())
        .filter(|&i| w.enemies.alive[i] != 0)
        .map(|i| {
            let kind_id = w
                .params
                .enemies
                .get(w.enemies.kind_ids[i] as usize)
                .map(|ep| ep.render_kind as u32)
                .unwrap_or(1);
            (
                w.enemies.positions_x[i] as f64,
                w.enemies.positions_y[i] as f64,
                kind_id,
            )
        })
        .collect();

    let bullets: Vec<(f64, f64, u32)> = (0..w.bullets.len())
        .filter(|&i| w.bullets.alive[i])
        .map(|i| {
            (
                w.bullets.positions_x[i] as f64,
                w.bullets.positions_y[i] as f64,
                w.bullets.render_kind[i] as u32,
            )
        })
        .collect();

    let particles: Vec<(f64, f64, f64, f64, f64, f64, f64)> = (0..w.particles.len())
        .filter(|&i| w.particles.alive[i])
        .map(|i| {
            let alpha =
                (w.particles.lifetime[i] / w.particles.max_lifetime[i]).clamp(0.0, 1.0) as f64;
            let c = w.particles.color[i];
            (
                w.particles.positions_x[i] as f64,
                w.particles.positions_y[i] as f64,
                c[0] as f64,
                c[1] as f64,
                c[2] as f64,
                alpha,
                w.particles.size[i] as f64,
            )
        })
        .collect();

    let items: Vec<(f64, f64, u32)> = (0..w.items.len())
        .filter(|&i| w.items.alive[i])
        .map(|i| {
            (
                w.items.positions_x[i] as f64,
                w.items.positions_y[i] as f64,
                w.items.kinds[i].render_kind() as u32,
            )
        })
        .collect();

    let obstacles: Vec<(f64, f64, f64, u32)> = w
        .collision
        .obstacles
        .iter()
        .map(|o| (o.x as f64, o.y as f64, o.radius as f64, o.kind as u32))
        .collect();

    // boss は Elixir state から描画するため、常に :none
    let boss = (none(), 0.0, 0.0, 0.0, 0);

    let score_popups: Vec<(f64, f64, u32, f64)> = w
        .score_popups
        .iter()
        .map(|&(x, y, v, lt)| (x as f64, y as f64, v, lt as f64))
        .collect();

    Ok((
        (
            w.player.x as f64,
            w.player.y as f64,
            w.frame_id,
            w.enemies.count,
            w.bullets.count,
        ),
        (
            w.magnet_timer as f64,
            w.player_invincible_timer_injected as f64,
        ),
        (enemies, bullets, particles),
        (items, obstacles, boss, score_popups),
    ))
}

// R-W1: get_weapon_upgrade_descs は削除。レベルアップカード表示は contents の
// WeaponFormulas.weapon_upgrade_descs で Elixir 側完結。
