//! Path: native/game_native/src/game_logic/events.rs
//! Summary: フレームイベントの drain（Elixir EventBus 用）

use crate::world::{FrameEvent, GameWorldInner};
use rustler::Atom;

/// 1.5.1: フレームイベントを取り出す内部実装（Rust ゲームループスレッドから呼ぶ）
pub(crate) fn drain_frame_events_inner(w: &mut GameWorldInner) -> Vec<(Atom, u32, u32)> {
    w.frame_events
        .drain(..)
        .map(|e| match e {
            FrameEvent::EnemyKilled { enemy_kind, weapon_kind } =>
                (crate::enemy_killed(), enemy_kind as u32, weapon_kind as u32),
            FrameEvent::PlayerDamaged { damage } =>
                (crate::player_damaged(), (damage * 1000.0) as u32, 0),
            FrameEvent::LevelUp { new_level } =>
                (crate::level_up_event(), new_level as u32, 0),
            FrameEvent::ItemPickup { item_kind } =>
                (crate::item_pickup(), item_kind as u32, 0),
            FrameEvent::BossDefeated { boss_kind } =>
                (crate::boss_defeated(), boss_kind as u32, 0),
        })
        .collect()
}
