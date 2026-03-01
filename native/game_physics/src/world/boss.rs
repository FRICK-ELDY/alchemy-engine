//! Path: native/game_physics/src/world/boss.rs
//! Summary: 繝懊せ迥ｶ諷具ｼ・ossState・・

use crate::entity_params::BossParams;

/// 繝懊せ迚ｩ逅・憾諷・
///
/// I-2: 繝懊せ遞ｮ蛻･縺ｮ讎ょｿｵ・・ind_id・峨ｒ Rust 縺九ｉ髯､蜴ｻ縲・
/// 繝懊せ遞ｮ蛻･縺ｯ Elixir 蛛ｴ Rule state 縺ｧ邂｡逅・＠縲《pawn_boss NIF 蜻ｼ縺ｳ蜃ｺ縺玲凾縺ｫ
/// 迚ｩ逅・ヱ繝ｩ繝｡繝ｼ繧ｿ・・adius, render_kind, max_hp 遲会ｼ峨・縺ｿ Rust 縺ｫ貂｡縺吶・
/// Phase 3-B: AI 繝ｭ繧ｸ繝・け縺ｯ Elixir 蛛ｴ縺ｫ遘ｻ邂｡貂医∩縲３ust 縺ｯ繝懊せ縺ｮ迚ｩ逅・噪縺ｪ蟄伜惠縺ｮ縺ｿ邂｡逅・☆繧九・
pub struct BossState {
    pub x:           f32,
    pub y:           f32,
    pub hp:          f32,
    pub max_hp:      f32,
    /// Elixir 縺九ｉ set_boss_velocity NIF 縺ｧ豕ｨ蜈･縺輔ｌ繧矩溷ｺｦ繝吶け繝医Ν
    pub vx:          f32,
    pub vy:          f32,
    /// Elixir 縺九ｉ set_boss_invincible NIF 縺ｧ豕ｨ蜈･縺輔ｌ繧狗┌謨ｵ繝輔Λ繧ｰ
    pub invincible:  bool,
    /// Elixir 蛛ｴ AI 縺御ｽｿ逕ｨ縺吶ｋ繝輔ぉ繝ｼ繧ｺ繧ｿ繧､繝槭・・・ust 縺ｯ譖ｴ譁ｰ縺励↑縺・∝・譛溷､縺ｮ縺ｿ險ｭ螳夲ｼ・
    pub phase_timer: f32,
    /// 謠冗判逕ｨ繧ｹ繝励Λ繧､繝育ｨｮ蛻･・・pawn_boss NIF 縺ｧ Elixir 縺九ｉ豕ｨ蜈･・・
    pub render_kind:      u8,
    /// 蠖薙◆繧雁愛螳壼濠蠕・ｼ・pawn_boss NIF 縺ｧ Elixir 縺九ｉ豕ｨ蜈･・・
    pub radius:           f32,
    /// 謗･隗ｦ繝繝｡繝ｼ繧ｸ豈守ｧ抵ｼ・pawn_boss NIF 縺ｧ Elixir 縺九ｉ豕ｨ蜈･・・
    pub damage_per_sec:   f32,
}

impl BossState {
    /// `bp` 縺ｯ蜻ｼ縺ｳ蜃ｺ縺怜・縺ｧ `params.get_boss(kind_id).clone()` 縺励※貂｡縺吶・
    /// ・亥庄螟牙溽畑縺ｨ荳榊､牙溽畑縺ｮ遶ｶ蜷医ｒ驕ｿ縺代ｋ縺溘ａ縲√ユ繝ｼ繝悶Ν縺ｧ縺ｯ縺ｪ縺丞､繧貞女縺大叙繧具ｼ・
    pub fn new(x: f32, y: f32, bp: &BossParams) -> Self {
        Self {
            x, y,
            hp:            bp.max_hp,
            max_hp:        bp.max_hp,
            vx:            0.0,
            vy:            0.0,
            invincible:    false,
            phase_timer:   bp.special_interval,
            render_kind:   bp.render_kind,
            radius:        bp.radius,
            damage_per_sec: bp.damage_per_sec,
        }
    }
}
