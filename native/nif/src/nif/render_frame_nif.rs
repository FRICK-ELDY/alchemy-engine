//! Path: native/nif/src/nif/render_frame_nif.rs
//! Summary: RenderFrameBuffer 作成・push_render_frame NIF
//!
//! Phase R-2: Elixir 側（contents）が DrawCommand リストを組み立てて
//! push_render_frame NIF 経由でバッファに書き込む。
//!
//! デコードロジックは decode/ モジュールに分割:
//! - decode/draw_command.rs — DrawCommand
//! - decode/camera.rs     — CameraParams
//! - decode/ui_canvas.rs  — UiCanvas / UiNode / UiComponent

use super::decode::{
    decode_camera, decode_commands, decode_cursor_grab, decode_mesh_definitions, decode_ui_canvas,
};
use crate::render_frame_buffer::RenderFrameBuffer;
use render::RenderFrame;
use rustler::{Atom, NifResult, ResourceArc, Term};

use crate::ok;

// ── リソース作成 ──────────────────────────────────────────────────────

#[rustler::nif]
pub fn create_render_frame_buffer() -> ResourceArc<RenderFrameBuffer> {
    ResourceArc::new(RenderFrameBuffer::new())
}

// ── push_render_frame ────────────────────────────────────────────────

/// Elixir 側から DrawCommand リスト・カメラ・UiCanvas を受け取り、
/// RenderFrameBuffer に書き込む。
///
/// ## DrawCommand タプル形式
/// - `{:player_sprite, x, y, frame}`
/// - `{:sprite, x, y, kind_id, frame}`
/// - `{:particle, x, y, r, g, b, {alpha, size}}`
/// - `{:item, x, y, kind}`
/// - `{:obstacle, x, y, radius, kind}`
///
/// ## CameraParams タプル形式
/// - `{:camera_2d, offset_x, offset_y}`
///
/// ## UiCanvas タプル形式
/// `{:canvas, [node]}` — 詳細は decode/ui_canvas.rs を参照
///
/// ## cursor_grab
/// - `:grab` | `:release` | `:no_change`
/// P3: 6 番目の引数 `mesh_definitions` は省略可能。
/// 非 nil の場合はメッシュ定義リストを decode し、Rust パイプラインが登録する。
#[rustler::nif]
pub fn push_render_frame(
    buf: ResourceArc<RenderFrameBuffer>,
    commands: Term,
    camera: Term,
    ui: Term,
    cursor_grab: Term,
    mesh_definitions: Term,
) -> NifResult<Atom> {
    let commands = decode_commands(commands)?;
    let camera = decode_camera(camera)?;
    let ui = decode_ui_canvas(ui)?;
    let cursor_grab = decode_cursor_grab(cursor_grab)?;
    let mesh_definitions = decode_mesh_definitions(mesh_definitions)?;

    buf.push(RenderFrame {
        commands,
        camera,
        ui,
        cursor_grab,
        mesh_definitions,
    });

    Ok(ok())
}
