//! Path: native/physics/src/world/game_world.rs
//! Summary: ゲームワールド（GameWorldInner, GameWorld）

use super::{BulletWorld, EnemyWorld, ParticleWorld, PlayerState, SpecialEntitySnapshot};
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
/// - `player_hp_injected` / `player_invincible_timer_injected` → set_player_snapshot NIF
/// - `player.input_dx/dy` → set_player_input NIF
/// - `elapsed_seconds`  → set_elapsed_seconds NIF
/// - `boss.hp`          → set_entity_hp(:boss) NIF（Phase R-3）
/// - `boss.vx/vy`       → set_entity_velocity(:boss) NIF（Phase R-3）
/// - `boss.invincible`  → set_entity_flag(:boss, :invincible) NIF（Phase R-3）
/// - `params`           → set_entity_params NIF
/// - `map_width/height` → set_world_size NIF
/// - `weapon_slots_input` → set_weapon_slots NIF（入力専用、永続状態なし）
///
/// ## Phase R-3 以降のデッドフィールド
/// 以下のフィールドは HUD データが push_render_frame 経由で直接 RenderFrameBuffer に
/// 書き込まれるようになったため、Elixir からの注入 NIF が廃止された。
/// Rust 側の物理演算では参照されないが、get_hud_data / get_frame_metadata / get_full_game_state
/// NIF が後方互換のために参照する（常に初期値 0 を返す）。
/// - `score`, `kill_count` — 旧 set_hud_state NIF（廃止）
/// - `hud_level`, `hud_exp`, `hud_exp_to_next`, `hud_level_up_pending`, `hud_weapon_choices`
///   — 旧 set_hud_level_state NIF（廃止）
pub struct GameWorldInner {
    pub frame_id: u32,
    pub player: PlayerState,
    /// PlayerState SSoT 移行: contents から毎フレーム set_player_snapshot で注入。
    pub player_hp_injected: f32,
    pub player_invincible_timer_injected: f32,
    pub enemies: EnemyWorld,
    pub bullets: BulletWorld,
    pub particles: ParticleWorld,
    /// 1.2.4: アイテム
    pub items: ItemWorld,
    /// 磁石エフェクト残り時間（秒）
    pub magnet_timer: f32,
    pub rng: SimpleRng,
    pub collision: CollisionWorld,
    /// 1.5.2: 障害物クエリ用バッファ（毎フレーム再利用）
    pub obstacle_query_buf: Vec<usize>,
    /// 動的エンティティ（敵・弾丸）クエリ用バッファ（毎フレーム再利用、アロケーション回避）
    pub spatial_query_buf: Vec<usize>,
    /// 直近フレームの物理ステップ処理時間（ミリ秒）
    pub last_frame_time_ms: f64,
    /// ゲーム開始からの経過時間（秒）- Elixir から毎フレーム注入（スポーン計算用）
    pub elapsed_seconds: f32,
    /// プレイヤーの最大 HP（HP バー計算用）
    pub player_max_hp: f32,
    /// weapon_slots SSoT 移行（A案）: 入力専用バッファ。毎フレーム set_weapon_slots で上書きされ、
    /// physics_step で参照される。永続状態ではなく、cooldown は FrameEvent で Elixir に返す。
    pub weapon_slots_input: Vec<WeaponSlot>,
    /// Elixir SSoT 移行: 衝突用スナップショット（永続状態なし）
    /// 毎フレーム set_special_entity_snapshot NIF で注入される。
    pub special_entity_snapshot: Option<SpecialEntitySnapshot>,
    /// 1.3.1: このフレームで発生したイベント（毎フレーム drain される）
    pub frame_events: Vec<FrameEvent>,
    /// 1.7.5: スコアポップアップ [(world_x, world_y, value, lifetime)]（描画用）
    pub score_popups: Vec<(f32, f32, u32, f32)>,
    /// スコア（Phase R-3 以降デッドフィールド: push_render_frame の HudData に移行）
    pub score: u32,
    /// キル数（Phase R-3 以降デッドフィールド: push_render_frame の HudData に移行）
    pub kill_count: u32,
    /// 1.10.7: 補間用 - 前フレームのプレイヤー位置
    pub prev_player_x: f32,
    pub prev_player_y: f32,
    /// 1.10.7: 補間用 - 前フレームの更新タイムスタンプ（ms）
    pub prev_tick_ms: u64,
    /// 1.10.7: 補間用 - 現在フレームの更新タイムスタンプ（ms）
    pub curr_tick_ms: u64,
    /// Phase 3-A: エンティティパラメータテーブル（set_entity_params NIF で注入）
    pub params: EntityParamTables,
    /// R-P2: 敵接触ダメージ（kind_id → damage_this_frame）。毎フレーム set_enemy_damage_this_frame NIF で注入。
    pub enemy_damage_this_frame: Vec<f32>,
    /// Phase 3-A: マップサイズ（set_world_size NIF で注入）
    pub map_width: f32,
    pub map_height: f32,
    /// R-C1: 物理定数（set_world_params NIF で注入可能）。デフォルトは constants の値。
    pub player_speed: f32,
    pub bullet_speed: f32,
    pub bullet_lifetime: f32,
    /// R-I1: アイテム収集半径・磁石パラメータ（set_world_params で注入可能）
    pub collect_radius: f32,
    pub magnet_collect_radius: f32,
    pub magnet_duration: f32,
    pub magnet_speed: f32,
    /// R-S1: 敵スポーン距離（set_world_params で注入可能）。プレイヤー周囲 min〜max px の円周上
    pub spawn_min_dist: f32,
    pub spawn_max_dist: f32,
    /// Phase R-3 以降デッドフィールド: push_render_frame の HudData に移行済み。
    /// ゲームロジック・レンダリングパイプラインのいずれも参照しない。
    pub hud_level: u32,
    pub hud_exp: u32,
    pub hud_exp_to_next: u32,
    pub hud_level_up_pending: bool,
    pub hud_weapon_choices: Vec<String>,
}

impl GameWorldInner {
    /// 衝突判定用の Spatial Hash を再構築する（clone 不要）
    pub fn rebuild_collision(&mut self) {
        self.collision.dynamic.clear();
        self.enemies
            .alive
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
