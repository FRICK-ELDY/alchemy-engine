//! Path: native/game_render/src/window.rs
//! Summary: RenderBridge トレイト・ウィンドウ設定型
//!
//! Phase 2: イベントループは game_input に移行。game_render は描画専用。
//! このモジュールはトレイトと型定義のみを提供する。

pub use winit::keyboard::KeyCode;

#[derive(Clone)]
pub struct RendererInit {
    pub atlas_png: Vec<u8>,
}

pub struct WindowConfig {
    pub title: String,
    pub width: u32,
    pub height: u32,
    pub renderer_init: RendererInit,
}

/// キー状態（押下/解放）
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum KeyState {
    Pressed,
    Released,
}

/// イベントループ（game_input）が呼び出すブリッジトレイト。
/// 描画フレーム取得・入力イベント・UI アクションのコールバックを定義する。
pub trait RenderBridge: Send + 'static {
    fn next_frame(&self) -> crate::RenderFrame;
    fn on_ui_action(&self, action: String);
    fn on_raw_key(&self, key: KeyCode, state: KeyState);
    fn on_raw_mouse_motion(&self, dx: f32, dy: f32);
    fn on_focus_lost(&self);
}
