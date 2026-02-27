//! Path: native/game_native/src/nif/save_nif.rs
//! Summary: セーブ・ロード NIF

use super::util::lock_poisoned_err;
use crate::world::{BulletWorld, GameWorld};
use game_core::constants::PARTICLE_RNG_SEED;
use game_core::item::ItemWorld;
use game_core::weapon::WeaponSlot;
use rustler::{Atom, NifResult, ResourceArc};

use crate::{ok, ParticleWorld};

/// 武器スロットの保存用データ（NifMap で Elixir map と相互変換）
#[derive(Debug, Clone, rustler::NifMap)]
pub struct WeaponSlotSave {
    pub kind_id: u8,
    pub level:   u32,
}

/// ゲーム状態のスナップショット（セーブ/ロード用）
///
/// フェーズ1〜3 の移行後:
/// - score/kill_count は Elixir 側が権威を持つため、SaveManager が Elixir 側の値を保存する
/// - Rust 側のスナップショットには物理演算に必要な値のみ含める
#[derive(Debug, Clone, rustler::NifMap)]
pub struct SaveSnapshot {
    pub player_hp:        f32,
    pub player_x:         f32,
    pub player_y:         f32,
    pub player_max_hp:    f32,
    pub level:            u32,
    pub exp:              u32,
    pub elapsed_seconds:  f32,
    pub weapon_slots:     Vec<WeaponSlotSave>,
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
        level:           w.level,
        exp:             w.exp,
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
    w.exp             = snapshot.exp;
    w.level           = snapshot.level;

    let mut slots: Vec<WeaponSlot> = snapshot.weapon_slots
        .into_iter()
        .map(|s| WeaponSlot { kind_id: s.kind_id, level: s.level, cooldown_timer: 0.0 })
        .collect();
    if slots.is_empty() {
        slots.push(WeaponSlot::new(0));
    }
    w.weapon_slots = slots;

    w.enemies  = crate::EnemyWorld::new();
    w.bullets  = BulletWorld::new();
    w.particles = ParticleWorld::new(PARTICLE_RNG_SEED);
    w.items    = ItemWorld::new();
    w.boss     = None;
    w.frame_events.clear();
    w.magnet_timer = 0.0;
    w.score_popups.clear();
    w.weapon_choices.clear();

    w.collision.dynamic.clear();

    Ok(ok())
}
