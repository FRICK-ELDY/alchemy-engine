//! repeated float フィールド向けの緩いデコード（0 埋め、alpha 既定 1.0）。

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

pub(super) fn f3(v: &[f32]) -> [f32; 3] {
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
