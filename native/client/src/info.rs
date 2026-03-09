//! クライアント情報（OS, arch, family）取得。
//! std::env::consts のみ使用。winit 非依存。
//!
//! Windows, Linux, macOS, Android, iOS ほか、std が対応する全環境で動作。

use serde::Serialize;

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
