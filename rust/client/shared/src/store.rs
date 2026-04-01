//! スナップショット保持（過去と現在）
//!
//! サーバーからの更新を保持し、補間用の過去・現在ペアを管理。
//! 詳細な実装は network 連携後に追加予定。

/// スナップショットストア（スケルトン）
pub struct Store {
    _placeholder: (),
}

impl Store {
    pub fn new() -> Self {
        Self { _placeholder: () }
    }
}

impl Default for Store {
    fn default() -> Self {
        Self::new()
    }
}
