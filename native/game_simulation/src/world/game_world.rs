//! Path: native/game_simulation/src/world/game_world.rs
//! Summary: ゲームワールド（GameWorldInner, GameWorld）

use super::{BossState, BulletWorld, EnemyWorld, ParticleWorld, PlayerState};
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
/// - `level`, `exp`     → set_player_level NIF（フェーズ3）
/// - `elapsed_seconds`  → set_elapsed_seconds NIF（フェーズ3）
/// - `boss.hp`          → set_boss_hp NIF（フェーズ4）
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
    /// 直近フレームの物理ステップ処理時間（ミリ秒）
    pub last_frame_time_ms: f64,
    /// ゲーム開始からの経過時間（秒）- Elixir から毎フレーム注入（スポーン計算用）
    pub elapsed_seconds:    f32,
    /// プレイヤーの最大 HP（HP バー計算用）
    pub player_max_hp:      f32,
    /// 現在の経験値 - Elixir から毎フレーム注入（武器ダメージ計算用）
    pub exp:                u32,
    /// 現在のレベル（1 始まり）- Elixir から毎フレーム注入（武器ダメージ計算用）
    pub level:              u32,
    /// 装備中の武器スロット（クールダウン管理のみ）
    pub weapon_slots:       Vec<WeaponSlot>,
    /// 1.2.9: ボスエネミー（boss.hp は Elixir から毎フレーム注入）
    pub boss:               Option<BossState>,
    /// 1.3.1: このフレームで発生したイベント（毎フレーム drain される）
    pub frame_events:       Vec<FrameEvent>,
    /// 1.7.5: レベルアップ時の武器選択肢（HUD 表示用）
    pub weapon_choices:     Vec<String>,
    /// 1.7.5: スコアポップアップ [(world_x, world_y, value, lifetime)]（描画用）
    pub score_popups:       Vec<(f32, f32, u32, f32)>,
    /// 1.10.7: 補間用 - 前フレームのプレイヤー位置
    pub prev_player_x:      f32,
    pub prev_player_y:      f32,
    /// 1.10.7: 補間用 - 前フレームの更新タイムスタンプ（ms）
    pub prev_tick_ms:       u64,
    /// 1.10.7: 補間用 - 現在フレームの更新タイムスタンプ（ms）
    pub curr_tick_ms:       u64,
}

impl GameWorldInner {
    /// レベルアップ処理を完了する（武器選択・スキップ共通）
    /// フェーズ3: level/level_up_pending の権威は Elixir 側に移行済み。
    /// weapon_choices のクリアのみ行う。level は Elixir から次フレームで注入される。
    pub fn complete_level_up(&mut self) {
        self.weapon_choices.clear();
    }

    /// 衝突判定用の Spatial Hash を再構築する（clone 不要）
    pub fn rebuild_collision(&mut self) {
        self.collision.dynamic.clear();
        self.enemies.alive
            .iter()
            .enumerate()
            .filter(|&(_, &is_alive)| is_alive)
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
