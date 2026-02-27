//! Path: native/game_nif/src/render_bridge.rs
//! Summary: game_render の RenderBridge 実装

use game_audio::AssetLoader;
use crate::lock_metrics::record_read_wait;
use crate::render_snapshot::{
    build_render_frame, calc_interpolation_alpha, copy_interpolation_data, interpolate_player_pos,
};
use game_simulation::world::GameWorld;
use game_simulation::constants::{PLAYER_SIZE, SCREEN_HEIGHT, SCREEN_WIDTH};
use game_render::RenderFrame;
use game_render::window::{run_render_loop, RenderBridge, RendererInit, WindowConfig};
use rustler::env::OwnedEnv;
use rustler::{Encoder, LocalPid, ResourceArc};
use std::time::Instant;

pub fn run_render_thread(world: ResourceArc<GameWorld>, elixir_pid: LocalPid) {
    let bridge = NativeRenderBridge { world, elixir_pid };
    let loader = AssetLoader::new();

    let config = WindowConfig {
        title: "AlchemyEngine - Vampire Survivor".to_string(),
        width:  SCREEN_WIDTH  as u32,
        height: SCREEN_HEIGHT as u32,
        renderer_init: RendererInit {
            atlas_png: loader.load_sprite_atlas(),
        },
    };

    if let Err(e) = run_render_loop(bridge, config) {
        eprintln!("Render thread: {e}");
    }
}

struct NativeRenderBridge {
    world:      ResourceArc<GameWorld>,
    elixir_pid: LocalPid,
}

impl RenderBridge for NativeRenderBridge {
    fn next_frame(&self) -> RenderFrame {
        let wait_start = Instant::now();

        let (interp_data, mut frame) = match self.world.0.read() {
            Ok(guard) => {
                record_read_wait("render.next_frame", wait_start.elapsed());
                let interp = copy_interpolation_data(&guard);
                let frame  = build_render_frame(&guard);
                (interp, frame)
            }
            Err(e) => {
                log::error!("Render bridge: read lock poisoned in next_frame: {e:?}");
                let guard = e.into_inner();
                record_read_wait("render.next_frame_poisoned", wait_start.elapsed());
                let interp = copy_interpolation_data(&guard);
                let frame  = build_render_frame(&guard);
                (interp, frame)
            }
        };

        if interp_data.curr_tick_ms > 0 {
            let now_ms = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_millis() as u64;
            let alpha = calc_interpolation_alpha(&interp_data, now_ms);
            let (interp_x, interp_y) = interpolate_player_pos(&interp_data, alpha);

            frame.player_pos = (interp_x, interp_y);
            if let Some(entry) = frame.render_data.first_mut() {
                entry.0 = interp_x;
                entry.1 = interp_y;
            }
            let cam_x = interp_x + PLAYER_SIZE / 2.0 - SCREEN_WIDTH  / 2.0;
            let cam_y = interp_y + PLAYER_SIZE / 2.0 - SCREEN_HEIGHT / 2.0;
            frame.camera_offset = (cam_x, cam_y);
        }

        frame
    }

    fn on_move_input(&self, dx: f32, dy: f32) {
        let mut env = OwnedEnv::new();
        let _ = env.send_and_clear(&self.elixir_pid, |env| {
            (crate::move_input(), dx as f64, dy as f64).encode(env)
        });
    }

    fn on_ui_action(&self, action: String) {
        let mut env = OwnedEnv::new();
        let _ = env.send_and_clear(&self.elixir_pid, |env| {
            (crate::ui_action(), action).encode(env)
        });
    }
}
