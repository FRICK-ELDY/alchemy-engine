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

pub trait RenderBridge: Send + 'static {
    fn next_frame(&self) -> RenderFrame;
    fn on_move_input(&self, dx: f32, dy: f32);
    fn on_ui_action(&self, action: String);
    fn on_mouse_delta(&self, dx: f32, dy: f32);
    fn on_sprint(&self, pressed: bool);
    /// キー押下を Elixir へ通知する。
    /// どのキーを転送するかは呼び出し側（`RenderApp`）が決定する。
    /// 現在は `Escape` のみ転送している。
    fn on_key_pressed(&self, key: KeyCode);
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
    move_up: bool,
    move_down: bool,
    move_left: bool,
    move_right: bool,
    sprint: bool,
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
            move_up: false,
            move_down: false,
            move_left: false,
            move_right: false,
            sprint: false,
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

    fn set_move_key(&mut self, key: KeyCode, pressed: bool) -> bool {
        let target = match key {
            KeyCode::KeyW | KeyCode::ArrowUp => &mut self.move_up,
            KeyCode::KeyS | KeyCode::ArrowDown => &mut self.move_down,
            KeyCode::KeyA | KeyCode::ArrowLeft => &mut self.move_left,
            KeyCode::KeyD | KeyCode::ArrowRight => &mut self.move_right,
            _ => return false,
        };
        if *target == pressed {
            return false;
        }
        *target = pressed;
        true
    }

    fn clear_move_keys(&mut self) -> bool {
        let had_pressed =
            self.move_up || self.move_down || self.move_left || self.move_right || self.sprint;
        self.move_up = false;
        self.move_down = false;
        self.move_left = false;
        self.move_right = false;
        if self.sprint {
            self.sprint = false;
            self.bridge.on_sprint(false);
        }
        had_pressed
    }

    fn sync_player_input(&self) {
        let dx = (self.move_right as i8 - self.move_left as i8) as f32;
        let dy = (self.move_down as i8 - self.move_up as i8) as f32;
        self.bridge.on_move_input(dx, dy);
    }
}

impl<B: RenderBridge> ApplicationHandler for RenderApp<B> {
    fn device_event(&mut self, _event_loop: &ActiveEventLoop, _id: DeviceId, event: DeviceEvent) {
        // グラブ中のみマウスデルタをElixirへ送信する
        if self.cursor_grabbed {
            if let DeviceEvent::MouseMotion { delta: (dx, dy) } = event {
                self.bridge.on_mouse_delta(dx as f32, dy as f32);
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
                // フォーカスを失ったらカーソルを解放し、移動入力もリセット
                if self.cursor_grabbed {
                    self.set_cursor_grabbed(false);
                }
                if self.clear_move_keys() {
                    self.sync_player_input();
                }
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
                    let pressed = event.state == ElementState::Pressed;
                    if self.set_move_key(code, pressed) {
                        self.sync_player_input();
                    } else {
                        match code {
                            KeyCode::ShiftLeft | KeyCode::ShiftRight => {
                                if self.sprint != pressed {
                                    self.sprint = pressed;
                                    self.bridge.on_sprint(pressed);
                                }
                            }
                            KeyCode::Escape if pressed => {
                                // グラブ中・解放中どちらでも Elixir へ通知する。
                                // カーソルグラブ状態の変更は Elixir 側が RenderFrame.cursor_grab で指示する。
                                self.bridge.on_key_pressed(KeyCode::Escape);
                            }
                            _ => {}
                        }
                    }
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
