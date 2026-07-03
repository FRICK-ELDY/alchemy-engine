//! winit イベントループ・ウィンドウ生成・入力イベント処理
//!
//! render の Renderer を用いて描画するが、イベントループの所有権はここにある。
//!
//! # システムメニュー（system_ui）との統合
//!
//! - ESC はクライアントが消費し、システムメニューを開閉する（サーバへは送らない）。
//! - メニュー表示中はゲーム入力（キー・movement）を遮断し、カーソルを解放する。
//!   閉じたらサーバ指示（frame.cursor_grab）の状態へ復帰する。
//! - メニュー表示中はゲーム内 Canvas UI を描画せず、システムメニューのみを表示する。

use render::window::{KeyState, RenderBridge, WindowConfig};
use render::{GameUiState, Renderer, UiCanvas};
use std::sync::Arc;
use system_ui::{SystemUi, SystemUiEvent};
use winit::{
    application::ApplicationHandler,
    event::{DeviceEvent, DeviceId, ElementState, WindowEvent},
    event_loop::{ActiveEventLoop, EventLoop},
    keyboard::{KeyCode, PhysicalKey},
    window::{CursorGrabMode, Window, WindowId},
};

#[cfg(target_os = "windows")]
use winit::platform::windows::EventLoopBuilderExtWindows;

pub fn run_desktop_loop<B: RenderBridge>(bridge: B, config: WindowConfig) -> Result<(), String> {
    run_desktop_loop_with_system_ui(bridge, config, SystemUi::new())
}

/// 構成済みの [`SystemUi`]（auth クライアント・リンク設定済み）で起動する。
pub fn run_desktop_loop_with_system_ui<B: RenderBridge>(
    bridge: B,
    config: WindowConfig,
    system_ui: SystemUi,
) -> Result<(), String> {
    let mut builder = EventLoop::builder();
    #[cfg(target_os = "windows")]
    builder.with_any_thread(true);

    let event_loop = builder
        .build()
        .map_err(|e| format!("event loop create failed: {e}"))?;
    let mut app = DesktopApp::new(bridge, config, system_ui);
    event_loop
        .run_app(&mut app)
        .map_err(|e| format!("event loop runtime failed: {e}"))
}

struct DesktopApp<B: RenderBridge> {
    bridge: B,
    config: WindowConfig,
    window: Option<Arc<Window>>,
    renderer: Option<Renderer>,
    ui_state: GameUiState,
    system_ui: SystemUi,
    cursor_grabbed: bool,
    /// サーバがフレームで指示した最新のカーソルグラブ希望状態。
    /// メニュー表示中は適用を保留し、閉じたときにこの状態へ復帰する。
    server_cursor_grab: bool,
    suppress_grab_frames: u8,
}

impl<B: RenderBridge> DesktopApp<B> {
    fn new(bridge: B, config: WindowConfig, system_ui: SystemUi) -> Self {
        Self {
            bridge,
            config,
            window: None,
            renderer: None,
            ui_state: GameUiState::default(),
            system_ui,
            cursor_grabbed: false,
            server_cursor_grab: false,
            suppress_grab_frames: 0,
        }
    }

    fn set_cursor_grabbed(&mut self, grabbed: bool) {
        let Some(window) = &self.window else { return };
        self.cursor_grabbed = grabbed;
        window.set_cursor_visible(!grabbed);
        if grabbed {
            let _ = window
                .set_cursor_grab(CursorGrabMode::Confined)
                .or_else(|_| window.set_cursor_grab(CursorGrabMode::Locked));
        } else {
            let _ = window.set_cursor_grab(CursorGrabMode::None);
        }
    }

    /// システムメニューからのイベントを処理する。
    fn handle_system_event(&mut self, event: SystemUiEvent, event_loop: &ActiveEventLoop) {
        match event {
            SystemUiEvent::Opened => {
                // 押しっぱなしのキーを解除して movement をゼロにする
                self.bridge.on_focus_lost();
                self.set_cursor_grabbed(false);
            }
            SystemUiEvent::Closed => {
                // 非グラブ状態へ復帰する場合、直後のクリックが誤って再グラブ
                // しないようにする（サーバ主導の解放時と同じ抑制を適用する）
                if !self.server_cursor_grab {
                    self.suppress_grab_frames = 3;
                }
                self.set_cursor_grabbed(self.server_cursor_grab);
            }
            SystemUiEvent::QuitRequested => event_loop.exit(),
        }
    }
}

impl<B: RenderBridge> ApplicationHandler for DesktopApp<B> {
    fn device_event(&mut self, _event_loop: &ActiveEventLoop, _id: DeviceId, event: DeviceEvent) {
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

        let renderer =
            pollster::block_on(Renderer::new(window.clone(), &self.config.renderer_init));
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
                if self.cursor_grabbed {
                    self.set_cursor_grabbed(false);
                }
                self.bridge.on_focus_lost();
            }
            WindowEvent::MouseInput {
                state: ElementState::Pressed,
                ..
            } => {
                if self.system_ui.is_open() {
                    // メニュー操作中はクリックで再グラブしない
                } else if self.suppress_grab_frames > 0 {
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
                    // ESC はクライアント所有（システムメニュー開閉）。サーバへは送らない。
                    if code == KeyCode::Escape {
                        if event.state == ElementState::Pressed {
                            if let Some(sys_event) = self.system_ui.handle_escape() {
                                self.handle_system_event(sys_event, event_loop);
                            }
                        }
                        return;
                    }
                    // メニュー表示中はゲーム入力を遮断する
                    // （egui へは handle_window_event 経由で既に届いている）
                    if self.system_ui.is_open() {
                        return;
                    }
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
                if self.renderer.is_none() || self.window.is_none() {
                    return;
                }

                self.system_ui.set_connected(self.bridge.is_connected());
                let frame = self.bridge.next_frame();

                // サーバ希望のカーソル状態を記録し、メニュー非表示時のみ適用する
                if let Some(grab) = frame.cursor_grab {
                    self.server_cursor_grab = grab;
                    if !self.system_ui.is_open() && grab != self.cursor_grabbed {
                        if !grab {
                            self.suppress_grab_frames = 3;
                        }
                        self.set_cursor_grabbed(grab);
                    }
                }

                // メニュー表示中はゲーム内 Canvas UI を隠す（クリックの取り合いも防ぐ）
                let menu_open = self.system_ui.is_open();
                let empty_ui = UiCanvas::default();
                let ui = if menu_open { &empty_ui } else { &frame.ui };

                let mut sys_event: Option<SystemUiEvent> = None;
                let system_ui = &mut self.system_ui;
                let ui_state = &mut self.ui_state;
                let (Some(renderer), Some(window)) = (self.renderer.as_mut(), self.window.as_ref())
                else {
                    return;
                };

                renderer.update_instances(&frame);
                let action = renderer.render(
                    window,
                    ui,
                    &frame.camera,
                    &frame.commands,
                    &frame.mesh_definitions,
                    ui_state,
                    &mut |ctx| {
                        sys_event = system_ui.render(ctx);
                    },
                );

                // メニュー開時は空 Canvas を渡しているため、ここで返るアクションは
                // メニューを開く前に予約された pending_action（セーブ/ロード等）のみ。
                // 破棄すると要求が永久に失われるため、常にサーバへ転送する。
                if let Some(action) = action {
                    self.bridge.on_ui_action(action);
                }
                if let Some(sys_event) = sys_event {
                    self.handle_system_event(sys_event, event_loop);
                }
                if let Some(window) = &self.window {
                    window.request_redraw();
                }
            }
            _ => {}
        }
    }
}
