//! Path: native/game_nif/src/nif/action_nif.rs
//! Summary: アクション NIF（add_weapon, skip_level_up, spawn_boss, spawn_elite_enemy, spawn_item 等）

use super::util::lock_poisoned_err;
use game_simulation::game_logic::systems::spawn::get_spawn_positions_around_player;
use game_simulation::world::{BossState, FrameEvent, GameWorld};
use game_simulation::constants::PLAYER_RADIUS;
use game_simulation::item::ItemKind;
use game_simulation::weapon::{WeaponSlot, MAX_WEAPON_LEVEL, MAX_WEAPON_SLOTS};
use rustler::{Atom, NifResult, ResourceArc};

use crate::ok;

#[rustler::nif]
pub fn add_weapon(world: ResourceArc<GameWorld>, weapon_id: u8) -> NifResult<Atom> {
    let mut w = world.0.write().map_err(|_| lock_poisoned_err())?;
    if let Some(slot) = w.weapon_slots.iter_mut().find(|s| s.kind_id == weapon_id) {
        slot.level = (slot.level + 1).min(MAX_WEAPON_LEVEL);
    } else if w.weapon_slots.len() < MAX_WEAPON_SLOTS {
        w.weapon_slots.push(WeaponSlot::new(weapon_id));
    }
    Ok(ok())
}

#[rustler::nif]
pub fn skip_level_up(_world: ResourceArc<GameWorld>) -> NifResult<Atom> {
    Ok(ok())
}

#[rustler::nif]
pub fn spawn_boss(world: ResourceArc<GameWorld>, kind_id: u8) -> NifResult<Atom> {
    let mut w = world.0.write().map_err(|_| lock_poisoned_err())?;
    if w.boss.is_some() { return Ok(ok()); }
    if (kind_id as usize) < w.params.bosses.len() {
        let bp = w.params.get_boss(kind_id).clone();
        let px = w.player.x + PLAYER_RADIUS;
        let py = w.player.y + PLAYER_RADIUS;
        let bx = (px + 600.0).min(w.map_width  - bp.radius);
        let by = py.clamp(bp.radius, w.map_height - bp.radius);
        w.boss = Some(BossState::new(kind_id, bx, by, &bp));
        w.frame_events.push(FrameEvent::BossSpawn { boss_kind: kind_id });
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
pub fn fire_boss_projectile(world: ResourceArc<GameWorld>, dx: f64, dy: f64, speed: f64, damage: i32, lifetime: f64) -> NifResult<Atom> {
    let mut w = world.0.write().map_err(|_| lock_poisoned_err())?;
    if let Some(ref boss) = w.boss {
        let bx = boss.x;
        let by = boss.y;
        let len = ((dx * dx + dy * dy) as f32).sqrt().max(0.001);
        let vx = (dx as f32 / len) * speed as f32;
        let vy = (dy as f32 / len) * speed as f32;
        use game_simulation::world::BULLET_KIND_ROCK;
        w.bullets.spawn_ex(bx, by, vx, vy, damage, lifetime as f32, false, BULLET_KIND_ROCK);
    }
    Ok(ok())
}

/// Phase 3-B: Elixir 側のルールがアイテムドロップを制御するための NIF。
/// kind: 0=Gem, 1=Potion, 2=Magnet
#[rustler::nif]
pub fn spawn_item(world: ResourceArc<GameWorld>, x: f64, y: f64, kind: u8, value: u32) -> NifResult<Atom> {
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
pub fn spawn_elite_enemy(world: ResourceArc<GameWorld>, kind_id: u8, count: usize, hp_multiplier: f64) -> NifResult<Atom> {
    let mut w = world.0.write().map_err(|_| lock_poisoned_err())?;
    let base_max_hp = w.params.get_enemy(kind_id).max_hp;
    let positions = get_spawn_positions_around_player(&mut w, count);
    let before_len = w.enemies.positions_x.len();
    // w.enemies（可変借用）と w.params（不変借用）の同時借用を避けるため
    // 必要なパラメータのみ先にコピーする
    let ep = w.params.get_enemy(kind_id).clone();
    w.enemies.spawn(&positions, kind_id, &ep);
    let after_len = w.enemies.positions_x.len();
    let base_hp = base_max_hp * hp_multiplier as f32;
    let mut applied = 0;
    for i in (0..after_len).rev() {
        if applied >= count { break; }
        if w.enemies.alive[i] && w.enemies.kind_ids[i] == kind_id {
            if i >= before_len || (w.enemies.hp[i] - base_max_hp).abs() < 0.01 {
                w.enemies.hp[i] = base_hp;
                applied += 1;
            }
        }
    }
    Ok(ok())
}
