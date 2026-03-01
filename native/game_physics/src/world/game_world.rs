//! Path: native/game_physics/src/world/game_world.rs
//! Summary: ゲームワールド（GameWorldInner, GameWorld）

use super::{BossState, BulletWorld, EnemyWorld, ParticleWorld, PlayerState};
use crate::entity_params::EntityParamTables;
use crate::item::ItemWorld;
use crate::physics::rng::SimpleRng;
use crate::physics::spatial_hash::CollisionWorld;
use crate::weapon::WeaponSlot;
use std::sync::RwLock;

use super::FrameEvent;

/// ゲームワールド内部状態
///
/// ## Elixir as SSoT 移行後の構造
/// 以下のフィールドは Elixir 側が権威を持ち、毎フレーム NIF で注入される:
/// - `player.hp`        → set_player_hp NIF（フェーズ2）
/// - `player.input_dx/dy` → set_player_input NIF（フェーズ5）
/// - `elapsed_seconds`  → set_elapsed_seconds NIF（フェーズ3）
/// - `boss.hp`          → set_boss_hp NIF（フェーズ4）
/// - `score`, `kill_count` → set_hud_state NIF（フェーズ1）
/// - `params`           → set_entity_params NIF（Phase 3-A）
/// - `map_width/height` → set_world_size NIF（Phase 3-A）
/// - `hud_level`, `hud_exp`, `hud_exp_to_next`, `hud_level_up_pending`, `hud_weapon_choices`
///                      → set_hud_level_state NIF（Phase 3-B: 描画専用）
/// - `weapon_slots`     → set_weapon_slots NIF（I-2: 毎フレーム Elixir から注入）
pub struct GameWorldInner {
    pub frame_id:           u32,
    pub player:             PlayerState,
    pub enemies:            EnemyWorld,
    pub bullets:            BulletWorld,
    pub particles:          ParticleWorld,
    /// 1.2.4: アイテム
    pub items:              ItemWorld,
    /// 磁石エフェクト残り時間（秒）
    pub magnet_timer:       f32,
    pub rng:                SimpleRng,
    pub collision:          CollisionWorld,
    /// 1.5.2: 障害物クエリ用バッファ（毎フレーム再利用）
    pub obstacle_query_buf: Vec<usize>,
    /// 動的エンティティ（敵・弾丸）クエリ用バッファ（毎フレーム再利用、アロケーション回避）
    pub spatial_query_buf:  Vec<usize>,
    /// 直近フレームの物理ステップ処理時間（ミリ秒）
    pub last_frame_time_ms: f64,
    /// ゲーム開始からの経過時間（秒）- Elixir から毎フレーム注入（スポーン計算用）
    pub elapsed_seconds:    f32,
    /// プレイヤーの最大 HP（HP バー計算用）
    pub player_max_hp:      f32,
    /// I-2: 装備中の武器スロット（クールダウン管理のみ）- Elixir から毎フレーム set_weapon_slots NIF で注入
    pub weapon_slots:       Vec<WeaponSlot>,
    /// I-2: ボスエネミー物理状態（boss.hp は Elixir から毎フレーム注入）
    /// ボス種別の概念は Elixir 側 Rule state で管理する。
    pub boss:               Option<BossState>,
    /// 1.3.1: このフレームで発生したイベント（毎フレーム drain される）
    pub frame_events:       Vec<FrameEvent>,
    /// 1.7.5: スコアポップアップ [(world_x, world_y, value, lifetime)]（描画用）
    pub score_popups:       Vec<(f32, f32, u32, f32)>,
    /// スコア - Elixir から毎フレーム注入（HUD 表示用）
    pub score:              u32,
    /// キル数 - Elixir から毎フレーム注入（HUD 表示用）
    pub kill_count:         u32,
    /// 1.10.7: 補間用 - 前フレームのプレイヤー位置
    pub prev_player_x:      f32,
    pub prev_player_y:      f32,
    /// 1.10.7: 補間用 - 前フレームの更新タイムスタンプ（ms）
    pub prev_tick_ms:       u64,
    /// 1.10.7: 補間用 - 現在フレームの更新タイムスタンプ（ms）
    pub curr_tick_ms:       u64,
    /// Phase 3-A: エンティティパラメータテーブル（set_entity_params NIF で注入）
    pub params:             EntityParamTables,
    /// Phase 3-A: マップサイズ（set_world_size NIF で注入）
    pub map_width:          f32,
    pub map_height:         f32,
    /// Phase 3-B: HUD 描画専用フィールド（Elixir SSoT から毎フレーム注入）
    /// ゲームロジックには使用しない。レンダリングパイプラインのみが参照する。
    pub hud_level:              u32,
    pub hud_exp:                u32,
    pub hud_exp_to_next:        u32,
    pub hud_level_up_pending:   bool,
    pub hud_weapon_choices:     Vec<String>,
}

impl GameWorldInner {
    /// 衝突判定用の Spatial Hash を再構築する（clone 不要）
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

/// ゲームワールド（RwLock で保護された内部状態）
pub struct GameWorld(pub RwLock<GameWorldInner>);

#[cfg(feature = "nif")]
impl rustler::Resource for GameWorld {}

#[cfg(feature = "nif")]
impl rustler::Resource for super::game_loop_control::GameLoopControl {}
