//! network - Zenoh による通信層
//!
//! 上位レイヤーには「UDP か WebSocket か」を意識させず、
//! 「データが届いた」という事実だけを伝える。

pub mod common;
pub mod msgpack_decode;
pub mod network_render_bridge;
pub mod platform;

pub use common::*;
pub use network_render_bridge::NetworkRenderBridge;
pub use platform::ClientSession;
pub use shared::ClientInfo;
