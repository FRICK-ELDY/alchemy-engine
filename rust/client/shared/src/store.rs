//! スナップショット保持（過去と現在）
//!
//! 実体は `crate::interp::SnapshotInterpolator`（描画遅延バッファ付き）。
//! 本モジュールは既存 API 互換の薄いエイリアスを残す。

pub use crate::interp::SnapshotInterpolator as Store;
