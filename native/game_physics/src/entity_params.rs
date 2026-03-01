//! Path: native/game_physics/src/entity_params.rs
//! Summary: 敵・武器・ボスの ID ベ�EスパラメータチE�Eブル
//!
//! Phase 3-A: `EntityParamTables` めE`GameWorldInner` に持たせることで
//! NIF 経由で外部から注入可能にする、E
//! `EntityParamTables::default()` は空チE�Eブルを返す、E
//! `set_entity_params` NIF が呼ばれるまで動作しなぁE��計、E

// ─── フォールバック定数 ──────────────────────────────────────────

/// params チE�Eブルに該彁EID が存在しなぁE��合�EチE��ォルト敵半征E
pub const DEFAULT_ENEMY_RADIUS: f32 = 16.0;

/// params チE�Eブルに該彁EID が存在しなぁE��合�EチE��ォルトパーチE��クル色
pub const DEFAULT_PARTICLE_COLOR: [f32; 4] = [1.0, 0.5, 0.1, 1.0];

/// params チE�Eブルに該彁EID が存在しなぁE��合�EチE��ォルチEwhip 封E��E
pub const DEFAULT_WHIP_RANGE: f32 = 200.0;

/// params チE�Eブルに該彁EID が存在しなぁE��合�EチE��ォルチEaura 半征E
pub const DEFAULT_AURA_RADIUS: f32 = 150.0;

/// params チE�Eブルに該彁EID が存在しなぁE��合�EチE��ォルチEchain 数
pub const DEFAULT_CHAIN_COUNT: usize = 1;

/// Chain 武器が�Eスに連鎖する最大距離
pub const CHAIN_BOSS_RANGE: f32 = 600.0;

// ─── EnemyParams ────────────────────────────────────────────────

/// 敵のパラメータ�E�Eind_id: u8 で参�E�E�E
#[derive(Clone, Debug)]
pub struct EnemyParams {
    pub max_hp:           f32,
    pub speed:            f32,
    pub radius:           f32,
    pub damage_per_sec:   f32,
    pub render_kind:      u8,
    /// パ�EチE��クル色 [r, g, b, a]
    pub particle_color:   [f32; 4],
    /// 障害物をすり抜けるか！Ehost など�E�E
    pub passes_obstacles: bool,
}

// ─── WeaponParams ───────────────────────────────────────────────

/// 武器の発封E��ターン
#[derive(Clone, Debug, PartialEq)]
pub enum FirePattern {
    /// 最近接敵に向けて扁E��に発封E��Eagic_wand 等！E
    Aimed,
    /// 固定方向に発封E��Exe: 上方向！E
    FixedUp,
    /// 全方向に発封E��Eross: 4方吁Eor 8方向！E
    Radial,
    /// 扁E��の直接判定（弾丸なし、whip�E�E
    Whip,
    /// プレイヤー周囲オーラ�E�Earlic�E�E
    Aura,
    /// 最近接敵に向けて貫通弾�E�Eireball�E�E
    Piercing,
    /// 連鎖電撁E��Eightning�E�E
    Chain,
}

/// 武器のパラメータ�E�Eind_id: u8 で参�E�E�E
#[derive(Clone, Debug)]
pub struct WeaponParams {
    pub cooldown:      f32,
    pub damage:        i32,
    pub as_u8:         u8,
    /// bullet_count_table: index=level (1-based)、Eone の場合�E固宁E1 発
    pub bullet_table:  Option<Vec<usize>>,
    /// 発封E��ターン
    pub fire_pattern:  FirePattern,
    /// 篁E���E�Ehip: 扁E��半征E��Aura: オーラ半征E��E
    pub range:         f32,
    /// 連鎖数�E�Ehain パターン用�E�E
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

    /// Whip の実効篁E��: base_range + (level - 1) * 20
    pub fn whip_range(&self, level: u32) -> f32 {
        self.range + (level as f32 - 1.0) * 20.0
    }

    /// Aura の実効半征E base_range + (level - 1) * 15
    pub fn aura_radius(&self, level: u32) -> f32 {
        self.range + (level as f32 - 1.0) * 15.0
    }

    /// Chain の実効連鎖数: base_chain_count + level / 2
    pub fn chain_count_for_level(&self, level: u32) -> usize {
        self.chain_count as usize + level as usize / 2
    }
}

// ─── BossParams ────────────────────────────────────────────────

/// ボスのパラメータ�E�Eind_id: u8 で参�E�E�E
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

/// NIF 経由で外部注入可能なエンチE��チE��パラメータチE�Eブル、E
/// `GameWorldInner` に保持し、`set_entity_params` NIF で上書きする、E
/// チE��ォルト�E空チE�Eブル。`set_entity_params` が呼ばれるまで動作しなぁE��E
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
        self.enemies.get(id as usize).map(|e| e.passes_obstacles).unwrap_or(false)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_tables() -> EntityParamTables {
        EntityParamTables {
            enemies: vec![
                EnemyParams {
                    max_hp: 30.0, speed: 80.0, radius: 20.0,
                    damage_per_sec: 20.0, render_kind: 1,
                    particle_color: [1.0, 0.5, 0.1, 1.0],
                    passes_obstacles: false,
                },
                EnemyParams {
                    max_hp: 15.0, speed: 160.0, radius: 12.0,
                    damage_per_sec: 10.0, render_kind: 2,
                    particle_color: [0.7, 0.2, 0.9, 1.0],
                    passes_obstacles: false,
                },
            ],
            weapons: vec![
                WeaponParams {
                    cooldown: 1.0, damage: 10, as_u8: 0,
                    bullet_table: Some(vec![0, 1, 1, 2, 2, 3, 3, 4, 4]),
                    fire_pattern: FirePattern::Aimed,
                    range: 0.0, chain_count: 0,
                },
            ],
            bosses: vec![
                BossParams {
                    max_hp: 1000.0, speed: 60.0, radius: 48.0,
                    damage_per_sec: 30.0, render_kind: 11,
                    special_interval: 5.0,
                },
            ],
        }
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
        // bullet_table = [0, 1, 1, 2, 2, 3, 3, 4, 4] (index 0 は未使用、E-based)
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
