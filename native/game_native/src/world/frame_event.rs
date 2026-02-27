//! Path: native/game_native/src/world/frame_event.rs
//! Summary: フレーム内で発生したゲームイベント（EventBus 用）

/// 1.3.1: フレーム内で発生したゲームイベント（EventBus 用）
#[derive(Debug, Clone)]
pub enum FrameEvent {
    EnemyKilled  { enemy_kind: u8, weapon_kind: u8 },
    PlayerDamaged { damage: f32 },
    LevelUp      { new_level: u32 },
    ItemPickup   { item_kind: u8 },
    BossDefeated { boss_kind: u8 },
}
