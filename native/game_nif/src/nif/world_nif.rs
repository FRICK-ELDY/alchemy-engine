//! Path: native/game_nif/src/nif/world_nif.rs
//! Summary: ワールド作成・入力・スポーン・障害物設定 NIF

use super::util::lock_poisoned_err;
use game_simulation::entity_params::{
    BossParams, EnemyParams, EntityParamTables, WeaponParams,
};
use game_simulation::game_logic::systems::spawn::get_spawn_positions_around_player;
use game_simulation::world::{GameWorld, GameWorldInner, PlayerState};
use game_simulation::constants::{CELL_SIZE, MAP_HEIGHT, MAP_WIDTH, PARTICLE_RNG_SEED, PLAYER_SIZE, SCREEN_HEIGHT, SCREEN_WIDTH};
use game_simulation::item::ItemWorld;
use game_simulation::physics::rng::SimpleRng;
use game_simulation::physics::spatial_hash::CollisionWorld;
use game_simulation::util::exp_required_for_next;
use game_simulation::weapon::WeaponSlot;
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
        spatial_query_buf:  Vec::new(),
        last_frame_time_ms: 0.0,
        elapsed_seconds:    0.0,
        player_max_hp:      100.0,
        exp:                0,
        level:              1,
        weapon_slots:       vec![WeaponSlot::new(0)],
        boss:               None,
        frame_events:       Vec::new(),
        weapon_choices:     Vec::new(),
        score_popups:       Vec::new(),
        score:              0,
        kill_count:         0,
        prev_player_x:      SCREEN_WIDTH  / 2.0 - PLAYER_SIZE / 2.0,
        prev_player_y:      SCREEN_HEIGHT / 2.0 - PLAYER_SIZE / 2.0,
        prev_tick_ms:       0,
        curr_tick_ms:       0,
        params:             EntityParamTables::default(),
        map_width:          MAP_WIDTH,
        map_height:         MAP_HEIGHT,
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
    let ep = w.params.get_enemy(kind_id).clone();
    w.enemies.spawn(&positions, kind_id, &ep);
    Ok(ok())
}

#[rustler::nif]
pub fn set_player_hp(world: ResourceArc<GameWorld>, hp: f64) -> NifResult<Atom> {
    let mut w = world.0.write().map_err(|_| lock_poisoned_err())?;
    w.player.hp = hp as f32;
    Ok(ok())
}

#[rustler::nif]
pub fn set_player_level(world: ResourceArc<GameWorld>, level: u32, exp: u32) -> NifResult<Atom> {
    let mut w = world.0.write().map_err(|_| lock_poisoned_err())?;
    w.level = level;
    w.exp = exp;
    Ok(ok())
}

#[rustler::nif]
pub fn set_elapsed_seconds(world: ResourceArc<GameWorld>, elapsed: f64) -> NifResult<Atom> {
    let mut w = world.0.write().map_err(|_| lock_poisoned_err())?;
    w.elapsed_seconds = elapsed as f32;
    Ok(ok())
}

#[rustler::nif]
pub fn set_boss_hp(world: ResourceArc<GameWorld>, hp: f64) -> NifResult<Atom> {
    let mut w = world.0.write().map_err(|_| lock_poisoned_err())?;
    if let Some(boss) = &mut w.boss {
        boss.hp = hp as f32;
    }
    Ok(ok())
}

/// EXP テーブルの SSoT は game_simulation::util::exp_required_for_next。
/// Elixir 側はこの NIF を呼び出すことで、Rust と同一の値を参照する。
#[rustler::nif]
pub fn exp_required_for_next_nif(level: u32) -> u32 {
    exp_required_for_next(level)
}

/// score と kill_count を Elixir 側から注入する（フェーズ1 SSoT 完結）。
/// render_snapshot がこれらの値を HUD に反映するため、毎フレーム呼び出す。
#[rustler::nif]
pub fn set_hud_state(world: ResourceArc<GameWorld>, score: u32, kill_count: u32) -> NifResult<Atom> {
    let mut w = world.0.write().map_err(|_| lock_poisoned_err())?;
    w.score      = score;
    w.kill_count = kill_count;
    Ok(ok())
}

