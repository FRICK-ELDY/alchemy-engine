//! Path: native/game_native/src/lib.rs
//! Summary: NIF エントリ・モジュール宣言・pub use・rustler::init のみ（スリム化済み）

pub use game_core::boss::BossKind;
pub use game_core::enemy::EnemyKind;

rustler::atoms! {
    ok,
    slime,
    bat,
    golem,
    // 武器種別アトム
    magic_wand,
    axe,
    cross,
    whip,
    fireball,
    lightning,
    // level_up 通知アトム
    level_up,
    no_change,
    // ボス種別アトム
    slime_king,
    bat_lord,
    stone_golem,
    // ゲーム状態アトム
    alive,
    dead,
    none,
    // イベントバス用アトム
    enemy_killed,
    player_damaged,
    level_up_event,
    item_pickup,
    boss_defeated,
    // Rust ゲームループ → Elixir 送信用
    frame_events,
    ui_action,
}

mod asset;
mod audio;
mod game_logic;
mod lock_metrics;
mod nif;
mod render_bridge;
mod render_snapshot;
mod world;

pub use asset::{AssetId, AssetLoader};
pub use audio::{start_audio_thread, AudioCommand, AudioCommandSender, AudioManager};
pub use game_logic::{
    find_nearest_enemy, find_nearest_enemy_excluding, find_nearest_enemy_spatial,
    find_nearest_enemy_spatial_excluding, run_physics_step_for_bench, update_chase_ai,
    update_chase_ai_simd,
};
pub use game_render::{BossHudInfo, GamePhase, HudData, RenderFrame};
pub use nif::{SaveSnapshot, WeaponSlotSave};
pub use world::{
    BossState, BulletWorld, EnemyWorld, FrameEvent, GameLoopControl, GameWorld, GameWorldInner,
    ParticleWorld, PlayerState,
    BULLET_KIND_FIREBALL, BULLET_KIND_LIGHTNING, BULLET_KIND_NORMAL, BULLET_KIND_ROCK,
    BULLET_KIND_WHIP,
};

// Umbrella 構成では GameEngine.NifBridge、既存構成では App.NifBridge として登録。
// umbrella feature が有効な場合は GameEngine.NifBridge を使用する。
#[cfg(feature = "umbrella")]
rustler::init!("Elixir.GameEngine.NifBridge", load = nif::load);

#[cfg(not(feature = "umbrella"))]
rustler::init!("Elixir.App.NifBridge", load = nif::load);
