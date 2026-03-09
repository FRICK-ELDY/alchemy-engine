//! #[repr(C)] 構造体（Elixir との共通規格）
//!
//! Zero-Copy のため bytemuck::Pod + Zeroable を導出。
//! 既存の DrawCommand, RenderFrame 等は段階的に移行予定。

use bytemuck::{Pod, Zeroable};
use serde::Serialize;

/// クライアント情報（OS, arch, family）。
/// network 経由で Elixir に送信。
#[derive(Debug, Clone, Serialize)]
pub struct ClientInfo {
    /// OS 名。例: "windows", "linux", "macos", "android", "ios"
    pub os: &'static str,
    /// アーキテクチャ。例: "x86_64", "aarch64", "arm"
    pub arch: &'static str,
    /// ファミリ。例: "windows", "unix"
    pub family: &'static str,
}

impl ClientInfo {
    /// 現在のクライアント情報を返す。
    pub fn current() -> Self {
        Self {
            os: std::env::consts::OS,
            arch: std::env::consts::ARCH,
            family: std::env::consts::FAMILY,
        }
    }
}

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
/// Pod/Zeroable のため、パディングを明示的に埋める。
#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq, Pod, Zeroable)]
pub struct SnapshotHeader {
    pub timestamp_ms: u64,
    pub sequence: u32,
    pub _pad: [u8; 4],
}
