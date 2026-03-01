//! Path: native/game_core/src/constants.rs
//! Summary: 画面解像度・マップサイズ・物理定数などの定数定義

// Background clear color (dark purple)
#[allow(dead_code)]
pub const BG_R: f64 = 0.05;
#[allow(dead_code)]
pub const BG_G: f64 = 0.02;
#[allow(dead_code)]
pub const BG_B: f64 = 0.10;

// Window resolution
pub const SCREEN_WIDTH: f32 = 1280.0;
pub const SCREEN_HEIGHT: f32 = 720.0;

// Map size (1.2.5: camera scroll)
// Used by game_window binary; NIF lib uses fixed screen coordinates.
#[allow(dead_code)]
pub const MAP_WIDTH: f32 = 4096.0;
#[allow(dead_code)]
pub const MAP_HEIGHT: f32 = 4096.0;

// Camera lerp speed (1.2.5)
#[allow(dead_code)]
pub const CAMERA_LERP_SPEED: f32 = 5.0;

// Sprite / player size
pub const SPRITE_SIZE: f32 = 64.0;
pub const PLAYER_SIZE: f32 = SPRITE_SIZE;

// Movement
pub const PLAYER_SPEED: f32 = 200.0;

// Frame budget (used by lib.rs NIF; not all binaries reference it)
#[allow(dead_code)]
pub const FRAME_BUDGET_MS: f64 = 1000.0 / 60.0;

// Collision radii
pub const PLAYER_RADIUS: f32 = PLAYER_SIZE / 2.0;
pub const ENEMY_RADIUS: f32 = 20.0;
pub const BULLET_RADIUS: f32 = 6.0;

// Enemy separation: 敵同士が重ならないための押し出し半径・強さ
pub const ENEMY_SEPARATION_RADIUS: f32 = ENEMY_RADIUS * 2.0;
pub const ENEMY_SEPARATION_FORCE: f32 = 120.0;

// Combat
#[allow(dead_code)]
pub const ENEMY_DAMAGE_PER_SEC: f32 = 20.0;
pub const INVINCIBLE_DURATION: f32 = 0.5;
pub const WEAPON_COOLDOWN: f32 = 1.0;
pub const BULLET_SPEED: f32 = 400.0;
pub const BULLET_DAMAGE: i32 = 10;
pub const BULLET_LIFETIME: f32 = 3.0;

// Spatial hash cell size
pub const CELL_SIZE: f32 = 80.0;

/// パーティクル用 RNG シード（create_world / load_save_snapshot 等で使用）
pub const PARTICLE_RNG_SEED: u64 = 67890;

// Score popup display parameters (score_popups buffer)
/// スコアポップアップの Y 軸オフセット（エンティティ中心より上に表示）
pub const POPUP_Y_OFFSET: f32 = -20.0;
/// スコアポップアップの表示時間（秒）
pub const POPUP_LIFETIME: f32 = 0.8;

/// 武器の最近接敵探索半径（MagicWand / Fireball / Lightning 用）
#[allow(dead_code)] // lib で使用、bin (game_window) では未使用（main.rs 空間ハッシュ化で使用予定）
pub const WEAPON_SEARCH_RADIUS: f32 = SCREEN_WIDTH / 2.0;

// Enemy cap (used by game_window binary; not referenced by the NIF lib)
#[allow(dead_code)]
pub const MAX_ENEMIES: usize = 300;

// Wave-based spawn schedule: (start_secs, interval_secs, count_per_tick)
// 1.2.10: 難易度カーブを自然に感じられるよう調整
// Used by game_window binary; Elixir SpawnSystem handles this for the NIF lib.
#[allow(dead_code)]
pub const WAVES: &[(f32, f32, usize)] = &[
    (0.0, 4.0, 2),    //   0〜60s:  2体 / 4秒（チュートリアル: ゆっくり学習）
    (60.0, 2.5, 4),   //  60〜180s: 4体 / 2.5秒（ウォームアップ）
    (180.0, 1.5, 8),  // 180〜360s: 8体 / 1.5秒（本番: 3分〜6分）
    (360.0, 1.0, 12), // 360〜600s: 12体 / 1秒（激化: 6分〜10分）
    (600.0, 0.7, 18), // 600s〜:   18体 / 0.7秒（最終盤: 10分〜）
];
