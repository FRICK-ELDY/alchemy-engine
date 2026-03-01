//! Path: native/game_nif/src/nif/render_nif.rs
//! Summary: 描画スレッド起動 NIF

use crate::render_bridge::run_render_thread;
use game_physics::world::GameWorld;
use rustler::{Atom, LocalPid, NifResult, ResourceArc};
use std::panic::AssertUnwindSafe;
use std::thread;

use crate::ok;

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
