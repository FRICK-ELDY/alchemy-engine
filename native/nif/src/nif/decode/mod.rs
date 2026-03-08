//! Path: native/nif/src/nif/decode/mod.rs
//! Summary: RenderFrame デコード共通ヘルパー
//!
//! atom_str, tag_of, decode_color 等の共通ユーティリティを集約。
//! 各サブモジュール（draw_command, camera, ui_canvas）から利用される。

mod camera;
mod draw_command;
mod mesh_def;
mod msgpack;
mod msgpack_injection;
mod ui_canvas;

pub use camera::decode_camera;
pub use draw_command::decode_commands;
pub use mesh_def::decode_mesh_definitions;
pub use msgpack::decode_render_frame_from_msgpack;
pub use msgpack_injection::apply_injection_from_msgpack;
pub use ui_canvas::decode_ui_canvas;

use desktop_render::MeshVertex;
use rustler::types::list::ListIterator;
use rustler::types::tuple::get_tuple;
use rustler::{Error as NifError, NifResult, Term};

/// アトムを文字列に変換する。
pub(crate) fn atom_str<'a>(term: Term<'a>) -> NifResult<String> {
    term.atom_to_string()
        .map_err(|_| NifError::Term(Box::new("expected atom")))
}

/// タプルの先頭要素（タグアトム）を文字列として取得する。
pub(crate) fn tag_of(term: Term) -> NifResult<String> {
    let elems = get_tuple(term).map_err(|_| NifError::Term(Box::new("expected tuple")))?;
    let first = elems
        .first()
        .ok_or_else(|| NifError::Term(Box::new("expected non-empty tuple")))?;
    atom_str(*first)
}

/// u32 を u8 に安全に変換する。255 を超える場合はエラーを返す。
pub(crate) fn u32_to_u8(value: u32, context: &str) -> NifResult<u8> {
    u8::try_from(value).map_err(|_| {
        NifError::Term(Box::new(format!(
            "{context}: value {value} does not fit in u8 (0-255)"
        )))
    })
}

/// `{r, g, b, a}` タプルを `[f32; 4]` にデコードする。
pub(crate) fn decode_color(term: Term) -> NifResult<[f32; 4]> {
    let (r, g, b, a): (f64, f64, f64, f64) = term
        .decode()
        .map_err(|_| NifError::Term(Box::new("color: expected {r, g, b, a}")))?;
    Ok([r as f32, g as f32, b as f32, a as f32])
}

/// `{{x,y,z}, {r,g,b,a}}` 形式の頂点をデコードする。
/// grid_plane_verts / mesh_def で共通利用。
pub(crate) fn decode_vertex(term: Term) -> NifResult<MeshVertex> {
    let (pos_t, color_t): (Term, Term) = term.decode().map_err(|_| {
        NifError::Term(Box::new("vertex: expected {{x,y,z}, {r,g,b,a}}"))
    })?;
    let (x, y, z): (f64, f64, f64) = pos_t.decode().map_err(|_| {
        NifError::Term(Box::new("vertex position: expected {x, y, z}"))
    })?;
    let color = decode_color(color_t)?;
    Ok(MeshVertex {
        position: [x as f32, y as f32, z as f32],
        color,
    })
}

/// 頂点リスト `[{{x,y,z},{r,g,b,a}}, ...]` をデコードする。
/// P5-3: with_capacity で再アロケーションを抑制。
pub(crate) fn decode_mesh_vertices(term: Term, context: &str) -> NifResult<Vec<MeshVertex>> {
    let iter: ListIterator = term.decode().map_err(|_| {
        NifError::Term(Box::new(format!(
            "{context}: expected list of {{{{pos}}, color}}"
        )))
    })?;
    let mut out = Vec::with_capacity(64);
    for item in iter {
        out.push(decode_vertex(item)?);
    }
    Ok(out)
}

/// カーソルグラブ要求をデコードする。
/// - `:grab`      → `Some(true)`
/// - `:release`   → `Some(false)`
/// - `:no_change` → `None`
pub fn decode_cursor_grab(term: Term) -> NifResult<Option<bool>> {
    let s = atom_str(term).map_err(|_| {
        NifError::Term(Box::new(
            "cursor_grab: expected :grab | :release | :no_change",
        ))
    })?;
    match s.as_str() {
        "grab" => Ok(Some(true)),
        "release" => Ok(Some(false)),
        "no_change" => Ok(None),
        other => Err(NifError::Term(Box::new(format!(
            "cursor_grab: unknown atom '{other}'"
        )))),
    }
}
