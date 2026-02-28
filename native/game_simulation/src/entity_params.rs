//! Path: native/game_core/src/entity_params.rs
//! Summary: 敵・武器・ボスの ID ベースパラメータテーブル
//!
//! 1.4.7: EnemyKind / WeaponKind / BossKind の enum を増やさずに、
//! u8 ID でパラメータを参照するテーブルを提供する。

/// 敵のパラメータ（ID で参照）
#[derive(Clone, Copy, Debug)]
pub struct EnemyParams {
    pub max_hp:       f32,
    pub speed:        f32,
    pub radius:       f32,
    pub exp_reward:   u32,
    pub damage_per_sec: f32,
    pub render_kind:  u8,
    /// パーティクル色 [r, g, b, a]
    pub particle_color: [f32; 4],
}

/// ヴァンサバの敵 ID: 0=Slime, 1=Bat, 2=Golem, 3=Skeleton, 4=Ghost（壁すり抜け）
pub const ENEMY_ID_SLIME: u8 = 0;
pub const ENEMY_ID_BAT:   u8 = 1;
pub const ENEMY_ID_GOLEM: u8 = 2;
pub const ENEMY_ID_SKELETON: u8 = 3;
pub const ENEMY_ID_GHOST: u8 = 4;

static ENEMY_TABLE: [EnemyParams; 5] = [
    EnemyParams { max_hp: 30.0,   speed: 80.0,  radius: 20.0, exp_reward: 5,  damage_per_sec: 20.0, render_kind: 1, particle_color: [1.0, 0.5, 0.1, 1.0] },   // Slime
    EnemyParams { max_hp: 15.0,   speed: 160.0, radius: 12.0, exp_reward: 3,  damage_per_sec: 10.0, render_kind: 2, particle_color: [0.7, 0.2, 0.9, 1.0] },   // Bat
    EnemyParams { max_hp: 150.0,  speed: 40.0,  radius: 32.0, exp_reward: 20, damage_per_sec: 40.0, render_kind: 3, particle_color: [0.6, 0.6, 0.6, 1.0] },   // Golem
    EnemyParams { max_hp: 60.0,   speed: 60.0,  radius: 22.0, exp_reward: 10, damage_per_sec: 15.0, render_kind: 5, particle_color: [0.9, 0.85, 0.7, 1.0] },  // Skeleton（高HP）
    EnemyParams { max_hp: 40.0,   speed: 100.0, radius: 16.0, exp_reward: 8,  damage_per_sec: 12.0, render_kind: 4, particle_color: [0.5, 0.5, 1.0, 0.8] },   // Ghost（壁すり抜け）
];

impl EnemyParams {
    pub fn get(id: u8) -> &'static EnemyParams {
        ENEMY_TABLE.get(id as usize).expect("Invalid enemy ID")
    }

    /// Ghost は障害物をすり抜ける（1.5.2）
    pub fn passes_through_obstacles(id: u8) -> bool {
        id == ENEMY_ID_GHOST
    }
}

// ─── WeaponParams ───────────────────────────────────────────────

/// 武器のパラメータ（ID で参照）
#[derive(Clone, Copy, Debug)]
pub struct WeaponParams {
    pub cooldown:     f32,
    pub damage:       i32,
    pub as_u8:        u8,
    pub name:         &'static str,
    /// bullet_count_table: [0]=未使用, [1..8]=Lv1..Lv8 の弾数。None の場合は固定 1 発
    pub bullet_table: Option<&'static [usize]>,
}

/// Whip の範囲: 120 + (level - 1) * 20
pub fn whip_range(_weapon_id: u8, level: u32) -> f32 {
    120.0 + (level as f32 - 1.0) * 20.0
}

/// Lightning のチェーン数: 2 + level / 2
pub fn lightning_chain_count(_weapon_id: u8, level: u32) -> usize {
    2 + level as usize / 2
}

