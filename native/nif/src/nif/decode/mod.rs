//! Path: native/nif/src/nif/decode/mod.rs
//! Summary: RenderFrame デコード共通ヘルパー
//!
//! atom_str, tag_of, decode_color 等の共通ユーティリティを集約。
//! 各サブモジュール（draw_command, camera, ui_canvas）から利用される。

mod camera;
mod draw_command;
mod ui_canvas;

pub use camera::decode_camera;
pub use draw_command::decode_commands;
pub use ui_canvas::decode_ui_canvas;

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