#[rustler::nif]
pub fn set_map_obstacles(world: ResourceArc<GameWorld>, obstacles_term: Term) -> NifResult<Atom> {
    let list: ListIterator = obstacles_term.decode()?;
    let mut obstacles: Vec<(f32, f32, f32, u8)> = Vec::new();
    for item in list {
        let tuple: (f64, f64, f64, u32) = item.decode()?;
        obstacles.push((tuple.0 as f32, tuple.1 as f32, tuple.2 as f32, tuple.3 as u8));
    }
    let mut w = world.0.write().map_err(|_| lock_poisoned_err())?;
    w.collision.rebuild_static(&obstacles);
    Ok(ok())
}

/// Phase 3-A: マップサイズを外部から注入する。
/// WorldBehaviour.map_size/0 から呼び出す。
#[rustler::nif]
pub fn set_world_size(world: ResourceArc<GameWorld>, width: f64, height: f64) -> NifResult<Atom> {
    let mut w = world.0.write().map_err(|_| lock_poisoned_err())?;
    w.map_width  = width as f32;
    w.map_height = height as f32;
    Ok(ok())
}

/// Phase 3-A: エンティティパラメータテーブルを外部から注入する。
///
/// 引数:
/// - `enemies`: `[{max_hp, speed, radius, exp_reward, damage_per_sec, render_kind, passes_obstacles}]`
/// - `weapons`: `[{cooldown, damage, as_u8, name, bullet_table_or_nil}]`
/// - `bosses`:  `[{max_hp, speed, radius, exp_reward, damage_per_sec, render_kind, special_interval, name}]`
#[rustler::nif]
pub fn set_entity_params(
    world: ResourceArc<GameWorld>,
    enemies_term: Term,
    weapons_term: Term,
    bosses_term:  Term,
) -> NifResult<Atom> {
    let enemies = decode_enemy_params(enemies_term)?;
    let weapons = decode_weapon_params(weapons_term)?;
    let bosses  = decode_boss_params(bosses_term)?;
    let mut w = world.0.write().map_err(|_| lock_poisoned_err())?;
    w.params = EntityParamTables { enemies, weapons, bosses };
    Ok(ok())
}

fn decode_enemy_params(term: Term) -> NifResult<Vec<EnemyParams>> {
    let list: ListIterator = term.decode()?;
    let mut result = Vec::new();
    for item in list {
        // {max_hp, speed, radius, exp_reward, damage_per_sec, render_kind, passes_obstacles}
        let t: (f64, f64, f64, u32, f64, u32, bool) = item.decode()?;
        result.push(EnemyParams {
            max_hp:           t.0 as f32,
            speed:            t.1 as f32,
            radius:           t.2 as f32,
            exp_reward:       t.3,
            damage_per_sec:   t.4 as f32,
            render_kind:      t.5 as u8,
            particle_color:   [1.0, 0.5, 0.1, 1.0], // デフォルト色（後で拡張可能）
            passes_obstacles: t.6,
        });
    }
    Ok(result)
}

fn decode_weapon_params(term: Term) -> NifResult<Vec<WeaponParams>> {
    let list: ListIterator = term.decode()?;
    let mut result = Vec::new();
    for item in list {
        // {cooldown, damage, as_u8, name, bullet_table_or_nil}
        // bullet_table は nil または整数リスト
        let t: (f64, i32, u32, String, Term) = item.decode()?;
        let bullet_table: Option<Vec<usize>> = if t.4.is_atom() {
            None
        } else {
            let bt_list: ListIterator = t.4.decode()?;
            Some(bt_list.map(|x| x.decode::<usize>()).collect::<rustler::NifResult<Vec<usize>>>()?)
        };
        result.push(WeaponParams {
            cooldown:     t.0 as f32,
            damage:       t.1,
            as_u8:        t.2 as u8,
            name:         t.3,
            bullet_table,
        });
    }
    Ok(result)
}

fn decode_boss_params(term: Term) -> NifResult<Vec<BossParams>> {
    let list: ListIterator = term.decode()?;
    let mut result = Vec::new();
    for item in list {
        // {max_hp, speed, radius, exp_reward, damage_per_sec, render_kind, special_interval}
        // 名前は省略（HUD 表示名は Elixir 側で管理）
        let t: (f64, f64, f64, u32, f64, u32, f64) = item.decode()?;
        result.push(BossParams {
            max_hp:           t.0 as f32,
            speed:            t.1 as f32,
            radius:           t.2 as f32,
            exp_reward:       t.3,
            damage_per_sec:   t.4 as f32,
            render_kind:      t.5 as u8,
            special_interval: t.6 as f32,
            name:             String::new(),
        });
    }
    Ok(result)
}
