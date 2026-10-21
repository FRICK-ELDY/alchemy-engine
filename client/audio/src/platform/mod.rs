//! target_os による音声出力の切り替え
//!
//! - desktop: rodio (CoreAudio / WASAPI / ALSA)
//! - web / android / ios: 将来実装

#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
pub mod desktop;

#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
pub use desktop::*;
