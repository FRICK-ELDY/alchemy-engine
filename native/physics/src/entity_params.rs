//! Path: native/physics/src/entity_params.rs
//! Summary: 敵・武器・ボスの ID ベースパラメータテーブル
//!
//! Phase 3-A: `EntityParamTables` を `GameWorldInner` に持たせることで
//! NIF 経由で外部から注入可能にする。
//! `EntityParamTables::default()` は空テーブルを返す。
//! `set_entity_params` NIF が呼ばれるまで動作しない設計。

// ─── フォールバック定数 ──────────────────────────────────────────

/// params テーブルに該当 ID が存在しない場合のデフォルト敵半径
pub const DEFAULT_ENEMY_RADIUS: f32 = 16.0;

/// params テーブルに該当 ID が存在しない場合のデフォルトパーティクル色
pub const DEFAULT_PARTICLE_COLOR: [f32; 4] = [1.0, 0.5, 0.1, 1.0];

/// params テーブルに該当 ID が存在しない場合のデフォルト whip 射程
pub const DEFAULT_WHIP_RANGE: f32 = 200.0;

/// params テーブルに該当 ID が存在しない場合のデフォルト aura 半径
pub const DEFAULT_AURA_RADIUS: f32 = 150.0;

/// params テーブルに該当 ID が存在しない場合のデフォルト chain 数
pub const DEFAULT_CHAIN_COUNT: usize = 1;

// ─── P4-1: オプションの default オーバーライド ───────────────────

/// P4-1: set_entity_params の opts から注入可能なデフォルト値。
/// 指定時は Rust 定数より優先。未指定時は DEFAULT_* 定数を使用。
#[derive(Clone, Debug, Default)]
pub struct EntityParamDefaults {
    pub default_enemy_radius: Option<f32>,
    pub default_particle_color: Option<[f32; 4]>,
    pub default_whip_range: Option<f32>,
    pub default_aura_radius: Option<f32>,
    pub default_chain_count: Option<usize>,
}

// ─── EnemyParams ────────────────────────────────────────────────

/// 敵のパラメータ（kind_id: u8 で参照）
#[derive(Clone, Debug)]
pub struct EnemyParams {
    pub max_hp: f32,
    pub speed: f32,
    pub radius: f32,
    pub damage_per_sec: f32,
    pub render_kind: u8,
    /// パーティクル色 [r, g, b, a]
    pub particle_color: [f32; 4],
    /// 障害物をすり抜けるか（Ghost など）
    pub passes_obstacles: bool,
}

// ─── WeaponParams ───────────────────────────────────────────────

/// 武器の発射パターン
#[derive(Clone, Copy, Debug, PartialEq)]
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
    pub cooldown: f32,
    pub damage: i32,
    pub as_u8: u8,
    /// bullet_count_table: index=level (1-based)。None の場合は固定 1 発
    pub bullet_table: Option<Vec<usize>>,
    /// 発射パターン
    pub fire_pattern: FirePattern,
    /// 範囲（Whip: 扇形半径、Aura: オーラ半径）
    pub range: f32,
    /// 連鎖数（Chain パターン用）
    pub chain_count: u8,
    /// R-F1: Whip の level ごとの実効範囲。contents から注入必須。None/空の場合は 0.0
    pub whip_range_per_level: Option<Vec<f32>>,
    /// R-F1: Aura の level ごとの実効半径。contents から注入必須。None/空の場合は 0.0
    pub aura_radius_per_level: Option<Vec<f32>>,
    /// R-F1: Chain の level ごとの実効連鎖数。contents から注入必須。None/空の場合は 0
    pub chain_count_per_level: Option<Vec<usize>>,
    /// Aimed 弾の扇状間隔（rad）。contents から注入。0 の場合は扇状にならない。
    pub aimed_spread_rad: f32,
    /// Whip 扇形の半角（rad）。contents から注入。
    pub whip_half_angle_rad: f32,
    /// 武器エフェクト表示時間（秒）。Whip/Lightning 等。contents から注入。
    pub effect_lifetime_sec: f32,
    /// P2-1: ヒット時パーティクル色 [r, g, b, a]。contents から注入。None の場合は DEFAULT_PARTICLE_COLOR。
    pub hit_particle_color: Option<[f32; 4]>,
    /// P3-1: Radial 発射の方向数（4 or 8）の level ごとのテーブル。contents から注入。
    /// 推奨: 8 要素（level 1..8 に対応）。7 要素以下の場合、level 7 以上で index が
    /// 範囲外となり warn の上 4 にフォールバックする。未定義時は 4 で warn。
    pub radial_dir_count_per_level: Option<Vec<usize>>,
}

impl WeaponParams {
    pub fn bullet_count(&self, level: u32) -> usize {
        let lv = level.clamp(1, 8) as usize;
        self.bullet_table
            .as_ref()
            .and_then(|t| t.get(lv).copied())
            .unwrap_or(1)
    }

