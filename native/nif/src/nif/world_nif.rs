//! Path: native/nif/src/nif/world_nif.rs
//! Summary: ワールド作成・入力・スポーン・障害物設定 NIF

use super::decode::apply_injection_from_msgpack;
use super::util::{lock_poisoned_err, params_not_loaded_err};
use physics::constants::{
    BULLET_LIFETIME, BULLET_SPEED, CELL_SIZE, MAP_HEIGHT, MAP_WIDTH, PARTICLE_RNG_SEED,
    PLAYER_SIZE, PLAYER_SPEED, SCREEN_HEIGHT, SCREEN_WIDTH,
};
use physics::entity_params::{
    BossParams, EnemyParams, EntityParamTables, FirePattern, WeaponParams,
};
use physics::game_logic::systems::spawn::get_spawn_positions_around_player;
use physics::item::ItemWorld;
use physics::physics::rng::SimpleRng;
use physics::physics::spatial_hash::CollisionWorld;
use physics::weapon::WeaponSlot;
use physics::world::{GameWorld, GameWorldInner, PlayerState};
use rustler::types::list::ListIterator;
use rustler::{Atom, Binary, NifResult, ResourceArc, Term};
use std::sync::RwLock;

use crate::{ok, BulletWorld, EnemyWorld, ParticleWorld};
use physics::entity_params::DEFAULT_PARTICLE_COLOR;

