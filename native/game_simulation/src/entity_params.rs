//! Path: native/game_simulation/src/entity_params.rs
//! Summary: 敵・武器・ボスの ID ベースパラメータテーブル
//!
//! Phase 3-A: `EntityParamTables` を `GameWorldInner` に持たせることで
//! NIF 経由で外部から注入可能にする。
//! `EntityParamTables::default()` は空テーブルを返す。
//! `set_entity_params` NIF が呼ばれるまで動作しない設計。

// ─── EnemyParams ────────────────────────────────────────────────

/// 敵のパラメータ（kind_id: u8 で参照）
#[derive(Clone, Debug)]
pub struct EnemyParams {
    pub max_hp:           f32,
    pub speed:            f32,
    pub radius:           f32,
    pub damage_per_sec:   f32,
    pub render_kind:      u8,
    /// パーティクル色 [r, g, b, a]
    pub particle_color:   [f32; 4],
    /// 障害物をすり抜けるか（Ghost など）
    pub passes_obstacles: bool,
}

// ─── WeaponParams ───────────────────────────────────────────────

/// 武器の発射パターン
#[derive(Clone, Debug, PartialEq)]
pub enum FirePattern {
    /// 最近接敵に向けて扇状に発射（magic_wand 等）
    Aimed,
    /// 固定方向に発射（axe: 上方向）
    FixedUp,
    /// 全方向に発射（cross: 4方向 or 8方向）
    Radial,
    /// 扇形の直接判定（弾丸なし、whip）
    Whip,
    /// プレイヤー周囲オーラ（garlic）
    Aura,
    /// 最近接敵に向けて貫通弾（fireball）
    Piercing,
    /// 連鎖電撃（lightning）
    Chain,
}

/// 武器のパラメータ（kind_id: u8 で参照）
#[derive(Clone, Debug)]
pub struct WeaponParams {
    pub cooldown:      f32,
    pub damage:        i32,
    pub as_u8:         u8,
    /// bullet_count_table: index=level (1-based)。None の場合は固定 1 発
    pub bullet_table:  Option<Vec<usize>>,
    /// 発射パターン
    pub fire_pattern:  FirePattern,
    /// 範囲（Whip: 扇形半径、Aura: オーラ半径）
    pub range:         f32,
    /// 連鎖数（Chain パターン用）
    pub chain_count:   u8,
}

impl WeaponParams {
    pub fn bullet_count(&self, level: u32) -> usize {
        let lv = level.clamp(1, 8) as usize;
        self.bullet_table
            .as_ref()
            .and_then(|t| t.get(lv).copied())
            .unwrap_or(1)
    }

    /// Whip の実効範囲: base_range + (level - 1) * 20
    pub fn whip_range(&self, level: u32) -> f32 {
        self.range + (level as f32 - 1.0) * 20.0
    }

    /// Aura の実効半径: base_range + (level - 1) * 15
    pub fn aura_radius(&self, level: u32) -> f32 {
        self.range + (level as f32 - 1.0) * 15.0
    }

    /// Chain の実効連鎖数: base_chain_count + level / 2
    pub fn chain_count_for_level(&self, level: u32) -> usize {
        self.chain_count as usize + level as usize / 2
    }
}

// ─── BossParams ────────────────────────────────────────────────

/// ボスのパラメータ（kind_id: u8 で参照）
#[derive(Clone, Debug)]
pub struct BossParams {
    pub max_hp:           f32,
    pub speed:            f32,
    pub radius:           f32,
    pub damage_per_sec:   f32,
    pub render_kind:      u8,
    pub special_interval: f32,
}

// ─── EntityParamTables ─────────────────────────────────────────

/// NIF 経由で外部注入可能なエンティティパラメータテーブル。
/// `GameWorldInner` に保持し、`set_entity_params` NIF で上書きする。
/// デフォルトは空テーブル。`set_entity_params` が呼ばれるまで動作しない。
#[derive(Clone, Debug)]
pub struct EntityParamTables {
    pub enemies: Vec<EnemyParams>,
    pub weapons: Vec<WeaponParams>,
    pub bosses:  Vec<BossParams>,
}

impl Default for EntityParamTables {
    fn default() -> Self {
        Self {
            enemies: vec![],
            weapons: vec![],
            bosses:  vec![],
        }
    }
}

impl EntityParamTables {
    pub fn get_enemy(&self, id: u8) -> &EnemyParams {
        self.enemies.get(id as usize).expect("Invalid enemy ID")
    }

    pub fn get_weapon(&self, id: u8) -> &WeaponParams {
        self.weapons.get(id as usize).expect("Invalid weapon ID")
    }

    pub fn get_boss(&self, id: u8) -> &BossParams {
        self.bosses.get(id as usize).expect("Invalid boss ID")
    }

    pub fn enemy_passes_obstacles(&self, id: u8) -> bool {
        self.enemies.get(id as usize).map(|e| e.passes_obstacles).unwrap_or(false)
    }
}
