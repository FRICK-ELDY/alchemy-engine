//! Path: native/game_nif/src/nif/action_nif.rs
//! Summary: アクション NIF（set_weapon_slots, spawn_boss, spawn_elite_enemy, spawn_item 等）

use super::util::{lock_poisoned_err, params_not_loaded_err};
use game_physics::constants::{PLAYER_RADIUS, POPUP_LIFETIME, POPUP_Y_OFFSET};
use game_physics::game_logic::systems::spawn::get_spawn_positions_around_player;
use game_physics::item::ItemKind;
use game_physics::weapon::WeaponSlot;
use game_physics::world::{BossState, FrameEvent, GameWorld};
use rustler::{Atom, NifResult, ResourceArc};

use crate::ok;

/// I-2: 武器スロットを Elixir 側から毎フレーム注入する NIF。
/// Elixir 側 Rule state が武器の SSoT となり、毎フレームこの NIF で Rust に反映する。
/// slots: [{kind_id: u8, level: u32}] のリスト
#[rustler::nif]
pub fn set_weapon_slots(world: ResourceArc<GameWorld>, slots: Vec<(u8, u32)>) -> NifResult<Atom> {
    let mut w = world.0.write().map_err(|_| lock_poisoned_err())?;
    let new_slots: Vec<WeaponSlot> = slots
        .into_iter()
        .map(|(kind_id, level)| {
            let existing_timer = w
                .weapon_slots
                .iter()
                .find(|s| s.kind_id == kind_id)
                .map(|s| s.cooldown_timer)
                .unwrap_or(0.0);
            WeaponSlot {
                kind_id,
                level,
                cooldown_timer: existing_timer,
            }
        })
        .collect();
    w.weapon_slots = new_slots;
    Ok(ok())
}

/// I-2: ボスの物理エントリを生成する NIF。
/// ボス種別の概念は Elixir 側 Rule state で管理する。
/// kind_id は FrameEvent::SpecialEntitySpawned でのみ使用し、Rust 内部では保持しない。
#[rustler::nif]
pub fn spawn_boss(world: ResourceArc<GameWorld>, kind_id: u8) -> NifResult<Atom> {
    let mut w = world.0.write().map_err(|_| lock_poisoned_err())?;
    if w.boss.is_some() {
        return Ok(ok());
    }
    if let Some(bp) = w.params.get_boss(kind_id).cloned() {
        let px = w.player.x + PLAYER_RADIUS;
        let py = w.player.y + PLAYER_RADIUS;
        let bx = (px + 600.0).min(w.map_width - bp.radius);
        let by = py.clamp(bp.radius, w.map_height - bp.radius);
        w.boss = Some(BossState::new(bx, by, &bp));
        w.frame_events.push(FrameEvent::SpecialEntitySpawned {
            entity_kind: kind_id,
        });
    }
    Ok(ok())
}

/// Phase 3-B: ボスの速度ベクトルを Elixir 側 AI から注入する NIF。
#[rustler::nif]
pub fn set_boss_velocity(world: ResourceArc<GameWorld>, vx: f64, vy: f64) -> NifResult<Atom> {
    let mut w = world.0.write().map_err(|_| lock_poisoned_err())?;
    if let Some(ref mut boss) = w.boss {
        boss.vx = vx as f32;
        boss.vy = vy as f32;
    }
    Ok(ok())
}

/// Phase 3-B: ボスの無敵状態を Elixir 側 AI から設定する NIF。
#[rustler::nif]
pub fn set_boss_invincible(world: ResourceArc<GameWorld>, invincible: bool) -> NifResult<Atom> {
    let mut w = world.0.write().map_err(|_| lock_poisoned_err())?;
    if let Some(ref mut boss) = w.boss {
        boss.invincible = invincible;
    }
    Ok(ok())
}

