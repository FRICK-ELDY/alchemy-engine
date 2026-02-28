//! Path: native/game_simulation/src/world/frame_event.rs
//! Summary: フレーム内で発生したゲームイベント（EventBus 用）

/// 1.3.1: フレーム内で発生したゲームイベント（EventBus 用）
#[derive(Debug, Clone)]
pub enum FrameEvent {
    /// 敵が撃破された。x/y はドロップアイテムのスポーン位置として Elixir 側で使用する。
    EnemyKilled  { enemy_kind: u8, x: f32, y: f32 },
    PlayerDamaged { damage: f32 },
    ItemPickup   { item_kind: u8 },
    /// 特殊エンティティ（ボス等）が撃破された。
    /// I-4: ボス種別は Elixir 側 Rule state で管理するため entity_kind フィールドを除去。
    SpecialEntityDefeated { x: f32, y: f32 },
    /// 特殊エンティティ（ボス等）が出現した。Elixir 側で HP 初期化に使用する。
    SpecialEntitySpawned  { entity_kind: u8 },
    /// 特殊エンティティ（ボス等）がダメージを受けた。Elixir 側で HP 減算に使用する。
    SpecialEntityDamaged  { damage: f32 },
}
