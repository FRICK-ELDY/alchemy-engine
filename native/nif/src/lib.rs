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
    // フェーズ5: 移動入力用アトム（Elixir InputHandler が raw_key から生成）
    move_input,
    // 入力イベント用アトム
    mouse_delta,
    sprint,
    key_pressed,
    escape,
    // 生入力イベント（デバイス抽象化設計）
    raw_key,
    raw_mouse_motion,
    focus_lost,
    pressed,
    released,
    unknown,
    // カーソルグラブ制御アトム
    grab,
    release,
    // Phase R-3: 汎用エンティティ操作 NIF 用アトム
    boss,
    enemy,
    invincible,
    // Phase 3: VR 入力イベント
    head_pose,
    controller_pose,
    controller_button,
    tracker_pose,
    left,
    right,
    trigger,
    grip,
    thumbstick,
    // a,b,x,y は raw_key（キーボード）と controller_button（VR コントローラー）で共通。
    // イベント種別で区別されるため混同しない。
    a,
    b,
    x,
    y,
    menu,
    system,
    // VR イベント用（map キー）
    position,
    orientation,
    timestamp,
    velocity,
}

mod key_map;
mod lock_metrics;
mod nif;
mod render_bridge;
mod render_frame_buffer;

#[cfg(feature = "xr")]
mod xr_bridge;

pub use audio::{
    start_audio_thread, AssetId, AssetLoader, AudioCommand, AudioCommandSender, AudioManager,
};
pub use nif::{SaveSnapshot, WeaponSlotSave};
pub use physics::game_logic::{
    find_nearest_enemy, find_nearest_enemy_spatial, find_nearest_enemy_spatial_excluding,
};
pub use physics::world::{
    BossState, BulletWorld, EnemyWorld, FrameEvent, GameLoopControl, GameWorld, GameWorldInner,
    ParticleWorld, PlayerState, BULLET_KIND_FIREBALL, BULLET_KIND_LIGHTNING, BULLET_KIND_NORMAL,
    BULLET_KIND_ROCK, BULLET_KIND_WHIP,
};
pub use render::RenderFrame;

#[cfg(feature = "umbrella")]
rustler::init!("Elixir.Core.NifBridge", load = nif::load);

#[cfg(not(feature = "umbrella"))]
rustler::init!("Elixir.App.NifBridge", load = nif::load);
