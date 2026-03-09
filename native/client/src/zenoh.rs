//! Zenoh 通信の窓口。network クレートを再エクスポート。
//!
//! client_desktop, client_web 等は client::zenoh 経由で利用。
//! 実装は native/network に移行済み。

pub use network::ClientSession;
