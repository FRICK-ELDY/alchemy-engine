//! Path: native/nif/src/nif/events.rs
//! Summary: フレームイベントの drain（Elixir EventBus 用）

use crate::physics::world::{FrameEvent, GameWorldInner};
use rustler::Atom;

/// フレームイベントを `(atom, u32, u32, u32, u32)` の 5 要素タプルに変換する。
/// x/y 座標は f32::to_bits() で u32 として渡す。Elixir 側では <<x::float-32>> でデコードする。
pub(crate) fn drain_frame_events_inner(w: &mut GameWorldInner) -> Vec<(Atom, u32, u32, u32, u32)> {
    w.frame_events
        .drain(..)
        .map(|e| match e {
            FrameEvent::EnemyKilled { enemy_kind, x, y } => (
                crate::enemy_killed(),
                enemy_kind as u32,
                x.to_bits(),
                y.to_bits(),
                0,
            ),
            FrameEvent::PlayerDamaged { damage } => (
                crate::player_damaged(),
                (damage * 1000.0).clamp(0.0, u32::MAX as f32) as u32,
                0,
                0,
                0,
            ),
            FrameEvent::ItemPickup { item_kind, value } => {
                (crate::item_pickup(), item_kind as u32, value, 0, 0)
            }
            FrameEvent::SpecialEntityDefeated { x, y } => {
                (crate::boss_defeated(), 0, x.to_bits(), y.to_bits(), 0)
            }
            FrameEvent::SpecialEntitySpawned { entity_kind } => {
                (crate::boss_spawn(), entity_kind as u32, 0, 0, 0)
            }
            FrameEvent::SpecialEntityDamaged { damage } => (
                crate::boss_damaged(),
                (damage * 1000.0).clamp(0.0, u32::MAX as f32) as u32,
                0,
                0,
                0,
            ),
            FrameEvent::WeaponCooldownUpdated {
                kind_id,
                cooldown_timer,
            } => (
                crate::weapon_cooldown_updated(),
                kind_id as u32,
                cooldown_timer.to_bits(),
                0,
                0,
            ),
        })
        .collect()
}
