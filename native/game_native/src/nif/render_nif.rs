//! Path: native/game_native/src/nif/render_nif.rs
//! Summary: 描画スレッド起動 NIF（1.7.4）
//!
//! NIF から描画用スレッドを spawn し、そのスレッドで winit の EventLoop・
//! ウィンドウ作成・wgpu 初期化の骨組みを実行する。

use crate::render_bridge::run_render_thread;
use crate::world::GameWorld;
use rustler::{Atom, NifResult, ResourceArc};
use std::panic::AssertUnwindSafe;
use std::sync::atomic::{AtomicBool, Ordering};
use std::thread;

use crate::ok;

/// 1.7.6: 描画スレッドはプロセス内で 1 本のみ起動する。
static RENDER_THREAD_RUNNING: AtomicBool = AtomicBool::new(false);

#[rustler::nif]
pub fn start_render_thread(world: ResourceArc<GameWorld>) -> NifResult<Atom> {
    // 既に起動済みなら何もしない（重複ウィンドウを防止）
    if RENDER_THREAD_RUNNING
        .compare_exchange(false, true, Ordering::AcqRel, Ordering::Acquire)
        .is_err()
    {
        log::warn!("Render thread already running; skipping duplicate start request");
        return Ok(ok());
    }

    let world_clone = world.clone();

    thread::spawn(move || {
        if let Err(e) = std::panic::catch_unwind(AssertUnwindSafe(move || {
            run_render_thread(world_clone);
        })) {
            eprintln!("Render thread panicked: {:?}", e);
        }
        // スレッド終了時にフラグを戻し、必要なら再起動できるようにする。
        RENDER_THREAD_RUNNING.store(false, Ordering::Release);
    });

    Ok(ok())
}
