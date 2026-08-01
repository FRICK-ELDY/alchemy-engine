//! shared - Elixir との契約・予測・補間
//!
//! Elixir の状態を Rust 側に「映し出す」ための層。
//! - Zero-Copy: bytemuck によるバイナリ直接参照
//! - Smoothing: 20Hz 更新を 60Hz 描画用に補間

pub mod display;
pub mod engine_color;
pub mod interp;
pub mod predict;
pub mod render_frame;
pub mod store;
pub mod types;

pub use interp::{
    interpolate_render_frame, lerp, lerp_draw_command, lerp_vec2, SnapshotInterpolator,
    INTERP_DELAY,
};
pub use predict::predict_input;
pub use store::Store;
pub use types::*;
