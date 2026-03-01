//! Path: native/game_nif/src/nif/load.rs
//! Summary: NIF ローダー（パニックフック・リソース登録・アトム事前登録）

use game_physics::world::{GameLoopControl, GameWorld};

#[cfg(debug_assertions)]
fn init_panic_hook() {
    std::panic::set_hook(Box::new(|info| {
        eprintln!("[Rust NIF Panic] {}", info);
        eprintln!("Backtrace:\n{}", std::backtrace::Backtrace::force_capture());
    }));
}

#[allow(non_local_definitions)]
pub fn load(env: rustler::Env, _: rustler::Term) -> bool {
    #[cfg(debug_assertions)]
    init_panic_hook();
    let _ = env_logger::Builder::from_default_env().try_init();

    if env.register::<GameWorld>().is_err() {
        return false;
    }
    if env.register::<GameLoopControl>().is_err() {
        return false;
    }
    let _ = crate::ok();
    let _ = crate::frame_events();
    let _ = crate::slime();
    let _ = crate::bat();
    let _ = crate::golem();
    let _ = crate::enemy_killed();
    let _ = crate::player_damaged();
    let _ = crate::level_up_event();
    let _ = crate::item_pickup();
    let _ = crate::boss_defeated();
    true
}
