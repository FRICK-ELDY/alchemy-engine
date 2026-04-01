//! 線形補間 (Lerp) ロジック
//!
//! サーバーの低頻度更新（20Hz）を描画タイミング（60Hz）に合わせて補間。

use crate::types::Vec2;

/// a と b を t (0.0..=1.0) で線形補間
#[inline]
pub fn lerp_vec2(a: Vec2, b: Vec2, t: f32) -> Vec2 {
    Vec2 {
        x: a.x + (b.x - a.x) * t,
        y: a.y + (b.y - a.y) * t,
    }
}

/// f32 の線形補間
#[inline]
pub fn lerp(a: f32, b: f32, t: f32) -> f32 {
    a + (b - a) * t
}