pub const WEAPON_ID_MAGIC_WAND: u8 = 0;
pub const WEAPON_ID_AXE:       u8 = 1;
pub const WEAPON_ID_CROSS:     u8 = 2;
pub const WEAPON_ID_WHIP:      u8 = 3;
pub const WEAPON_ID_FIREBALL:  u8 = 4;
pub const WEAPON_ID_LIGHTNING: u8 = 5;
pub const WEAPON_ID_GARLIC:    u8 = 6;

static MW_TABLE: [usize; 9] = [0, 1, 1, 2, 2, 3, 3, 4, 4];
static CROSS_TABLE: [usize; 9] = [0, 4, 4, 4, 8, 8, 8, 8, 8];

/// Garlic のオーラ半径（px）: 80 + (level - 1) * 15
pub fn garlic_radius(_weapon_id: u8, level: u32) -> f32 {
    80.0 + (level as f32 - 1.0) * 15.0
}

static WEAPON_TABLE: [WeaponParams; 7] = [
    WeaponParams { cooldown: 1.0,  damage: 10, as_u8: 0, name: "magic_wand", bullet_table: Some(&MW_TABLE) },
    WeaponParams { cooldown: 1.5,  damage: 25, as_u8: 1, name: "axe",        bullet_table: None },
    WeaponParams { cooldown: 2.0,  damage: 15, as_u8: 2, name: "cross",      bullet_table: Some(&CROSS_TABLE) },
    WeaponParams { cooldown: 1.0,  damage: 30, as_u8: 3, name: "whip",       bullet_table: None },
    WeaponParams { cooldown: 1.0,  damage: 20, as_u8: 4, name: "fireball",   bullet_table: None },
    WeaponParams { cooldown: 1.0,  damage: 15, as_u8: 5, name: "lightning",  bullet_table: None },
    WeaponParams { cooldown: 0.2,  damage: 1,  as_u8: 6, name: "garlic",     bullet_table: None },
];

impl WeaponParams {
    pub fn get(id: u8) -> &'static WeaponParams {
        WEAPON_TABLE.get(id as usize).expect("Invalid weapon ID")
    }

    pub fn bullet_count(&self, level: u32) -> usize {
        let lv = level.clamp(1, 8) as usize;
        self.bullet_table
            .and_then(|t| t.get(lv).copied())
            .unwrap_or(1)
    }
}

// ─── BossParams ────────────────────────────────────────────────

#[derive(Clone, Copy, Debug)]
pub struct BossParams {
    pub max_hp:           f32,
    pub speed:            f32,
    pub radius:           f32,
    pub exp_reward:       u32,
    pub damage_per_sec:   f32,
    pub render_kind:      u8,
    pub special_interval: f32,
    /// HUD 表示用のボス名
    pub name:             &'static str,
}

pub const BOSS_ID_SLIME_KING:  u8 = 0;
pub const BOSS_ID_BAT_LORD:    u8 = 1;
pub const BOSS_ID_STONE_GOLEM: u8 = 2;

static BOSS_TABLE: [BossParams; 3] = [
    BossParams { max_hp: 1000.0, speed: 60.0,  radius: 48.0, exp_reward: 200, damage_per_sec: 30.0, render_kind: 11, special_interval: 5.0, name: "Slime King" },
    BossParams { max_hp: 2000.0, speed: 200.0, radius: 48.0, exp_reward: 400, damage_per_sec: 50.0, render_kind: 12, special_interval: 4.0, name: "Bat Lord" },
    BossParams { max_hp: 5000.0, speed: 30.0,  radius: 64.0, exp_reward: 800, damage_per_sec: 80.0, render_kind: 13, special_interval: 6.0, name: "Stone Golem" },
];

impl BossParams {
    pub fn get(id: u8) -> &'static BossParams {
        BOSS_TABLE.get(id as usize).expect("Invalid boss ID")
    }
}