#[rustler::nif]
pub fn create_world() -> ResourceArc<GameWorld> {
    ResourceArc::new(GameWorld(RwLock::new(GameWorldInner {
        frame_id: 0,
        player: PlayerState {
            x: SCREEN_WIDTH / 2.0 - PLAYER_SIZE / 2.0,
            y: SCREEN_HEIGHT / 2.0 - PLAYER_SIZE / 2.0,
            input_dx: 0.0,
            input_dy: 0.0,
        },
        player_hp_injected: 0.0,
        player_invincible_timer_injected: 0.0,
        enemies: EnemyWorld::new(),
        bullets: BulletWorld::new(),
        particles: ParticleWorld::new(PARTICLE_RNG_SEED),
        items: ItemWorld::new(),
        magnet_timer: 0.0,
        rng: SimpleRng::new(12345),
        collision: CollisionWorld::new(CELL_SIZE),
        obstacle_query_buf: Vec::new(),
        spatial_query_buf: Vec::new(),
        last_frame_time_ms: 0.0,
        elapsed_seconds: 0.0,
        player_max_hp: 100.0,
        weapon_slots_input: vec![],
        special_entity_snapshot: None,
        frame_events: Vec::new(),
        score_popups: Vec::new(),
        score: 0,
        kill_count: 0,
        prev_player_x: SCREEN_WIDTH / 2.0 - PLAYER_SIZE / 2.0,
        prev_player_y: SCREEN_HEIGHT / 2.0 - PLAYER_SIZE / 2.0,
        prev_tick_ms: 0,
        curr_tick_ms: 0,
        params: EntityParamTables::default(),
        enemy_damage_this_frame: Vec::new(),
        map_width: MAP_WIDTH,
        map_height: MAP_HEIGHT,
        player_speed: PLAYER_SPEED,
        bullet_speed: BULLET_SPEED,
        bullet_lifetime: BULLET_LIFETIME,
        collect_radius: 60.0,
        magnet_collect_radius: 9999.0,
        magnet_duration: 10.0,
        magnet_speed: 300.0,
        spawn_min_dist: 800.0,
        spawn_max_dist: 1200.0,
        hud_level: 1,
        hud_exp: 0,
        hud_exp_to_next: 10,
        hud_level_up_pending: false,
        hud_weapon_choices: Vec::new(),
        render_buffers: Default::default(),
        render_front: 0,
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
    let ep = w
        .params
        .get_enemy(kind_id)
        .ok_or_else(params_not_loaded_err)?
        .clone();
    let positions = get_spawn_positions_around_player(&mut w, count);
    w.enemies.spawn(&positions, kind_id, &ep);
    Ok(ok())
}

/// Phase 3-B: 指定座標リストに敵をスポーンする NIF。
/// positions: [{x, y}] のリスト
#[rustler::nif]
pub fn spawn_enemies_at(
    world: ResourceArc<GameWorld>,
    kind_id: u8,
    positions_term: Term,
) -> NifResult<Atom> {
    let mut w = world.0.write().map_err(|_| lock_poisoned_err())?;
    let ep = w
        .params
        .get_enemy(kind_id)
        .ok_or_else(params_not_loaded_err)?
        .clone();
    let positions_list: Vec<(f64, f64)> = positions_term.decode()?;
    let positions: Vec<(f32, f32)> = positions_list
        .iter()
        .map(|&(x, y)| (x as f32, y as f32))
        .collect();
    w.enemies.spawn(&positions, kind_id, &ep);
    Ok(ok())
}

/// PlayerState SSoT 移行: contents から毎フレーム呼ぶ。hp と invincible_timer を注入する。
#[rustler::nif]
pub fn set_player_snapshot(
    world: ResourceArc<GameWorld>,
    hp: f64,
    invincible_timer: f64,
) -> NifResult<Atom> {
    let mut w = world.0.write().map_err(|_| lock_poisoned_err())?;
    w.player_hp_injected = hp as f32;
    w.player_invincible_timer_injected = invincible_timer as f32;
    Ok(ok())
}

/// プレイヤー位置を設定（ロード時・テレポート用）。通常は物理演算で更新される。
#[rustler::nif]
pub fn set_player_position(world: ResourceArc<GameWorld>, x: f64, y: f64) -> NifResult<Atom> {
    let mut w = world.0.write().map_err(|_| lock_poisoned_err())?;
    w.player.x = x as f32;
    w.player.y = y as f32;
    Ok(ok())
}

#[rustler::nif]
pub fn set_elapsed_seconds(world: ResourceArc<GameWorld>, elapsed: f64) -> NifResult<Atom> {
    let mut w = world.0.write().map_err(|_| lock_poisoned_err())?;
    w.elapsed_seconds = elapsed as f32;
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

/// Phase 3-A: マップサイズを外部から注入する。
/// WorldBehaviour.map_size/0 から呼び出す。
#[rustler::nif]
pub fn set_world_size(world: ResourceArc<GameWorld>, width: f64, height: f64) -> NifResult<Atom> {
    let mut w = world.0.write().map_err(|_| lock_poisoned_err())?;
    w.map_width = width as f32;
    w.map_height = height as f32;
    Ok(ok())
}

/// R-C1: 物理定数を外部から注入する。
/// params: %{player_speed: 200, bullet_speed: 400, bullet_lifetime: 3.0} 等。指定キーのみ更新。
/// Elixir は atom キーで渡すが、map_get は "player_speed" 等の文字列でルックアップ（Rustler は
/// 文字列からアトムを生成し、Elixir の :player_speed と一致する）。
#[rustler::nif]
pub fn set_world_params(world: ResourceArc<GameWorld>, params: Term) -> NifResult<Atom> {
    let mut w = world.0.write().map_err(|_| lock_poisoned_err())?;
    if let Ok(v) = map_get::<f64>(params, "player_speed") {
        w.player_speed = v as f32;
    }
    if let Ok(v) = map_get::<f64>(params, "bullet_speed") {
        w.bullet_speed = v as f32;
    }
    if let Ok(v) = map_get::<f64>(params, "bullet_lifetime") {
        w.bullet_lifetime = v as f32;
    }
    if let Ok(v) = map_get::<f64>(params, "collect_radius") {
        w.collect_radius = v as f32;
    }
    if let Ok(v) = map_get::<f64>(params, "magnet_collect_radius") {
        w.magnet_collect_radius = v as f32;
    }
    if let Ok(v) = map_get::<f64>(params, "magnet_duration") {
        w.magnet_duration = v as f32;
    }
    if let Ok(v) = map_get::<f64>(params, "magnet_speed") {
        w.magnet_speed = v as f32;
    }
    if let Ok(v) = map_get::<f64>(params, "spawn_min_dist") {
        w.spawn_min_dist = v as f32;
    }
    if let Ok(v) = map_get::<f64>(params, "spawn_max_dist") {
        w.spawn_max_dist = v as f32;
    }
    Ok(ok())
}

/// Phase 3-A: エンティティパラメータテーブルを外部から注入する。
///
/// 引数はいずれもアトムキーのマップのリスト。
/// - `enemies`: `[%{max_hp, speed, radius, damage_per_sec, render_kind, passes_obstacles}]`
/// - `weapons`: `[%{cooldown, damage, as_u8, bullet_table, fire_pattern, range, chain_count}]`
///   ※ `bullet_table` は `nil` または整数リスト、`fire_pattern` は文字列
/// - `bosses`:  `[%{max_hp, speed, radius, damage_per_sec, render_kind, special_interval}]`
#[rustler::nif]
pub fn set_entity_params(
    world: ResourceArc<GameWorld>,
    enemies_term: Term,
    weapons_term: Term,
    bosses_term: Term,
) -> NifResult<Atom> {
    let enemies = decode_enemy_params(enemies_term)?;
    let weapons = decode_weapon_params(weapons_term)?;
    let bosses = decode_boss_params(bosses_term)?;
    let mut w = world.0.write().map_err(|_| lock_poisoned_err())?;
    w.params = EntityParamTables {
        enemies,
        weapons,
        bosses,
    };
    Ok(ok())
}

/// P5-1: 複数注入を 1 回の write lock でまとめて適用するバッチ NIF。
/// injection_map: オプショナルキーを持つ Elixir map。存在するキーのみ適用。
///   - :player_input => {dx, dy}
///   - :player_snapshot => {hp, invincible_timer}
///   - :elapsed_seconds => float
///   - :weapon_slots => [{kind_id, level, cooldown, cooldown_sec, precomputed_damage}, ...]
///   - :enemy_damage_this_frame => [{kind_id, damage}, ...]
///   - :special_entity_snapshot => :none | {:alive, x, y, radius, damage, invincible}
#[rustler::nif]
pub fn set_frame_injection(
    world: ResourceArc<GameWorld>,
    injection_map: Term,
) -> NifResult<Atom> {
    let mut w = world.0.write().map_err(|_| lock_poisoned_err())?;

    if let Ok((dx, dy)) = map_get::<(f64, f64)>(injection_map, "player_input") {
        w.player.input_dx = dx as f32;
        w.player.input_dy = dy as f32;
    }
    if let Ok((hp, inv)) = map_get::<(f64, f64)>(injection_map, "player_snapshot") {
        w.player_hp_injected = hp as f32;
        w.player_invincible_timer_injected = inv as f32;
    }
    if let Ok(elapsed) = map_get::<f64>(injection_map, "elapsed_seconds") {
        w.elapsed_seconds = elapsed as f32;
    }
    if let Ok(list) = map_get::<Vec<(u8, u32, f64, f64, i32)>>(injection_map, "weapon_slots") {
        w.weapon_slots_input = list
            .into_iter()
            .map(|(kind_id, level, cooldown, cooldown_sec, precomputed_damage)| WeaponSlot {
                kind_id,
                level,
                cooldown_timer: cooldown as f32,
                cooldown_sec: cooldown_sec as f32,
                precomputed_damage,
            })
            .collect();
    }
    if let Ok(list) = map_get::<Vec<(u8, f64)>>(injection_map, "enemy_damage_this_frame") {
        let max_id = list.iter().map(|&(id, _)| id as usize).max().unwrap_or(0);
        w.enemy_damage_this_frame.resize(max_id + 1, 0.0);
        w.enemy_damage_this_frame.fill(0.0);
        for (kind_id, damage) in list {
            let i = kind_id as usize;
            if i < w.enemy_damage_this_frame.len() {
                w.enemy_damage_this_frame[i] = damage as f32;
            }
        }
    }
    if let Ok(snapshot_term) = map_get::<Term>(injection_map, "special_entity_snapshot") {
        apply_special_entity_snapshot(&mut w, snapshot_term);
    }

    Ok(ok())
}

/// P5: MessagePack バイナリ形式の set_frame_injection。タプル decode のオーバーヘッドを削減。
#[rustler::nif]
pub fn set_frame_injection_binary(
    world: ResourceArc<GameWorld>,
    binary: Binary,
) -> NifResult<Atom> {
    let mut w = world.0.write().map_err(|_| lock_poisoned_err())?;
    apply_injection_from_msgpack(&mut w, binary.as_slice())
        .map_err(|e| rustler::Error::Term(Box::new(e.to_string())))?;
    Ok(ok())
}

fn apply_special_entity_snapshot(w: &mut GameWorldInner, snapshot: Term) {
    use physics::world::SpecialEntitySnapshot;

    if snapshot.is_atom() {
        w.special_entity_snapshot = None;
        return;
    }
    if let Ok((tag, x, y, radius, damage, inv)) =
        snapshot.decode::<(Atom, f64, f64, f64, f64, bool)>()
    {
        if tag == crate::alive() {
            w.special_entity_snapshot = Some(SpecialEntitySnapshot {
                x: x as f32,
                y: y as f32,
                radius: radius as f32,
                damage_this_frame: damage as f32,
                invincible: inv,
            });
        } else {
            w.special_entity_snapshot = None;
        }
    } else {
        w.special_entity_snapshot = None;
    }
}

/// R-P2: 敵接触の damage_this_frame を注入する NIF。
/// 毎フレーム on_nif_sync で呼ぶ。list: [{kind_id, damage}, ...] — contents が damage_per_sec * dt で事前計算。
/// 使用範囲を毎回クリアしてから書き込む（リストから外れた kind_id の古い値を残さない）。
#[rustler::nif]
pub fn set_enemy_damage_this_frame(
    world: ResourceArc<GameWorld>,
    list: Vec<(u8, f64)>,
) -> NifResult<Atom> {
    let mut w = world.0.write().map_err(|_| lock_poisoned_err())?;
    let max_id = list.iter().map(|&(id, _)| id as usize).max().unwrap_or(0);
    w.enemy_damage_this_frame.resize(max_id + 1, 0.0);
    w.enemy_damage_this_frame.fill(0.0);
    for (kind_id, damage) in list {
        let i = kind_id as usize;
        if i < w.enemy_damage_this_frame.len() {
            w.enemy_damage_this_frame[i] = damage as f32;
        }
    }
    Ok(ok())
}

/// マップから指定キーの値を取得するヘルパー。
/// キーは Elixir アトム（例: `max_hp`）。
fn map_get<'a, T: rustler::Decoder<'a>>(map: Term<'a>, key: &str) -> NifResult<T> {
    let env = map.get_env();
    let key_term = rustler::types::atom::Atom::from_str(env, key)
        .map_err(|_| rustler::Error::Atom("invalid_key"))?;
    map.map_get(key_term.to_term(env))?.decode::<T>()
}

fn decode_enemy_params(term: Term) -> NifResult<Vec<EnemyParams>> {
    let list: ListIterator = term.decode()?;
    list.map(|item| {
        let particle_color = decode_particle_color(item);
        Ok(EnemyParams {
            max_hp: map_get::<f64>(item, "max_hp")? as f32,
            speed: map_get::<f64>(item, "speed")? as f32,
            radius: map_get::<f64>(item, "radius")? as f32,
            damage_per_sec: map_get::<f64>(item, "damage_per_sec")? as f32,
            render_kind: map_get::<i64>(item, "render_kind")? as u8,
            particle_color,
            passes_obstacles: map_get::<bool>(item, "passes_obstacles")?,
        })
    })
    .collect()
}

fn decode_optional_float_vec(item: Term, key: &str) -> Option<Vec<f32>> {
    let term: Term = map_get(item, key).ok()?;
    if term.is_atom() {
        return None;
    }
    let list: ListIterator = term.decode().ok()?;
    list.map(|x| x.decode::<f64>().map(|v| v as f32))
        .collect::<Result<Vec<_>, _>>()
        .ok()
}

fn decode_optional_usize_vec(item: Term, key: &str) -> Option<Vec<usize>> {
    let term: Term = map_get(item, key).ok()?;
    if term.is_atom() {
        return None;
    }
    let list: ListIterator = term.decode().ok()?;
    list.map(|x| x.decode::<usize>())
        .collect::<Result<Vec<_>, _>>()
        .ok()
}

fn decode_particle_color(item: Term) -> [f32; 4] {
    if let Ok(v) = map_get::<Vec<f64>>(item, "particle_color") {
        if v.len() == 4 {
            return [v[0] as f32, v[1] as f32, v[2] as f32, v[3] as f32];
        }
    }
    DEFAULT_PARTICLE_COLOR
}

fn decode_fire_pattern(s: &str) -> FirePattern {
    match s {
        "aimed" => FirePattern::Aimed,
        "fixed_up" => FirePattern::FixedUp,
        "radial" => FirePattern::Radial,
        "whip" => FirePattern::Whip,
        "aura" => FirePattern::Aura,
        "piercing" => FirePattern::Piercing,
        "chain" => FirePattern::Chain,
        _ => FirePattern::Aimed,
    }
}

fn decode_weapon_params(term: Term) -> NifResult<Vec<WeaponParams>> {
    let list: ListIterator = term.decode()?;
    list.map(|item| {
        let bt_term: Term = map_get(item, "bullet_table")?;
        let bullet_table: Option<Vec<usize>> = if bt_term.is_atom() {
            None
        } else {
            let bt_list: ListIterator = bt_term.decode()?;
            Some(
                bt_list
                    .map(|x| x.decode::<usize>())
                    .collect::<rustler::NifResult<Vec<usize>>>()?,
            )
        };
        let pattern_str: String = map_get::<String>(item, "fire_pattern")?;
        let fire_pattern = decode_fire_pattern(&pattern_str);
        let range: f32 = map_get::<f64>(item, "range")
            .or_else(|_| map_get::<i64>(item, "range").map(|v| v as f64))
            .unwrap_or(0.0) as f32;
        let chain_count: u8 = map_get::<u64>(item, "chain_count")
            .or_else(|_| map_get::<i64>(item, "chain_count").map(|v| v as u64))
            .unwrap_or(0) as u8;
        let whip_table = decode_optional_float_vec(item, "whip_range_per_level");
        let aura_table = decode_optional_float_vec(item, "aura_radius_per_level");
        let chain_table = decode_optional_usize_vec(item, "chain_count_per_level");
        Ok(WeaponParams {
            cooldown: map_get::<f64>(item, "cooldown")? as f32,
            damage: map_get::<i64>(item, "damage")? as i32,
            as_u8: map_get::<u64>(item, "as_u8")
                .or_else(|_| map_get::<i64>(item, "as_u8").map(|v| v as u64))
                .unwrap_or(0) as u8,
            bullet_table,
            fire_pattern,
            range,
            chain_count,
            whip_range_per_level: whip_table,
            aura_radius_per_level: aura_table,
            chain_count_per_level: chain_table,
        })
    })
    .collect()
}

fn decode_boss_params(term: Term) -> NifResult<Vec<BossParams>> {
    let list: ListIterator = term.decode()?;
    list.map(|item| {
        Ok(BossParams {
            max_hp: map_get::<f64>(item, "max_hp")? as f32,
            speed: map_get::<f64>(item, "speed")? as f32,
            radius: map_get::<f64>(item, "radius")? as f32,
            damage_per_sec: map_get::<f64>(item, "damage_per_sec")? as f32,
            render_kind: map_get::<i64>(item, "render_kind")? as u8,
            special_interval: map_get::<f64>(item, "special_interval")? as f32,
        })
    })
    .collect()
}
