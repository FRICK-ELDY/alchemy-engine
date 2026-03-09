//! Path: native/physics/src/world/render_snapshot.rs
//! Summary: P5-4 描画用エンティティスナップショットのダブルバッファ
//!
//! get_render_entities の O(n) コピーを削減するため、物理ステップ後に
//! 事前構築したバッファをスワップして返す。SoA からの構築は 1 フレームに 1 回のみ。

/// 描画用エンティティスナップショット（Atom なし・physics クレート内で完結）
/// boss は Elixir SSoT のため常に (:none, 0, 0, 0, 0)。nif 層で補完する。
#[derive(Clone, Default)]
pub struct RenderSnapshotBuffer {
    pub player: (f64, f64, u32, usize, usize),
    pub timers: (f64, f64),
    pub enemies: Vec<(f64, f64, u32)>,
    pub bullets: Vec<(f64, f64, u32)>,
    pub particles: Vec<(f64, f64, f64, f64, f64, f64, f64)>,
    pub items: Vec<(f64, f64, u32)>,
    pub obstacles: Vec<(f64, f64, f64, u32)>,
    pub score_popups: Vec<(f64, f64, u32, f64)>,
}
