//! Path: native/game_render/src/window.rs
//! Summary: ウィンドウ生成・OS入力イベント・レンダーループ（旧 game_window）

use crate::{GameUiState, RenderFrame, Renderer};
use std::sync::Arc;
use winit::{
    application::ApplicationHandler,
    event::{DeviceEvent, DeviceId, ElementState, WindowEvent},
    event_loop::{ActiveEventLoop, EventLoop},
    keyboard::PhysicalKey,
    window::{CursorGrabMode, Window, WindowId},
};
pub use winit::keyboard::KeyCode;

#[cfg(target_os = "windows")]
use winit::platform::windows::EventLoopBuilderExtWindows;

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

pub trait RenderBridge: Send + 'static {
    fn next_frame(&self) -> RenderFrame;
    fn on_ui_action(&self, action: String);
    /// 生キーイベント。Elixir 側でキー→意味のマッピングを行う。
    fn on_raw_key(&self, key: KeyCode, state: KeyState);
    /// 生マウス移動量。Elixir 側で必要に応じて処理する。
    fn on_raw_mouse_motion(&self, dx: f32, dy: f32);
    /// フォーカス喪失。Elixir 側で押下状態をリセットする。
    fn on_focus_lost(&self);
}

pub fn run_render_loop<B: RenderBridge>(bridge: B, config: WindowConfig) -> Result<(), String> {
    let mut builder = EventLoop::builder();
    #[cfg(target_os = "windows")]
    builder.with_any_thread(true);

    let event_loop = builder
        .build()
        .map_err(|e| format!("event loop create failed: {e}"))?;
    let mut app = RenderApp::new(bridge, config);
    event_loop
        .run_app(&mut app)
        .map_err(|e| format!("event loop runtime failed: {e}"))
}

struct RenderApp<B: RenderBridge> {
    bridge: B,
    config: WindowConfig,
    window: Option<Arc<Window>>,
    renderer: Option<Renderer>,
    ui_state: GameUiState,
    /// マウスカーソルがウィンドウにキャプチャされているか
    cursor_grabbed: bool,
    /// Elixir 側の指示でグラブ解放した後、MouseInput による即時再グラブを抑制するカウンタ。
    /// 0 より大きい間は MouseInput::Pressed でのグラブを行わず、毎回デクリメントする。
    /// HUD ボタンのクリックが解放と同フレームで再グラブを引き起こす競合を防ぐ。
    /// フレームレートによっては同一フレーム内で複数の MouseInput が発火するため、
    /// bool ではなくカウンタで複数イベントを抑制する。
    suppress_grab_frames: u8,
}

impl<B: RenderBridge> RenderApp<B> {
    fn new(bridge: B, config: WindowConfig) -> Self {
        Self {
            bridge,
            config,
            window: None,
            renderer: None,
            ui_state: GameUiState::default(),
            cursor_grabbed: false,
            suppress_grab_frames: 0,
        }
    }

    /// カーソルのグラブ状態を切り替える。
    /// グラブ中: カーソル非表示・ウィンドウ内にロック
    /// 解放中: カーソル表示・自由に動かせる
    fn set_cursor_grabbed(&mut self, grabbed: bool) {
        let Some(window) = &self.window else { return };
        self.cursor_grabbed = grabbed;
        window.set_cursor_visible(!grabbed);
        if grabbed {
            // Windows では Locked が使えないため Confined を優先する
            let _ = window
                .set_cursor_grab(CursorGrabMode::Confined)
                .or_else(|_| window.set_cursor_grab(CursorGrabMode::Locked));
        } else {
            let _ = window.set_cursor_grab(CursorGrabMode::None);
        }
    }
}

impl<B: RenderBridge> ApplicationHandler for RenderApp<B> {
    fn device_event(&mut self, _event_loop: &ActiveEventLoop, _id: DeviceId, event: DeviceEvent) {
        // グラブ中のみマウス移動量を Elixir へ送信する
        if self.cursor_grabbed {
            if let DeviceEvent::MouseMotion { delta: (dx, dy) } = event {
                self.bridge.on_raw_mouse_motion(dx as f32, dy as f32);
            }
        }
    }

