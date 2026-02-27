//! Path: native/game_native/src/nif/mod.rs
//! Summary: NIF エントリモジュール

mod action_nif;
mod game_loop_nif;
mod load;
mod render_nif;
mod read_nif;
mod save_nif;
mod util;
mod world_nif;

pub use load::load;
pub use save_nif::{SaveSnapshot, WeaponSlotSave};
