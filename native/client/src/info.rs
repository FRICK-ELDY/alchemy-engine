//! クライアント情報。shared クレートを再エクスポート。
//!
//! ClientInfo は shared の型として定義。
//! network が Zenoh で Elixir へ送信する。

pub use shared::ClientInfo;
