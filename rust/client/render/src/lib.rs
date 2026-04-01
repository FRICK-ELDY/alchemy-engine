pub use render_frame_proto::decode_pb_render_frame;
pub use shared::render_frame::*;

pub mod common;
pub(crate) mod platform;
pub(crate) mod renderer;
pub mod window;

pub use platform::{GameUiState, LoadDialogKind, Renderer};

#[cfg(feature = "headless")]
pub mod headless;
#[cfg(feature = "headless")]
pub use headless::HeadlessRenderer;
