//! Path: native/game_native/src/render_bridge.rs
//! Summary: game_window の RenderBridge 実装（1.8.4）

use crate::asset::AssetLoader;
use crate::lock_metrics::{record_read_wait, record_write_wait};
use crate::render_snapshot::{
    build_render_frame, calc_interpolation_alpha, copy_interpolation_data, interpolate_player_pos,
};
use crate::world::GameWorld;
use game_core::constants::{SCREEN_HEIGHT, SCREEN_WIDTH};
use game_render::RenderFrame;
use game_window::{run_render_loop, RenderBridge, RendererInit, WindowConfig};
use rustler::ResourceArc;
use std::time::Instant;

pub fn run_render_thread(world: ResourceArc<GameWorld>) {
    let bridge = NativeRenderBridge { world };
    let loader = AssetLoader::new();

    let config = WindowConfig {
        title: "AlchemyEngine - Vampire Survivor".to_string(),
        width: SCREEN_WIDTH as u32,
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
    world: ResourceArc<GameWorld>,
}

impl RenderBridge for NativeRenderBridge {
    fn next_frame(&self) -> RenderFrame {
        let wait_start = Instant::now();

        // 1.10.7: Step 1 - ロック内では補間データのみをコピーして即解放
        let (interp_data, mut frame) = match self.world.0.read() {
            Ok(guard) => {
                record_read_wait("render.next_frame", wait_start.elapsed());
                let interp = copy_interpolation_data(&guard);
                let frame = build_render_frame(&guard);
                (interp, frame)
            }
            Err(e) => {
                log::error!("Render bridge: read lock poisoned in next_frame: {e:?}");
                let guard = e.into_inner();
                record_read_wait("render.next_frame_poisoned", wait_start.elapsed());
                let interp = copy_interpolation_data(&guard);
                let frame = build_render_frame(&guard);
                (interp, frame)
            }
        };

        // 1.10.7: Step 2 - ロック解放後に補間計算（重い処理はここで行う）
        if interp_data.curr_tick_ms > 0 {
            let now_ms = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_millis() as u64;
            let alpha = calc_interpolation_alpha(&interp_data, now_ms);
            let (interp_x, interp_y) = interpolate_player_pos(&interp_data, alpha);

            // プレイヤーのスプライト位置を補間値で上書き（専用フィールドで安全に更新）
            frame.player_pos = (interp_x, interp_y);
            // render_data[0] はプレイヤーエントリ。player_pos と同期させる。
            // render_snapshot::build_render_frame が先頭にプレイヤーを push する仕様は
            // player_pos フィールドのコメントで明記されており、ここでは player_pos を正とする。
            if let Some(entry) = frame.render_data.first_mut() {
                entry.0 = interp_x;
                entry.1 = interp_y;
            }
            // カメラオフセットも補間位置に合わせて更新
            use game_core::constants::{PLAYER_SIZE, SCREEN_WIDTH, SCREEN_HEIGHT};
            let cam_x = interp_x + PLAYER_SIZE / 2.0 - SCREEN_WIDTH / 2.0;
            let cam_y = interp_y + PLAYER_SIZE / 2.0 - SCREEN_HEIGHT / 2.0;
            frame.camera_offset = (cam_x, cam_y);
        }

        frame
    }

    fn on_move_input(&self, dx: f32, dy: f32) {
        let wait_start = Instant::now();
        match self.world.0.write() {
            Ok(mut guard) => {
                record_write_wait("render.on_move_input", wait_start.elapsed());
                guard.player.input_dx = dx;
                guard.player.input_dy = dy;
            }
            Err(e) => {
                log::error!("Render bridge: failed to acquire write lock for input: {e:?}");
            }
        }
    }

    fn on_ui_action(&self, action: String) {
        let wait_start = Instant::now();
        match self.world.0.read() {
            Ok(guard) => {
                record_read_wait("render.on_ui_action", wait_start.elapsed());
                match guard.pending_ui_action.lock() {
                    Ok(mut pending) => {
                        *pending = Some(action);
                    }
                    Err(e) => {
                        log::error!("Render bridge: pending_ui_action mutex poisoned: {e:?}");
                        let mut pending = e.into_inner();
                        *pending = Some(action);
                    }
                }
            }
            Err(e) => {
                log::error!("Render bridge: failed to acquire read lock for ui action: {e:?}");
            }
        }
    }
}
