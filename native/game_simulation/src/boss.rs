//! Path: native/game_simulation/src/boss.rs
//! Summary: ボス種別の定数定義（Phase 3-A: BossKind enum を除去）
//!
//! 具体的なパラメータは entity_params::EntityParamTables に移行済み。

// ボス ID 定数は entity_params.rs で定義しているため、ここでは再 export のみ。
pub use crate::entity_params::{
    BOSS_ID_BAT_LORD, BOSS_ID_SLIME_KING, BOSS_ID_STONE_GOLEM,
};
