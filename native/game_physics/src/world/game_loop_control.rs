//! Path: native/game_physics/src/world/game_loop_control.rs
//! Summary: GameLoop 蛻ｶ蠕｡逕ｨ・・ause/resume・峨Μ繧ｽ繝ｼ繧ｹ

/// 1.5.1: GameLoop 蛻ｶ蠕｡逕ｨ・・ause/resume・・
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
