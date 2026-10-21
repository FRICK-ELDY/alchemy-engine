//! NIF ロード。リソース型（GameWorld 等）は登録しない。

#[cfg(debug_assertions)]
fn init_panic_hook() {
    std::panic::set_hook(Box::new(|info| {
        eprintln!("[Rust NIF Panic] {}", info);
        eprintln!("Backtrace:\n{}", std::backtrace::Backtrace::force_capture());
    }));
}

#[allow(non_local_definitions)]
pub fn load(_env: rustler::Env, _: rustler::Term) -> bool {
    #[cfg(debug_assertions)]
    init_panic_hook();
    let _ = env_logger::Builder::from_default_env().try_init();
    true
}
