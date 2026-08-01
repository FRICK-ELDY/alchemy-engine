//! スナップショット保持（履歴キュー）
//!
//! 実体は `crate::interp::SnapshotInterpolator`（複数枚キュー + 描画遅延バッファ）。
//! 本モジュールは既存 API 互換の薄いエイリアスを残す。

pub use crate::interp::SnapshotInterpolator as Store;
