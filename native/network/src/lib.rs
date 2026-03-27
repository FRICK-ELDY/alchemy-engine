//! network - Zenoh による通信層
//!
//! 上位レイヤーには「UDP か WebSocket か」を意識させず、
//! 「データが届いた」という事実だけを伝える。

pub mod bert_decode;
pub mod bert_encode;
pub mod common;
pub mod network_render_bridge;
pub mod platform;
pub mod protobuf_codec;
pub mod protobuf_render_frame;

pub use common::*;
pub use network_render_bridge::NetworkRenderBridge;
pub use platform::ClientSession;
pub use shared::ClientInfo;
