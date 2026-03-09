//! network - Zenoh による通信層
//!
//! 上位レイヤーには「UDP か WebSocket か」を意識させず、
//! 「データが届いた」という事実だけを伝える。

pub mod common;
pub mod platform;

pub use common::*;
pub use platform::ClientSession;
