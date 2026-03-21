//! winit イベントループ・ウィンドウ生成・入力イベント処理
//!
//! render の Renderer を用いて描画するが、イベントループの所有権はここにある。

use render::window::{KeyState, RenderBridge, WindowConfig};
use render::{GameUiState, Renderer, UiComponent, UiNode};
use std::sync::Arc;
use winit::{
    application::ApplicationHandler,
    event::{DeviceEvent, DeviceId, ElementState, WindowEvent},
    event_loop::{ActiveEventLoop, EventLoop},
    keyboard::PhysicalKey,
    window::{CursorGrabMode, Window, WindowId},
};

#[cfg(target_os = "windows")]
use winit::platform::windows::EventLoopBuilderExtWindows;

pub fn run_desktop_loop<B: RenderBridge>(bridge: B, config: WindowConfig) -> Result<(), String> {
    let mut builder = EventLoop::builder();
    #[cfg(target_os = "windows")]
    builder.with_any_thread(true);

    let event_loop = builder
        .build()
        .map_err(|e| format!("event loop create failed: {e}"))?;
    let mut app = DesktopApp::new(bridge, config);
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
    cursor_grabbed: bool,
    suppress_grab_frames: u8,
    retry_button_visible: bool,
}

impl<B: RenderBridge> DesktopApp<B> {
    fn new(bridge: B, config: WindowConfig) -> Self {
        Self {
            bridge,
            config,
            window: None,
            renderer: None,
            ui_state: GameUiState::default(),
            cursor_grabbed: false,
            suppress_grab_frames: 0,
            retry_button_visible: false,
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

    fn frame_has_retry_button(nodes: &[UiNode]) -> bool {
        nodes.iter().any(|node| {
            matches!(
                &node.component,
                UiComponent::Button {
                    action,
                    ..
                } if action == "__retry__"
            ) || Self::frame_has_retry_button(&node.children)
        })
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
        let ui_consumed = if let (Some(renderer), Some(window)) = (&mut self.renderer, &self.window) {
            let consumed = renderer.handle_window_event(window, &event);
            if consumed {
                window.request_redraw();
            }
            consumed
        } else {
            false
        };

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
                if self.retry_button_visible {
                    self.bridge.on_ui_action("__retry__".to_string());
                    if self.cursor_grabbed {
                        self.suppress_grab_frames = 3;
                        self.set_cursor_grabbed(false);
                    }
                    return;
                }

                // クリックによる自動グラブは無効化する。
                // グラブ切替は frame.cursor_grab（サーバー指示）または ESC トグルに委譲することで、
                // タッチパッドのタップ/クリック時にも UI ボタン操作を安定させる。
                if !ui_consumed && self.suppress_grab_frames > 0 {
                    self.suppress_grab_frames -= 1;
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
                let frame = if self.renderer.is_some() {
                    Some(self.bridge.next_frame())
                } else {
                    None
                };
                if let Some(ref frame) = frame {
                    self.retry_button_visible = Self::frame_has_retry_button(&frame.ui.nodes);

                    // __retry__ が存在する UI（GameOver 系）では、クライアント側でも安全にカーソルを解放する。
                    // frame.cursor_grab の伝播が環境差で欠落した場合でも、ボタン操作不能を防ぐ。
                    if self.retry_button_visible && self.cursor_grabbed {
                        self.suppress_grab_frames = 3;
                        self.set_cursor_grabbed(false);
                    }

                    if let Some(grab) = frame.cursor_grab {
                        if grab != self.cursor_grabbed {
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
                        &frame.mesh_definitions,
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