    /// Whip の実効範囲。R-F1: テーブルのみ。contents がテーブルを注入する。None/空の場合は 0.0
    /// level 9 以上は index 7 の値を常に使用（テーブル長 8 の上限）。
    pub fn whip_range(&self, level: u32) -> f32 {
        let idx = (level.clamp(1, 8) - 1) as usize;
        self.whip_range_per_level
            .as_ref()
            .and_then(|t| t.get(idx).copied())
            .unwrap_or(0.0)
    }

    /// Aura の実効半径。R-F1: テーブルのみ。contents がテーブルを注入する。None/空の場合は 0.0
    /// level 9 以上は index 7 の値を常に使用（テーブル長 8 の上限）。
    pub fn aura_radius(&self, level: u32) -> f32 {
        let idx = (level.clamp(1, 8) - 1) as usize;
        self.aura_radius_per_level
            .as_ref()
            .and_then(|t| t.get(idx).copied())
            .unwrap_or(0.0)
    }

    /// Chain の実効連鎖数。R-F1: テーブルのみ。contents がテーブルを注入する。None/空の場合は 0
    /// level 9 以上は index 7 の値を常に使用（テーブル長 8 の上限）。
    pub fn chain_count_for_level(&self, level: u32) -> usize {
        let idx = (level.clamp(1, 8) - 1) as usize;
        self.chain_count_per_level
            .as_ref()
            .and_then(|t| t.get(idx).copied())
            .unwrap_or(0)
    }

    /// P3-1: Radial 発射の方向数（4 or 8）。contents がテーブルを注入する。
    /// level 1..8 で index 0..7 を参照。level 9 以上は index 7 を使用。
    /// None/空の場合は 4 を返し warn（Radial 武器では contents が必ず渡すこと）。
    pub fn radial_dir_count(&self, level: u32) -> usize {
        let idx = (level.clamp(1, 8) - 1) as usize;
        match self
            .radial_dir_count_per_level
            .as_ref()
            .and_then(|t| t.get(idx).copied())
        {
            Some(n) if n == 4 || n == 8 => n,
            Some(n) => {
                log::warn!(
                    "radial_dir_count_per_level[{}]={} is invalid (must be 4 or 8), using 4",
                    idx,
                    n
                );
                4
            }
            None => {
                log::warn!(
                    "Radial weapon has no radial_dir_count_per_level — using 4. Define in contents."
                );
                4
            }
        }
    }
}

// ─── BossParams ────────────────────────────────────────────────

/// ボスのパラメータ（kind_id: u8 で参照）
#[derive(Clone, Debug)]
pub struct BossParams {
    pub max_hp: f32,
    pub speed: f32,
    pub radius: f32,
    pub damage_per_sec: f32,
    pub render_kind: u8,
    pub special_interval: f32,
}

// ─── EntityParamTables ─────────────────────────────────────────

/// NIF 経由で外部注入可能なエンティティパラメータテーブル。
/// `GameWorldInner` に保持し、`set_entity_params` NIF で上書きする。
/// デフォルトは空テーブル。`set_entity_params` が呼ばれるまで動作しない。
///
/// ## 武器テーブル注入の必須事項（新規コンテンツ追加時）
///
/// - **Whip パターン**: `whip_range_per_level` を必ず注入（1..8 要素のテーブル）。未注入だと範囲 0 でヒットしない。
/// - **Aura パターン**: `aura_radius_per_level` を必ず注入。未注入だと半径 0 でヒットしない。
/// - **Chain パターン**: `chain_count_per_level` を必ず注入。未注入だと連鎖数 0 で発動しない。
/// - **Aimed パターン**: `aimed_spread_rad` を注入（0 だと弾が一直線になる）。
/// - **Whip**: `whip_half_angle_rad`, `effect_lifetime_sec` も必要。
/// - **Chain**: `effect_lifetime_sec` も必要。
#[derive(Clone, Debug)]
pub struct EntityParamTables {
    pub enemies: Vec<EnemyParams>,
    pub weapons: Vec<WeaponParams>,
    pub bosses: Vec<BossParams>,
    /// P4-1: set_entity_params の opts から注入。未指定時は DEFAULT_* 定数を使用。
    pub defaults: EntityParamDefaults,
}

impl Default for EntityParamTables {
    fn default() -> Self {
        Self {
            enemies: Vec::new(),
            weapons: Vec::new(),
            bosses: Vec::new(),
            defaults: EntityParamDefaults::default(),
        }
    }
}

impl EntityParamTables {
    pub fn get_enemy(&self, id: u8) -> Option<&EnemyParams> {
        self.enemies.get(id as usize)
    }

    pub fn get_weapon(&self, id: u8) -> Option<&WeaponParams> {
        self.weapons.get(id as usize)
    }

    pub fn get_boss(&self, id: u8) -> Option<&BossParams> {
        self.bosses.get(id as usize)
    }

    pub fn enemy_passes_obstacles(&self, id: u8) -> bool {
        self.enemies
            .get(id as usize)
            .map(|e| e.passes_obstacles)
            .unwrap_or(false)
    }

