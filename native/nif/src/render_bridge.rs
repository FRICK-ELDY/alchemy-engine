//! Path: native/nif/src/render_bridge.rs
//! Summary: desktop_render の RenderBridge 実装
//!
//! Phase R-2: RenderBridge::next_frame() が GameWorldInner を直接読む代わりに
//! RenderFrameBuffer を参照するよう変更した。
//! プレイヤー補間のみ GameWorld から補間データを読み取って適用する。
//!
//! Phase R-4: ウィンドウタイトルとアトラスパスを引数として受け取るよう変更した。
//! Elixir 側はパス文字列のみを渡し、ファイルの実態（バイナリ）は持たない。
//! アトラスのロードはこの関数内で行い、ファイルが存在しない場合は
//! AssetLoader の埋め込みフォールバックを使用する。

use crate::lock_metrics::record_read_wait;
use crate::render_frame_buffer::RenderFrameBuffer;
use audio::AssetLoader;
use desktop_input::run_desktop_loop;
use physics::constants::{PLAYER_SIZE, SCREEN_HEIGHT, SCREEN_WIDTH};
use physics::world::GameWorld;
use desktop_render::window::{KeyCode, KeyState, RenderBridge, RendererInit, WindowConfig};
use desktop_render::{CameraParams, DrawCommand, RenderFrame};
use rustler::env::OwnedEnv;
use rustler::{Encoder, LocalPid, ResourceArc};
use std::time::Instant;

pub fn run_render_thread(
    world: ResourceArc<GameWorld>,
    render_buf: ResourceArc<RenderFrameBuffer>,
    elixir_pid: LocalPid,
    title: String,
    atlas_path: String,
) {
    let bridge = NativeRenderBridge {
        world,
        render_buf,
        elixir_pid,
    };

    let atlas_png = load_atlas_png(&atlas_path);
    let (sprite_wgsl, mesh_wgsl) = load_shaders_from_atlas_path(&atlas_path);

    let config = WindowConfig {
        title,
        width: SCREEN_WIDTH as u32,
        height: SCREEN_HEIGHT as u32,
        renderer_init: RendererInit {
            atlas_png,
            sprite_wgsl,
            mesh_wgsl,
        },
    };

    if let Err(e) = run_desktop_loop(bridge, config) {
        eprintln!("Render thread: {e}");
    }
}

/// アトラス PNG をファイルから読み込む。
/// ファイルが存在しない場合は AssetLoader の埋め込みデータにフォールバックする。
fn load_atlas_png(path: &str) -> Vec<u8> {
    match std::fs::read(path) {
        Ok(data) => data,
        Err(e) => {
            log::warn!("atlas not found at '{path}': {e} — falling back to embedded atlas");
            AssetLoader::new().load_sprite_atlas()
        }
    }
}

/// P4: atlas_path からシェーダーディレクトリを導出し、sprite.wgsl / mesh.wgsl をロードする。
/// ファイルが存在しない場合は None を返し、Rust 側で include_str! フォールバックを使用する。
///
/// パス構成（shader-elixir-interface.md 参照）:
/// - atlas_path: assets/{game_id}/sprites/atlas.png
/// - shader_dir: assets/{game_id}/shaders
/// - shared_shader_dir: assets/shaders（共有フォールバック）
fn load_shaders_from_atlas_path(atlas_path: &str) -> (Option<String>, Option<String>) {
    let path = std::path::Path::new(atlas_path);
    // assets/{game_id}/sprites/atlas.png → assets/{game_id}/shaders
    let shader_dir = path
        .parent()
        .and_then(|p| p.parent())
        .map(|p| p.join("shaders"));
    // assets/{game_id}/sprites/atlas.png → assets/shaders（共有フォールバック）
    let shared_shader_dir = path
        .parent()
        .and_then(|p| p.parent())
        .and_then(|p| p.parent())
        .map(|p| p.join("shaders"));

    let try_load = |name: &str| -> Option<String> {
        if let Some(ref d) = shader_dir {
            match std::fs::read_to_string(d.join(name)) {
                Ok(s) => return Some(s),
                Err(e) => log::debug!("shader {name} not in content dir {:?}: {e}", d),
            }
        }
        if let Some(ref d) = shared_shader_dir {
            match std::fs::read_to_string(d.join(name)) {
                Ok(s) => return Some(s),
                Err(e) => log::debug!("shader {name} not in shared dir {:?}: {e}", d),
            }
        }
        log::debug!(
            "shader {name}: using include_str! fallback (no file in content or shared shader dir)"
        );
        None
    };

    let sprite_wgsl = try_load("sprite.wgsl");
    let mesh_wgsl = try_load("mesh.wgsl");
    (sprite_wgsl, mesh_wgsl)
}

struct NativeRenderBridge {
    world: ResourceArc<GameWorld>,
    render_buf: ResourceArc<RenderFrameBuffer>,
    elixir_pid: LocalPid,
}

