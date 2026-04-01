//! target_os による Surface 生成の切り替え

#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
pub mod desktop;

#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
pub use desktop::*;
