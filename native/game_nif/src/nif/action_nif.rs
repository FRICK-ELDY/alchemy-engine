//! Path: native/game_nif/src/nif/action_nif.rs
//! Summary: アクション NIF（add_weapon, skip_level_up, spawn_boss, spawn_elite_enemy）

use super::util::lock_poisoned_err;
use game_simulation::game_logic::systems::spawn::get_spawn_positions_around_player;
use game_simulation::world::{BossState, FrameEvent, GameWorld};
use game_simulation::constants::PLAYER_RADIUS;
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
    w.complete_level_up();
    Ok(ok())
}

#[rustler::nif]
pub fn skip_level_up(world: ResourceArc<GameWorld>) -> NifResult<Atom> {
    let mut w = world.0.write().map_err(|_| lock_poisoned_err())?;
    w.complete_level_up();
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
