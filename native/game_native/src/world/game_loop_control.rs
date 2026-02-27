//! Path: native/game_native/src/world/game_loop_control.rs
//! Summary: GameLoop 制御用（pause/resume）リソース

/// 1.5.1: GameLoop 制御用（pause/resume）
pub struct GameLoopControl {
    paused: std::sync::atomic::AtomicBool,
}

impl GameLoopControl {
    pub fn new() -> Self {
        Self {
            paused: std::sync::atomic::AtomicBool::new(false),
        }
    }
    pub fn pause(&self) {
        self.paused.store(true, std::sync::atomic::Ordering::SeqCst);
    }
    pub fn resume(&self) {
        self.paused.store(false, std::sync::atomic::Ordering::SeqCst);
    }
    pub fn is_paused(&self) -> bool {
        self.paused.load(std::sync::atomic::Ordering::SeqCst)
    }
}
