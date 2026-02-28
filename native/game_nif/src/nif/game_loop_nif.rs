//! Path: native/game_nif/src/nif/game_loop_nif.rs
//! Summary: ゲームループ NIF（physics_step, drain_frame_events, pause/resume, Rust ループ起動）

use super::util::lock_poisoned_err;
use super::events::drain_frame_events_inner;
use game_simulation::game_logic::physics_step_inner;
use game_simulation::world::{GameLoopControl, GameWorld};
use crate::lock_metrics::record_write_wait;
use rustler::env::OwnedEnv;
use rustler::{Atom, Encoder, LocalPid, NifResult, ResourceArc};
use std::thread;
use std::time::{Duration, Instant};

use crate::{frame_events, ok};

#[rustler::nif(schedule = "DirtyCpu")]
pub fn physics_step(world: ResourceArc<GameWorld>, delta_ms: f64) -> NifResult<u32> {
    let wait_start = Instant::now();
    let mut w = world.0.write().map_err(|_| lock_poisoned_err())?;
    record_write_wait("nif.physics_step", wait_start.elapsed());
    physics_step_inner(&mut w, delta_ms);
    Ok(w.frame_id)
}

#[rustler::nif]
pub fn drain_frame_events(world: ResourceArc<GameWorld>) -> NifResult<Vec<(Atom, u32, u32)>> {
    let wait_start = Instant::now();
    let mut w = world.0.write().map_err(|_| lock_poisoned_err())?;
    record_write_wait("nif.drain_frame_events", wait_start.elapsed());
    Ok(drain_frame_events_inner(&mut w))
}

#[rustler::nif]
pub fn create_game_loop_control() -> ResourceArc<GameLoopControl> {
    ResourceArc::new(GameLoopControl::new())
}

#[rustler::nif]
pub fn start_rust_game_loop(
    world: ResourceArc<GameWorld>,
    control: ResourceArc<GameLoopControl>,
    pid: LocalPid,
) -> NifResult<Atom> {
    let world_clone   = world.clone();
    let control_clone = control.clone();
    thread::spawn(move || { run_rust_game_loop(world_clone, control_clone, pid); });
    Ok(ok())
}

fn run_rust_game_loop(
    world: ResourceArc<GameWorld>,
    control: ResourceArc<GameLoopControl>,
    pid: LocalPid,
) {
    const TICK_MS: f64 = 1000.0 / 60.0;
    let mut next_tick = Instant::now();

    loop {
        next_tick += Duration::from_secs_f64(TICK_MS / 1000.0);
        let now = Instant::now();
        if next_tick > now { thread::sleep(next_tick - now); }

        let events: Vec<(Atom, u32, u32)> = {
            let wait_start = Instant::now();
            let mut w = match world.0.write() {
                Ok(guard) => guard,
                Err(_) => break,
            };
            record_write_wait("loop.simulation_tick", wait_start.elapsed());
            if control.is_paused() {
                Vec::new()
            } else {
                physics_step_inner(&mut w, TICK_MS);
                drain_frame_events_inner(&mut w)
            }
        };

        let mut env = OwnedEnv::new();
        let _ = env.send_and_clear(&pid, |env| {
            (frame_events(), events).encode(env)
        });
    }
}

#[rustler::nif]
pub fn pause_physics(control: ResourceArc<GameLoopControl>) -> NifResult<Atom> {
    control.pause();
    Ok(ok())
}

#[rustler::nif]
pub fn resume_physics(control: ResourceArc<GameLoopControl>) -> NifResult<Atom> {
    control.resume();
    Ok(ok())
}
