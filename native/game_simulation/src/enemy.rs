//! Path: native/game_simulation/src/enemy.rs
//! Summary: 敵種別の定数定義（Phase 3-A: EnemyKind enum を除去）
//!
//! 具体的なパラメータは entity_params::EntityParamTables に移行済み。
//! このファイルは後方互換のために残す（#[allow(dead_code)]）。

// 敵 ID 定数は entity_params.rs で定義しているため、ここでは再 export のみ。
pub use crate::entity_params::{
    ENEMY_ID_BAT, ENEMY_ID_GHOST, ENEMY_ID_GOLEM, ENEMY_ID_SKELETON, ENEMY_ID_SLIME,
};
