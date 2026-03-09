//! Path: native/physics/src/world/game_world.rs
//! Summary: ゲームワールド（GameWorldInner, GameWorld）

use super::{
    BulletWorld, EnemyWorld, ParticleWorld, PlayerState, RenderSnapshotBuffer,
    SpecialEntitySnapshot,
};
use crate::physics::entity_params::EntityParamTables;
use crate::physics::item::ItemWorld;
use crate::physics::physics::rng::SimpleRng;
use crate::physics::physics::spatial_hash::CollisionWorld;
use crate::physics::weapon::WeaponSlot;
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
    /// P2-2: パーティクル重力（set_world_params で注入可能）。未注入時 200.0
    pub particle_gravity: f32,
    /// P2-3: 弾丸衝突クエリ半径（set_world_params で注入可能）。BULLET_RADIUS + 敵最大半径
    pub bullet_query_radius: f32,
    /// P2-3: マップ外判定マージン（set_world_params で注入可能）
    pub map_margin: f32,
    /// P2-3: Chain 武器がボスに連鎖する最大距離（set_world_params で注入可能）
    pub chain_boss_range: f32,
    /// Phase R-3 以降デッドフィールド: push_render_frame の HudData に移行済み。
    /// ゲームロジック・レンダリングパイプラインのいずれも参照しない。
    pub hud_level: u32,
    pub hud_exp: u32,
    pub hud_exp_to_next: u32,
    pub hud_level_up_pending: bool,
    pub hud_weapon_choices: Vec<String>,
    /// P5-4: 描画用ダブルバッファ。物理ステップ後に fill し、get_render_entities で返す。
    pub render_buffers: [RenderSnapshotBuffer; 2],
    /// P5-4: どのバッファを「フロント」（get_render_entities で返す側）とするか。0 または 1。
    pub render_front: usize,
}

impl GameWorldInner {
    /// P5-4: 描画用ダブルバッファを更新。物理ステップ後に呼ぶ。
    /// バックバッファに SoA からデータを構築し、フロントをスワップする。
    pub fn fill_render_snapshot_back_and_swap(&mut self) {
        let back = 1 - self.render_front;
        let buf = &mut self.render_buffers[back];

        buf.player = (
            self.player.x as f64,
            self.player.y as f64,
            self.frame_id,
            self.enemies.count,
            self.bullets.count,
        );
        buf.timers = (
            self.magnet_timer as f64,
            self.player_invincible_timer_injected as f64,
        );

        buf.enemies.clear();
        buf.enemies.reserve(self.enemies.count);
        for i in 0..self.enemies.len() {
            if self.enemies.alive[i] == 0 {
                continue;
            }
            let kind_id = self
                .params
                .enemies
                .get(self.enemies.kind_ids[i] as usize)
                .map(|ep| ep.render_kind as u32)
                .unwrap_or(1);
            buf.enemies.push((
                self.enemies.positions_x[i] as f64,
                self.enemies.positions_y[i] as f64,
                kind_id,
            ));
        }

        buf.bullets.clear();
        buf.bullets.reserve(self.bullets.count);
        for i in 0..self.bullets.len() {
            if !self.bullets.alive[i] {
                continue;
            }
            buf.bullets.push((
                self.bullets.positions_x[i] as f64,
                self.bullets.positions_y[i] as f64,
                self.bullets.render_kind[i] as u32,
            ));
        }

        buf.particles.clear();
        buf.particles.reserve(self.particles.count);
        for i in 0..self.particles.len() {
            if !self.particles.alive[i] {
                continue;
            }
            let alpha = (self.particles.lifetime[i] / self.particles.max_lifetime[i])
                .clamp(0.0, 1.0) as f64;
            let c = self.particles.color[i];
            buf.particles.push((
                self.particles.positions_x[i] as f64,
                self.particles.positions_y[i] as f64,
                c[0] as f64,
                c[1] as f64,
                c[2] as f64,
                alpha,
                self.particles.size[i] as f64,
            ));
        }

        buf.items.clear();
        buf.items.reserve(self.items.count);
        for i in 0..self.items.len() {
            if !self.items.alive[i] {
                continue;
            }
            buf.items.push((
                self.items.positions_x[i] as f64,
                self.items.positions_y[i] as f64,
                self.items.kinds[i].render_kind() as u32,
            ));
        }

        buf.obstacles.clear();
        buf.obstacles.reserve(self.collision.obstacles.len());
        for o in &self.collision.obstacles {
            buf.obstacles
                .push((o.x as f64, o.y as f64, o.radius as f64, o.kind as u32));
        }

        buf.score_popups.clear();
        buf.score_popups.reserve(self.score_popups.len());
        for &(x, y, v, lt) in &self.score_popups {
            buf.score_popups.push((x as f64, y as f64, v, lt as f64));
        }

        self.render_front = back;
    }

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

impl rustler::Resource for GameWorld {}

impl rustler::Resource for super::game_loop_control::GameLoopControl {}