    /// P4-1: 有効なデフォルト敵半径（opts 注入値を優先）
    pub fn effective_default_enemy_radius(&self) -> f32 {
        self.defaults
            .default_enemy_radius
            .unwrap_or(DEFAULT_ENEMY_RADIUS)
    }

    /// P4-1: 有効なデフォルトパーティクル色（opts 注入値を優先）
    pub fn effective_default_particle_color(&self) -> [f32; 4] {
        self.defaults
            .default_particle_color
            .unwrap_or(DEFAULT_PARTICLE_COLOR)
    }

    /// P4-1: 有効なデフォルト whip 射程（opts 注入値を優先）
    pub fn effective_default_whip_range(&self) -> f32 {
        self.defaults
            .default_whip_range
            .unwrap_or(DEFAULT_WHIP_RANGE)
    }

    /// P4-1: 有効なデフォルト aura 半径（opts 注入値を優先）
    pub fn effective_default_aura_radius(&self) -> f32 {
        self.defaults
            .default_aura_radius
            .unwrap_or(DEFAULT_AURA_RADIUS)
    }

    /// P4-1: 有効なデフォルト chain 数（opts 注入値を優先）
    pub fn effective_default_chain_count(&self) -> usize {
        self.defaults
            .default_chain_count
            .unwrap_or(DEFAULT_CHAIN_COUNT)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_tables() -> EntityParamTables {
        EntityParamTables {
            defaults: EntityParamDefaults::default(),
            enemies: vec![
                EnemyParams {
                    max_hp: 30.0,
                    speed: 80.0,
                    radius: 20.0,
                    damage_per_sec: 20.0,
                    render_kind: 1,
                    particle_color: [1.0, 0.5, 0.1, 1.0],
                    passes_obstacles: false,
                },
                EnemyParams {
                    max_hp: 15.0,
                    speed: 160.0,
                    radius: 12.0,
                    damage_per_sec: 10.0,
                    render_kind: 2,
                    particle_color: [0.7, 0.2, 0.9, 1.0],
                    passes_obstacles: false,
                },
            ],
            weapons: vec![WeaponParams {
                cooldown: 1.0,
                damage: 10,
                as_u8: 0,
                bullet_table: Some(vec![0, 1, 1, 2, 2, 3, 3, 4, 4]),
                fire_pattern: FirePattern::Aimed,
                range: 0.0,
                chain_count: 0,
                whip_range_per_level: None,
                aura_radius_per_level: None,
                chain_count_per_level: None,
                aimed_spread_rad: 0.0,
                whip_half_angle_rad: 0.0,
                effect_lifetime_sec: 0.0,
                hit_particle_color: None,
                radial_dir_count_per_level: None,
            }],
            bosses: vec![BossParams {
                max_hp: 1000.0,
                speed: 60.0,
                radius: 48.0,
                damage_per_sec: 30.0,
                render_kind: 11,
                special_interval: 5.0,
            }],
        }
    }

    #[test]
    fn effective_defaults_use_constants_when_no_opts() {
        let tables = EntityParamTables::default();
        assert!((tables.effective_default_enemy_radius() - DEFAULT_ENEMY_RADIUS).abs() < 0.001);
        assert_eq!(tables.effective_default_chain_count(), DEFAULT_CHAIN_COUNT);
    }

    #[test]
    fn get_enemy_returns_correct_params() {
        let tables = make_tables();
        let ep = tables.get_enemy(0).expect("enemy 0 should exist");
        assert!((ep.max_hp - 30.0).abs() < 0.001);
        assert!((ep.speed - 80.0).abs() < 0.001);
    }

    #[test]
    fn get_weapon_returns_correct_params() {
        let tables = make_tables();
        let wp = tables.get_weapon(0).expect("weapon 0 should exist");
        assert_eq!(wp.damage, 10);
        assert_eq!(wp.fire_pattern, FirePattern::Aimed);
    }

    #[test]
    fn get_boss_returns_correct_params() {
        let tables = make_tables();
        let bp = tables.get_boss(0).expect("boss 0 should exist");
        assert!((bp.max_hp - 1000.0).abs() < 0.001);
    }

    #[test]
    fn get_enemy_returns_none_for_invalid_id() {
        let tables = make_tables();
        assert!(tables.get_enemy(99).is_none());
    }

    #[test]
    fn weapon_bullet_count_by_level() {
        let tables = make_tables();
        let wp = tables.get_weapon(0).expect("weapon 0 should exist");
        // bullet_table = [0, 1, 1, 2, 2, 3, 3, 4, 4] (index 0 は未使用、1-based)
        assert_eq!(wp.bullet_count(1), 1);
        assert_eq!(wp.bullet_count(4), 2);
        assert_eq!(wp.bullet_count(8), 4);
    }

    #[test]
    fn default_tables_are_empty() {
        let tables = EntityParamTables::default();
        assert!(tables.enemies.is_empty());
        assert!(tables.weapons.is_empty());
        assert!(tables.bosses.is_empty());
    }

    #[test]
    fn enemy_passes_obstacles_false_for_unknown_id() {
        let tables = EntityParamTables::default();
        assert!(!tables.enemy_passes_obstacles(0));
    }
}
