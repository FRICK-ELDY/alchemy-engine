//! Path: native/game_nif/src/lib.rs
//! Summary: NIF エントリ・モジュール宣言・rustler::init のみ

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
    // フェーズ4: ボスイベント用アトム
    boss_spawn,
    boss_damaged,
    // Rust ゲームループ → Elixir 送信用
    frame_events,
    ui_action,
    // フェーズ5: 移動入力用アトム
    move_input,
}

mod lock_metrics;
mod nif;
mod render_bridge;
mod render_snapshot;

pub use game_audio::{AssetId, AssetLoader, AudioCommand, AudioCommandSender, AudioManager, start_audio_thread};
pub use game_physics::game_logic::{
    find_nearest_enemy, find_nearest_enemy_spatial,
    find_nearest_enemy_spatial_excluding,
};
pub use game_render::{BossHudInfo, GamePhase, HudData, RenderFrame};
pub use nif::{SaveSnapshot, WeaponSlotSave};
pub use game_physics::world::{
    BossState, BulletWorld, EnemyWorld, FrameEvent, GameLoopControl, GameWorld, GameWorldInner,
    ParticleWorld, PlayerState,
    BULLET_KIND_FIREBALL, BULLET_KIND_LIGHTNING, BULLET_KIND_NORMAL, BULLET_KIND_ROCK,
    BULLET_KIND_WHIP,
};

#[cfg(feature = "umbrella")]
rustler::init!("Elixir.GameEngine.NifBridge", load = nif::load);

#[cfg(not(feature = "umbrella"))]
rustler::init!("Elixir.App.NifBridge", load = nif::load);
