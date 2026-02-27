//! Path: native/game_native/src/nif/render_nif.rs
//! Summary: 描画スレッド起動 NIF（フェーズ5: PID を受け取り直接 Elixir 送信に対応）
//!
//! フェーズ5 の変更:
//! - RENDER_THREAD_RUNNING static AtomicBool を廃止
//!   → 重複起動防止は Elixir 側の GameEvents.render_started フラグで管理
//! - Elixir PID を引数で受け取り、run_render_thread に渡す
//!   → on_ui_action / on_move_input が直接 GameEvents プロセスに送信できる

use crate::render_bridge::run_render_thread;
use crate::world::GameWorld;
use rustler::{Atom, LocalPid, NifResult, ResourceArc};
use std::panic::AssertUnwindSafe;
use std::thread;

use crate::ok;

/// フェーズ5: RENDER_THREAD_RUNNING static 廃止。重複起動防止は Elixir 側で管理。
/// pid: UI アクション・移動入力を直接送信する GameEvents プロセスの PID
#[rustler::nif]
pub fn start_render_thread(world: ResourceArc<GameWorld>, pid: LocalPid) -> NifResult<Atom> {
    let world_clone = world.clone();

    thread::spawn(move || {
        if let Err(e) = std::panic::catch_unwind(AssertUnwindSafe(move || {
            run_render_thread(world_clone, pid);
        })) {
            eprintln!("Render thread panicked: {:?}", e);
        }
    });

    Ok(ok())
}
