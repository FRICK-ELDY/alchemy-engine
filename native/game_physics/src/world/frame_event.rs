//! Path: native/game_physics/src/world/frame_event.rs
//! Summary: 繝輔Ξ繝ｼ繝蜀・〒逋ｺ逕溘＠縺溘ご繝ｼ繝繧､繝吶Φ繝茨ｼ・ventBus 逕ｨ・・

/// 1.3.1: 繝輔Ξ繝ｼ繝蜀・〒逋ｺ逕溘＠縺溘ご繝ｼ繝繧､繝吶Φ繝茨ｼ・ventBus 逕ｨ・・
#[derive(Debug, Clone)]
pub enum FrameEvent {
    /// 謨ｵ縺梧茶遐ｴ縺輔ｌ縺溘Ｙ/y 縺ｯ繝峨Ο繝・・繧｢繧､繝・Β縺ｮ繧ｹ繝昴・繝ｳ菴咲ｽｮ縺ｨ縺励※ Elixir 蛛ｴ縺ｧ菴ｿ逕ｨ縺吶ｋ縲・
    EnemyKilled  { enemy_kind: u8, x: f32, y: f32 },
    PlayerDamaged { damage: f32 },
    ItemPickup   { item_kind: u8 },
    /// 迚ｹ谿翫お繝ｳ繝・ぅ繝・ぅ・医・繧ｹ遲会ｼ峨′謦・ｴ縺輔ｌ縺溘・
    /// I-4: 繝懊せ遞ｮ蛻･縺ｯ Elixir 蛛ｴ Rule state 縺ｧ邂｡逅・☆繧九◆繧・entity_kind 繝輔ぅ繝ｼ繝ｫ繝峨ｒ髯､蜴ｻ縲・
    SpecialEntityDefeated { x: f32, y: f32 },
    /// 迚ｹ谿翫お繝ｳ繝・ぅ繝・ぅ・医・繧ｹ遲会ｼ峨′蜃ｺ迴ｾ縺励◆縲・lixir 蛛ｴ縺ｧ HP 蛻晄悄蛹悶↓菴ｿ逕ｨ縺吶ｋ縲・
    SpecialEntitySpawned  { entity_kind: u8 },
    /// 迚ｹ谿翫お繝ｳ繝・ぅ繝・ぅ・医・繧ｹ遲会ｼ峨′繝繝｡繝ｼ繧ｸ繧貞女縺代◆縲・lixir 蛛ｴ縺ｧ HP 貂帷ｮ励↓菴ｿ逕ｨ縺吶ｋ縲・
    SpecialEntityDamaged  { damage: f32 },
}