/// Phase 3-B: ボスの phase_timer を Elixir 側 AI から更新する NIF。
#[rustler::nif]
pub fn set_boss_phase_timer(world: ResourceArc<GameWorld>, timer: f64) -> NifResult<Atom> {
    let mut w = world.0.write().map_err(|_| lock_poisoned_err())?;
    if let Some(ref mut boss) = w.boss {
        boss.phase_timer = timer as f32;
    }
    Ok(ok())
}

/// Phase 3-B: Elixir 側 AI がボスの弾丸を発射するための NIF。
/// dx/dy は方向ベクトル（正規化不要）、speed は弾速、damage はダメージ、lifetime は寿命（秒）
#[rustler::nif]
pub fn fire_boss_projectile(
    world: ResourceArc<GameWorld>,
    dx: f64,
    dy: f64,
    speed: f64,
    damage: i32,
    lifetime: f64,
) -> NifResult<Atom> {
    let mut w = world.0.write().map_err(|_| lock_poisoned_err())?;
    if let Some(ref boss) = w.boss {
        let bx = boss.x;
        let by = boss.y;
        let len = ((dx * dx + dy * dy) as f32).sqrt().max(0.001);
        let vx = (dx as f32 / len) * speed as f32;
        let vy = (dy as f32 / len) * speed as f32;
        use game_physics::world::BULLET_KIND_ROCK;
        w.bullets.spawn_ex(
            bx,
            by,
            vx,
            vy,
            damage,
            lifetime as f32,
            false,
            BULLET_KIND_ROCK,
        );
    }
    Ok(ok())
}

/// Phase 3-C: Elixir 側がスコアポップアップを描画用バッファに追加する NIF。
/// EnemyKilled / BossDefeated イベント受信時に Elixir 側から呼び出す。
/// value: 表示するスコア値
#[rustler::nif]
pub fn add_score_popup(
    world: ResourceArc<GameWorld>,
    x: f64,
    y: f64,
    value: u32,
) -> NifResult<Atom> {
    let mut w = world.0.write().map_err(|_| lock_poisoned_err())?;
    w.score_popups
        .push((x as f32, y as f32 + POPUP_Y_OFFSET, value, POPUP_LIFETIME));
    Ok(ok())
}

/// Phase 3-B: Elixir 側のルールがアイテムドロップを制御するための NIF。
/// kind: 0=Gem, 1=Potion, 2=Magnet
#[rustler::nif]
pub fn spawn_item(
    world: ResourceArc<GameWorld>,
    x: f64,
    y: f64,
    kind: u8,
    value: u32,
) -> NifResult<Atom> {
    let mut w = world.0.write().map_err(|_| lock_poisoned_err())?;
    let item_kind = match kind {
        0 => ItemKind::Gem,
        1 => ItemKind::Potion,
        2 => ItemKind::Magnet,
        _ => ItemKind::Gem,
    };
    w.items.spawn(x as f32, y as f32, item_kind, value);
    Ok(ok())
}

#[rustler::nif]
pub fn spawn_elite_enemy(
    world: ResourceArc<GameWorld>,
    kind_id: u8,
    count: usize,
    hp_multiplier: f64,
) -> NifResult<Atom> {
    let mut w = world.0.write().map_err(|_| lock_poisoned_err())?;
    let ep = w
        .params
        .get_enemy(kind_id)
        .ok_or_else(params_not_loaded_err)?
        .clone();
    let base_max_hp = ep.max_hp;
    let positions = get_spawn_positions_around_player(&mut w, count);
    let before_len = w.enemies.positions_x.len();
    w.enemies.spawn(&positions, kind_id, &ep);
    let after_len = w.enemies.positions_x.len();
    let base_hp = base_max_hp * hp_multiplier as f32;
    let mut applied = 0;
    for i in (0..after_len).rev() {
        if applied >= count {
            break;
        }
        if w.enemies.alive[i] != 0
            && w.enemies.kind_ids[i] == kind_id
            && (i >= before_len || (w.enemies.hp[i] - base_max_hp).abs() < 0.01)
        {
            w.enemies.hp[i] = base_hp;
            applied += 1;
        }
    }
    Ok(ok())
}
