//! Path: native/game_simulation/src/world/frame_event.rs
//! Summary: フレーム内で発生したゲームイベント（EventBus 用）

/// 1.3.1: フレーム内で発生したゲームイベント（EventBus 用）
#[derive(Debug, Clone)]
pub enum FrameEvent {
    /// 敵が撃破された。x/y はドロップアイテムのスポーン位置として Elixir 側で使用する。
    EnemyKilled  { enemy_kind: u8, x: f32, y: f32 },
    PlayerDamaged { damage: f32 },
    ItemPickup   { item_kind: u8 },
    BossDefeated { boss_kind: u8, x: f32, y: f32 },
    /// フェーズ4: ボス出現イベント（Elixir 側でボス HP を初期化するために使用）
    BossSpawn    { boss_kind: u8 },
    /// フェーズ4: ボスへのダメージイベント（Elixir 側でボス HP を減算するために使用）
    BossDamaged  { damage: f32 },
}
