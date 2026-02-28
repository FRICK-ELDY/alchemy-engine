//! Path: native/game_nif/src/nif/mod.rs
//! Summary: NIF エントリモジュール

mod action_nif;
pub(crate) mod events;
mod game_loop_nif;
mod load;
mod push_tick_nif;
mod render_nif;
mod read_nif;
mod save_nif;
mod util;
mod world_nif;

pub use load::load;
pub use save_nif::{SaveSnapshot, WeaponSlotSave};