impl RenderBridge for NativeRenderBridge {
    fn next_frame(&self) -> RenderFrame {
        // RenderFrameBuffer から最新フレームを取得する
        let mut frame = self.render_buf.get();

        // プレイヤー補間: GameWorld から読み取り
        let wait_start = Instant::now();
        let interp_data = {
            let guard = match self.world.0.read() {
                Ok(guard) => {
                    record_read_wait("render.next_frame", wait_start.elapsed());
                    guard
                }
                Err(e) => {
                    log::error!("Render bridge: read lock poisoned in next_frame: {e:?}");
                    record_read_wait("render.next_frame_poisoned", wait_start.elapsed());
                    e.into_inner()
                }
            };
            copy_interpolation_data(&guard)
        };

        // 補間は Camera2D 専用。Camera3D の場合は Elixir 側がカメラを毎フレーム計算して
        // push するため、ここでの上書きは不要かつ有害。
        let is_2d = matches!(frame.camera, CameraParams::Camera2D { .. });

        if is_2d && interp_data.curr_tick_ms > 0 {
            let now_ms = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_millis() as u64;
            let alpha = calc_interpolation_alpha(&interp_data, now_ms);
            let (interp_x, interp_y) = interpolate_player_pos(&interp_data, alpha);

            // R-R1: RenderComponent は player を SpriteRaw で先頭に配置する規約。
            // 補間後の座標で先頭の SpriteRaw（= プレイヤー）の x, y を上書きする。
            // 契約違反検知: 先頭が SpriteRaw でない場合は補間をスキップしログを出す。
            let player_cmd = frame.commands.first_mut();
            match player_cmd {
                Some(DrawCommand::SpriteRaw {
                    ref mut x,
                    ref mut y,
                    ..
                }) => {
                    *x = interp_x;
                    *y = interp_y;
                }
                Some(cmd) => {
                    log::warn!(
                        "render_bridge: expected first command to be SpriteRaw (player), got {:?}; interpolation skipped",
                        std::mem::discriminant(cmd)
                    );
                }
                None => {
                    log::warn!("render_bridge: no draw commands; player interpolation skipped");
                }
            }
            let cam_x = interp_x + PLAYER_SIZE / 2.0 - SCREEN_WIDTH / 2.0;
            let cam_y = interp_y + PLAYER_SIZE / 2.0 - SCREEN_HEIGHT / 2.0;
            frame.camera = CameraParams::Camera2D {
                offset_x: cam_x,
                offset_y: cam_y,
            };
        }

        frame
    }

    fn on_ui_action(&self, action: String) {
        let mut env = OwnedEnv::new();
        let _ = env.send_and_clear(&self.elixir_pid, |env| {
            (crate::ui_action(), action).encode(env)
        });
    }

    fn on_raw_key(&self, key: KeyCode, state: KeyState) {
        let key_str = crate::key_map::key_code_to_atom_str(key);
        let state_atom = match state {
            KeyState::Pressed => crate::pressed(),
            KeyState::Released => crate::released(),
        };
        let mut env = OwnedEnv::new();
        let _ = env.send_and_clear(&self.elixir_pid, |env| {
            let key_atom =
                rustler::Atom::from_str(env, key_str).unwrap_or_else(|_| crate::unknown());
            (crate::raw_key(), key_atom, state_atom).encode(env)
        });
    }

    fn on_raw_mouse_motion(&self, dx: f32, dy: f32) {
        let mut env = OwnedEnv::new();
        let _ = env.send_and_clear(&self.elixir_pid, |env| {
            (crate::raw_mouse_motion(), dx as f64, dy as f64).encode(env)
        });
    }

    fn on_focus_lost(&self) {
        let mut env = OwnedEnv::new();
        let _ = env.send_and_clear(&self.elixir_pid, |env| crate::focus_lost().encode(env));
    }
}

// ── 補間ヘルパー（render_snapshot.rs から移動）────────────────────────

struct InterpolationData {
    prev_player_x: f32,
    prev_player_y: f32,
    curr_player_x: f32,
    curr_player_y: f32,
    prev_tick_ms: u64,
    curr_tick_ms: u64,
}

fn copy_interpolation_data(w: &physics::world::GameWorldInner) -> InterpolationData {
    InterpolationData {
        prev_player_x: w.prev_player_x,
        prev_player_y: w.prev_player_y,
        curr_player_x: w.player.x,
        curr_player_y: w.player.y,
        prev_tick_ms: w.prev_tick_ms,
        curr_tick_ms: w.curr_tick_ms,
    }
}

fn calc_interpolation_alpha(data: &InterpolationData, now_ms: u64) -> f32 {
    let tick_duration = data.curr_tick_ms.saturating_sub(data.prev_tick_ms);
    if tick_duration == 0 {
        return 1.0;
    }
    let elapsed = now_ms.saturating_sub(data.prev_tick_ms);
    (elapsed as f32 / tick_duration as f32).clamp(0.0, 1.0)
}

fn interpolate_player_pos(data: &InterpolationData, alpha: f32) -> (f32, f32) {
    let x = data.prev_player_x + (data.curr_player_x - data.prev_player_x) * alpha;
    let y = data.prev_player_y + (data.curr_player_y - data.prev_player_y) * alpha;
    (x, y)
}
