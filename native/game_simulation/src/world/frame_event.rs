//! Path: native/game_simulation/src/world/frame_event.rs
//! Summary: フレーム内で発生したゲームイベント（EventBus 用）

/// 1.3.1: フレーム内で発生したゲームイベント（EventBus 用）
#[derive(Debug, Clone)]
pub enum FrameEvent {
    EnemyKilled  { enemy_kind: u8, weapon_kind: u8 },
    PlayerDamaged { damage: f32 },
    LevelUp      { new_level: u32 },
    ItemPickup   { item_kind: u8 },
    BossDefeated { boss_kind: u8 },
    /// フェーズ4: ボス出現イベント（Elixir 側でボス HP を初期化するために使用）
    BossSpawn    { boss_kind: u8 },
    /// フェーズ4: ボスへのダメージイベント（Elixir 側でボス HP を減算するために使用）
    BossDamaged  { damage: f32 },
}
