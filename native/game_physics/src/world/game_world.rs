//! Path: native/game_physics/src/world/game_world.rs
//! Summary: 繧ｲ繝ｼ繝繝ｯ繝ｼ繝ｫ繝会ｼ・ameWorldInner, GameWorld・・

use super::{BossState, BulletWorld, EnemyWorld, ParticleWorld, PlayerState};
use crate::entity_params::EntityParamTables;
use crate::item::ItemWorld;
use crate::physics::rng::SimpleRng;
use crate::physics::spatial_hash::CollisionWorld;
use crate::weapon::WeaponSlot;
use std::sync::RwLock;

use super::FrameEvent;

/// 繧ｲ繝ｼ繝繝ｯ繝ｼ繝ｫ繝牙・驛ｨ迥ｶ諷・
///
/// ## Elixir as SSoT 遘ｻ陦悟ｾ後・讒矩
/// 莉･荳九・繝輔ぅ繝ｼ繝ｫ繝峨・ Elixir 蛛ｴ縺梧ｨｩ螽√ｒ謖√■縲∵ｯ弱ヵ繝ｬ繝ｼ繝 NIF 縺ｧ豕ｨ蜈･縺輔ｌ繧・
/// - `player.hp`        竊・set_player_hp NIF・医ヵ繧ｧ繝ｼ繧ｺ2・・
/// - `player.input_dx/dy` 竊・set_player_input NIF・医ヵ繧ｧ繝ｼ繧ｺ5・・
/// - `elapsed_seconds`  竊・set_elapsed_seconds NIF・医ヵ繧ｧ繝ｼ繧ｺ3・・
/// - `boss.hp`          竊・set_boss_hp NIF・医ヵ繧ｧ繝ｼ繧ｺ4・・
/// - `score`, `kill_count` 竊・set_hud_state NIF・医ヵ繧ｧ繝ｼ繧ｺ1・・
/// - `params`           竊・set_entity_params NIF・・hase 3-A・・
/// - `map_width/height` 竊・set_world_size NIF・・hase 3-A・・
/// - `hud_level`, `hud_exp`, `hud_exp_to_next`, `hud_level_up_pending`, `hud_weapon_choices`
///                      竊・set_hud_level_state NIF・・hase 3-B: 謠冗判蟆ら畑・・
/// - `weapon_slots`     竊・set_weapon_slots NIF・・-2: 豈弱ヵ繝ｬ繝ｼ繝 Elixir 縺九ｉ豕ｨ蜈･・・
pub struct GameWorldInner {
    pub frame_id:           u32,
    pub player:             PlayerState,
    pub enemies:            EnemyWorld,
    pub bullets:            BulletWorld,
    pub particles:          ParticleWorld,
    /// 1.2.4: 繧｢繧､繝・Β
    pub items:              ItemWorld,
    /// 逎∫浹繧ｨ繝輔ぉ繧ｯ繝域ｮ九ｊ譎る俣・育ｧ抵ｼ・
    pub magnet_timer:       f32,
    pub rng:                SimpleRng,
    pub collision:          CollisionWorld,
    /// 1.5.2: 髫懷ｮｳ迚ｩ繧ｯ繧ｨ繝ｪ逕ｨ繝舌ャ繝輔ぃ・域ｯ弱ヵ繝ｬ繝ｼ繝蜀榊茜逕ｨ・・
    pub obstacle_query_buf: Vec<usize>,
    /// 蜍慕噪繧ｨ繝ｳ繝・ぅ繝・ぅ・域雰繝ｻ蠑ｾ荳ｸ・峨け繧ｨ繝ｪ逕ｨ繝舌ャ繝輔ぃ・域ｯ弱ヵ繝ｬ繝ｼ繝蜀榊茜逕ｨ縲√い繝ｭ繧ｱ繝ｼ繧ｷ繝ｧ繝ｳ蝗樣∩・・
    pub spatial_query_buf:  Vec<usize>,
    /// 逶ｴ霑代ヵ繝ｬ繝ｼ繝縺ｮ迚ｩ逅・せ繝・ャ繝怜・逅・凾髢難ｼ医Α繝ｪ遘抵ｼ・
    pub last_frame_time_ms: f64,
    /// 繧ｲ繝ｼ繝髢句ｧ九°繧峨・邨碁℃譎る俣・育ｧ抵ｼ・ Elixir 縺九ｉ豈弱ヵ繝ｬ繝ｼ繝豕ｨ蜈･・医せ繝昴・繝ｳ險育ｮ礼畑・・
    pub elapsed_seconds:    f32,
    /// 繝励Ξ繧､繝､繝ｼ縺ｮ譛螟ｧ HP・・P 繝舌・險育ｮ礼畑・・
    pub player_max_hp:      f32,
    /// I-2: 陬・ｙ荳ｭ縺ｮ豁ｦ蝎ｨ繧ｹ繝ｭ繝・ヨ・医け繝ｼ繝ｫ繝繧ｦ繝ｳ邂｡逅・・縺ｿ・・ Elixir 縺九ｉ豈弱ヵ繝ｬ繝ｼ繝 set_weapon_slots NIF 縺ｧ豕ｨ蜈･
    pub weapon_slots:       Vec<WeaponSlot>,
    /// I-2: 繝懊せ繧ｨ繝阪Α繝ｼ迚ｩ逅・憾諷具ｼ・oss.hp 縺ｯ Elixir 縺九ｉ豈弱ヵ繝ｬ繝ｼ繝豕ｨ蜈･・・
    /// 繝懊せ遞ｮ蛻･縺ｮ讎ょｿｵ縺ｯ Elixir 蛛ｴ Rule state 縺ｧ邂｡逅・☆繧九・
    pub boss:               Option<BossState>,
    /// 1.3.1: 縺薙・繝輔Ξ繝ｼ繝縺ｧ逋ｺ逕溘＠縺溘う繝吶Φ繝茨ｼ域ｯ弱ヵ繝ｬ繝ｼ繝 drain 縺輔ｌ繧具ｼ・
    pub frame_events:       Vec<FrameEvent>,
    /// 1.7.5: 繧ｹ繧ｳ繧｢繝昴ャ繝励い繝・・ [(world_x, world_y, value, lifetime)]・域緒逕ｻ逕ｨ・・
    pub score_popups:       Vec<(f32, f32, u32, f32)>,
    /// 繧ｹ繧ｳ繧｢ - Elixir 縺九ｉ豈弱ヵ繝ｬ繝ｼ繝豕ｨ蜈･・・UD 陦ｨ遉ｺ逕ｨ・・
    pub score:              u32,
    /// 繧ｭ繝ｫ謨ｰ - Elixir 縺九ｉ豈弱ヵ繝ｬ繝ｼ繝豕ｨ蜈･・・UD 陦ｨ遉ｺ逕ｨ・・
    pub kill_count:         u32,
    /// 1.10.7: 陬憺俣逕ｨ - 蜑阪ヵ繝ｬ繝ｼ繝縺ｮ繝励Ξ繧､繝､繝ｼ菴咲ｽｮ
    pub prev_player_x:      f32,
    pub prev_player_y:      f32,
    /// 1.10.7: 陬憺俣逕ｨ - 蜑阪ヵ繝ｬ繝ｼ繝縺ｮ譖ｴ譁ｰ繧ｿ繧､繝繧ｹ繧ｿ繝ｳ繝暦ｼ・s・・
    pub prev_tick_ms:       u64,
    /// 1.10.7: 陬憺俣逕ｨ - 迴ｾ蝨ｨ繝輔Ξ繝ｼ繝縺ｮ譖ｴ譁ｰ繧ｿ繧､繝繧ｹ繧ｿ繝ｳ繝暦ｼ・s・・
    pub curr_tick_ms:       u64,
    /// Phase 3-A: 繧ｨ繝ｳ繝・ぅ繝・ぅ繝代Λ繝｡繝ｼ繧ｿ繝・・繝悶Ν・・et_entity_params NIF 縺ｧ豕ｨ蜈･・・
    pub params:             EntityParamTables,
    /// Phase 3-A: 繝槭ャ繝励し繧､繧ｺ・・et_world_size NIF 縺ｧ豕ｨ蜈･・・
    pub map_width:          f32,
    pub map_height:         f32,
    /// Phase 3-B: HUD 謠冗判蟆ら畑繝輔ぅ繝ｼ繝ｫ繝会ｼ・lixir SSoT 縺九ｉ豈弱ヵ繝ｬ繝ｼ繝豕ｨ蜈･・・
    /// 繧ｲ繝ｼ繝繝ｭ繧ｸ繝・け縺ｫ縺ｯ菴ｿ逕ｨ縺励↑縺・ゅΞ繝ｳ繝繝ｪ繝ｳ繧ｰ繝代う繝励Λ繧､繝ｳ縺ｮ縺ｿ縺悟盾辣ｧ縺吶ｋ縲・
    pub hud_level:              u32,
    pub hud_exp:                u32,
    pub hud_exp_to_next:        u32,
    pub hud_level_up_pending:   bool,
    pub hud_weapon_choices:     Vec<String>,
}

impl GameWorldInner {
    /// 陦晉ｪ∝愛螳夂畑縺ｮ Spatial Hash 繧貞・讒狗ｯ峨☆繧具ｼ・lone 荳崎ｦ・ｼ・
    pub fn rebuild_collision(&mut self) {
        self.collision.dynamic.clear();
        self.enemies.alive
            .iter()
            .enumerate()
            .filter(|&(_, &is_alive)| is_alive != 0)
            .for_each(|(i, _)| {
                self.collision.dynamic.insert(
                    i,
                    self.enemies.positions_x[i],
                    self.enemies.positions_y[i],
                );
            });
    }
}

/// 繧ｲ繝ｼ繝繝ｯ繝ｼ繝ｫ繝会ｼ・wLock 縺ｧ菫晁ｭｷ縺輔ｌ縺溷・驛ｨ迥ｶ諷具ｼ・
pub struct GameWorld(pub RwLock<GameWorldInner>);

#[cfg(feature = "nif")]
impl rustler::Resource for GameWorld {}

#[cfg(feature = "nif")]
impl rustler::Resource for super::game_loop_control::GameLoopControl {}
