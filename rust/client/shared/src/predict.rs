//! 入力予測ロジック（レイテンシ対策）
//!
//! クライアント側で入力のクライアント予測を行う。
//! 詳細な実装は network 連携後に追加予定。

use crate::types::Vec2;

/// 入力予測（スケルトン）
/// 現時点では入力をそのまま返す
#[inline]
pub fn predict_input(current: Vec2, _delta_ms: f32) -> Vec2 {
    current
}
