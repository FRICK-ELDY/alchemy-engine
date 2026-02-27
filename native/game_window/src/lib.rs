use game_render::{GameUiState, RenderFrame, Renderer};
use std::sync::Arc;
use winit::{
    application::ApplicationHandler,
    event::{ElementState, WindowEvent},
    event_loop::{ActiveEventLoop, EventLoop},
    keyboard::{KeyCode, PhysicalKey},
    window::{Window, WindowId},
};

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
}

pub fn run_render_loop<B: RenderBridge>(bridge: B, config: WindowConfig) -> Result<(), String> {
    let mut builder = EventLoop::builder();
    #[cfg(target_os = "windows")]
    builder.with_any_thread(true);

    let event_loop = builder.build().map_err(|e| format!("event loop create failed: {e}"))?;
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
        let had_pressed = self.move_up || self.move_down || self.move_left || self.move_right;
        self.move_up = false;
        self.move_down = false;
        self.move_left = false;
        self.move_right = false;
        had_pressed
    }

    fn sync_player_input(&self) {
        let dx = (self.move_right as i8 - self.move_left as i8) as f32;
        let dy = (self.move_down as i8 - self.move_up as i8) as f32;
        self.bridge.on_move_input(dx, dy);
    }
}

impl<B: RenderBridge> ApplicationHandler for RenderApp<B> {
    fn resumed(&mut self, event_loop: &ActiveEventLoop) {
        if self.window.is_some() {
            return;
        }

        let window = Arc::new(
            event_loop
                .create_window(
                    Window::default_attributes()
                        .with_title(self.config.title.clone())
                        .with_inner_size(winit::dpi::LogicalSize::new(self.config.width, self.config.height)),
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
                if self.clear_move_keys() {
                    self.sync_player_input();
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
                if let (Some(renderer), Some(window)) = (&mut self.renderer, &self.window) {
                    let frame = self.bridge.next_frame();
                    renderer.update_instances(
                        &frame.render_data,
                        &frame.particle_data,
                        &frame.item_data,
                        &frame.obstacle_data,
                        frame.camera_offset,
                    );
                    if let Some(action) = renderer.render(window, &frame.hud, &mut self.ui_state) {
                        self.bridge.on_ui_action(action);
                    }
                    window.request_redraw();
                }
            }
            _ => {}
        }
    }
}
