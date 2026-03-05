//! Path: native/nif/src/nif/mod.rs
//! Summary: NIF エントリモジュール

mod action_nif;
pub(crate) mod events;
mod game_loop_nif;
mod load;
mod push_tick_nif;
mod read_nif;
mod render_frame_nif;
mod render_nif;
mod save_nif;
mod util;
mod world_nif;

#[cfg(feature = "xr")]
mod xr_nif;

pub use load::load;
pub use save_nif::SaveSnapshot;
