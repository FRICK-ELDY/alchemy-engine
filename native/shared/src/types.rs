//! #[repr(C)] 構造体（Elixir との共通規格）
//!
//! Zero-Copy のため bytemuck::Pod + Zeroable を導出。
//! 既存の DrawCommand, RenderFrame 等は段階的に移行予定。

use bytemuck::{Pod, Zeroable};

/// 2D ベクトル（Elixir と共有）
#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq, Pod, Zeroable)]
pub struct Vec2 {
    pub x: f32,
    pub y: f32,
}

impl Vec2 {
    pub const ZERO: Self = Self { x: 0.0, y: 0.0 };

    pub fn new(x: f32, y: f32) -> Self {
        Self { x, y }
    }
}

/// タイムスタンプ付きスナップショットのヘッダ（将来の拡張用）
#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq, Pod, Zeroable)]
pub struct SnapshotHeader {
    pub timestamp_ms: u64,
    pub sequence: u32,
}
