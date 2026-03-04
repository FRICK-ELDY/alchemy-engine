//! Path: native/game_input/src/lib.rs
//! Summary: デスクトップ入力・ウィンドウ・イベントループ
//!
//! Phase 2: イベントループの所有権を game_render から移行。
//! game_render は描画専用、game_input は winit によるウィンドウ・入力取得を担当。

mod desktop_loop;

pub use desktop_loop::run_desktop_loop;
