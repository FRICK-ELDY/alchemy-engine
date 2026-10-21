//! OS 固有処理（Suspend/Resume 等）

#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
pub mod desktop;