    fn resumed(&mut self, event_loop: &ActiveEventLoop) {
        if self.window.is_some() {
            return;
        }

        let window = Arc::new(
            event_loop
                .create_window(
                    Window::default_attributes()
                        .with_title(self.config.title.clone())
                        .with_inner_size(winit::dpi::LogicalSize::new(
                            self.config.width,
                            self.config.height,
                        )),
                )
                .expect("window creation failed"),
        );

        let renderer = pollster::block_on(Renderer::new(
            window.clone(),
            &self.config.renderer_init.atlas_png,
        ));
        self.window = Some(window.clone());
        self.renderer = Some(renderer);
        window.request_redraw();
    }

    fn window_event(&mut self, event_loop: &ActiveEventLoop, _id: WindowId, event: WindowEvent) {
        if let (Some(renderer), Some(window)) = (&mut self.renderer, &self.window) {
            if renderer.handle_window_event(window, &event) {
                window.request_redraw();
            }
        }

        match event {
            WindowEvent::CloseRequested => event_loop.exit(),
            WindowEvent::Focused(false) => {
                // フォーカスを失ったらカーソルを解放し、Elixir 側で押下状態をリセット
                if self.cursor_grabbed {
                    self.set_cursor_grabbed(false);
                }
                self.bridge.on_focus_lost();
            }
            // ウィンドウをクリックしたらカーソルをキャプチャ。
            // ただし Elixir 指示によるグラブ解放直後（suppress_grab_frames > 0）は再グラブしない。
            // これにより HUD ボタンのクリックが解放と同フレームで再グラブを引き起こす競合を防ぐ。
            WindowEvent::MouseInput {
                state: ElementState::Pressed,
                ..
            } => {
                if self.suppress_grab_frames > 0 {
                    self.suppress_grab_frames -= 1;
                } else if !self.cursor_grabbed {
                    self.set_cursor_grabbed(true);
                }
            }
            WindowEvent::KeyboardInput { event, .. } => {
                if event.repeat {
                    return;
                }
                if let PhysicalKey::Code(code) = event.physical_key {
                    let state = if event.state == ElementState::Pressed {
                        KeyState::Pressed
                    } else {
                        KeyState::Released
                    };
                    self.bridge.on_raw_key(code, state);
                }
            }
            WindowEvent::Resized(size) => {
                if let (Some(renderer), size) = (&mut self.renderer, (size.width, size.height)) {
                    if size.0 > 0 && size.1 > 0 {
                        renderer.resize(size.0, size.1);
                    }
                }
            }
            WindowEvent::RedrawRequested => {
                // フレームデータを取得し、カーソルグラブ要求を先に処理する（借用チェッカー対策）
                let frame = if self.renderer.is_some() {
                    Some(self.bridge.next_frame())
                } else {
                    None
                };
                if let Some(ref frame) = frame {
                    if let Some(grab) = frame.cursor_grab {
                        if grab != self.cursor_grabbed {
                            // Elixir 指示でグラブ解放する場合、直後の MouseInput による
                            // 即時再グラブを抑制する（HUD ボタンクリック競合対策）。
                            // 同一フレーム内で複数の MouseInput が発火する可能性があるため
                            // カウンタで複数イベントを抑制する。
                            if !grab {
                                self.suppress_grab_frames = 3;
                            }
                            self.set_cursor_grabbed(grab);
                        }
                    }
                }
                if let (Some(frame), Some(renderer), Some(window)) =
                    (frame, &mut self.renderer, &self.window)
                {
                    renderer.update_instances(&frame);
                    if let Some(action) = renderer.render(
                        window,
                        &frame.ui,
                        &frame.camera,
                        &frame.commands,
                        &mut self.ui_state,
                    ) {
                        self.bridge.on_ui_action(action);
                    }
                    window.request_redraw();
                }
            }
            _ => {}
        }
    }
}
