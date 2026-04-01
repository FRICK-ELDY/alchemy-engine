//! ランタイム固有の初期化

#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
pub mod desktop;

#[cfg(target_os = "android")]
pub mod android;
