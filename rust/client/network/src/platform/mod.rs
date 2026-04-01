//! 通信方式の切り替え（target_os / target_family）

#[cfg(not(target_family = "wasm"))]
mod desktop;

#[cfg(target_family = "wasm")]
mod web;

#[cfg(not(target_family = "wasm"))]
pub use desktop::ClientSession;

#[cfg(target_family = "wasm")]
pub use web::ClientSession;
