//! Path: native/game_nif/src/nif/render_nif.rs
//! Summary: 描画スレッド起動 NIF
//!
//! Elixir 側からウィンドウタイトルとアトラスのファイルパスを受け取り、
//! 描画スレッドを起動する。アトラスの実際のロードは Rust 側（render_bridge）で行う。
//! この NIF は起動時に一度だけ呼ばれる。

use crate::render_bridge::run_render_thread;
use crate::render_frame_buffer::RenderFrameBuffer;
use physics::world::GameWorld;
use rustler::{Atom, LocalPid, NifResult, ResourceArc};
use std::panic::AssertUnwindSafe;
use std::thread;

use crate::ok;

#[rustler::nif]
pub fn start_render_thread(
    world: ResourceArc<GameWorld>,
    render_buf: ResourceArc<RenderFrameBuffer>,
    pid: LocalPid,
    title: String,
    atlas_path: String,
) -> NifResult<Atom> {
    let world_clone = world.clone();
    let render_buf_clone = render_buf.clone();
    thread::spawn(move || {
        if let Err(e) = std::panic::catch_unwind(AssertUnwindSafe(move || {
            run_render_thread(world_clone, render_buf_clone, pid, title, atlas_path);
        })) {
            eprintln!("Render thread panicked: {:?}", e);
        }
    });
    Ok(ok())
}
