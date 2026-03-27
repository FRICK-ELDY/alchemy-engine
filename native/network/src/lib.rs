//! network - Zenoh による通信層
//!
//! 上位レイヤーには「UDP か WebSocket か」を意識させず、
//! 「データが届いた」という事実だけを伝える。

pub mod common;
pub mod network_render_bridge;
pub mod pb {
    include!(concat!(env!("OUT_DIR"), "/alchemy.render.rs"));
    include!(concat!(env!("OUT_DIR"), "/alchemy.input.rs"));
    include!(concat!(env!("OUT_DIR"), "/alchemy.frame.rs"));
    include!(concat!(env!("OUT_DIR"), "/alchemy.client.rs"));
}
pub mod platform;
pub mod protobuf_codec;
pub mod protobuf_render_frame;

pub use common::*;
pub use network_render_bridge::NetworkRenderBridge;
pub use platform::ClientSession;
pub use shared::ClientInfo;
