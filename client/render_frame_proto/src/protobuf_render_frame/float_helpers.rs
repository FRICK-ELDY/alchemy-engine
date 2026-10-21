//! repeated 数値フィールド向けの緩いデコード（0 埋め、alpha 既定 1.0）。
//! `f*` は色・UV（binary32）。`d3` は座標（binary64）。

pub(super) fn f2(v: &[f32]) -> [f32; 2] {
    [
        v.first().copied().unwrap_or(0.0),
        v.get(1).copied().unwrap_or(0.0),
    ]
}

pub(super) fn f4(v: &[f32]) -> [f32; 4] {
    [
        v.first().copied().unwrap_or(0.0),
        v.get(1).copied().unwrap_or(0.0),
        v.get(2).copied().unwrap_or(0.0),
        v.get(3).copied().unwrap_or(1.0),
    ]
}

pub(super) fn d3(v: &[f64]) -> [f64; 3] {
    [
        v.first().copied().unwrap_or(0.0),
        v.get(1).copied().unwrap_or(0.0),
        v.get(2).copied().unwrap_or(0.0),
    ]
}

pub(super) fn pad4(v: &[f32]) -> [f32; 4] {
    [
        v.first().copied().unwrap_or(0.0),
        v.get(1).copied().unwrap_or(0.0),
        v.get(2).copied().unwrap_or(0.0),
        v.get(3).copied().unwrap_or(0.0),
    ]
}
