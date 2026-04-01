//! 窓層（The Shell）
//!
//! winit によるライフサイクル管理・ウィンドウ生成・入力取得。
//! render は描画専用、window がイベントループの所有権を持つ。

pub mod common;
mod desktop_loop;
pub(crate) mod platform;

pub use desktop_loop::run_desktop_loop;
