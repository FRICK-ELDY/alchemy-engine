//! Path: native/game_native/src/world/game_world.rs
//! Summary: ゲームワールド（GameWorldInner, GameWorld）

use super::{BossState, BulletWorld, EnemyWorld, ParticleWorld, PlayerState};
use game_core::item::ItemWorld;
use game_core::physics::rng::SimpleRng;
use game_core::physics::spatial_hash::CollisionWorld;
use game_core::weapon::WeaponSlot;
use std::sync::{Mutex, RwLock};

use super::FrameEvent;

/// ゲームワールド内部状態
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
    /// 1.1.13: 撃破スコア（敵 1 体 = 10 点）
    pub score:              u32,
    /// ゲーム開始からの経過時間（秒）
    pub elapsed_seconds:    f32,
    /// プレイヤーの最大 HP（HP バー計算用）
    pub player_max_hp:      f32,
    /// 1.1.14: 現在の経験値
    pub exp:                u32,
    /// 現在のレベル（1 始まり）
    pub level:              u32,
    /// レベルアップ待機フラグ（Elixir 側が武器選択を完了するまで true）
    pub level_up_pending:   bool,
    /// 装備中の武器スロット（最大 6 つ）
    pub weapon_slots:       Vec<WeaponSlot>,
    /// 1.2.9: ボスエネミー
    pub boss:               Option<BossState>,
    /// 1.3.1: このフレームで発生したイベント（毎フレーム drain される）
    pub frame_events:       Vec<FrameEvent>,
    /// 1.7.5: 描画スレッドからの UI アクション（Start/Retry/武器選択/Save/Load 等）
    /// ゲームループが取得して Elixir に送信する
    pub pending_ui_action:  Mutex<Option<String>>,
    /// 1.7.5: レベルアップ時の武器選択肢（level_up_pending が true のとき HUD に表示）
    pub weapon_choices:     Vec<String>,
    /// 1.7.5: スコアポップアップ [(world_x, world_y, value, lifetime)]
    pub score_popups:       Vec<(f32, f32, u32, f32)>,
    /// 1.7.5: 撃破数（ゲームオーバー画面等に表示）
    pub kill_count:         u32,
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
    pub(crate) fn complete_level_up(&mut self) {
        self.level += 1;
        self.level_up_pending = false;
        self.weapon_choices.clear();
    }

    /// 衝突判定用の Spatial Hash を再構築する（clone 不要）
    pub(crate) fn rebuild_collision(&mut self) {
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
