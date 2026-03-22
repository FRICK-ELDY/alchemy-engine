//! Path: native/nif/src/nif/decode/mod.rs
//! Summary: NIF 用デコードヘルパー
//!
//! - `bert_injection`: set_frame_injection_binary 用。Erlang term バイナリをデコードして GameWorldInner に注入。
//! - `msgpack_injection`: レガシー（MessagePack 形式）。削除予定。

mod bert_injection;
#[allow(dead_code)] // レガシー参照用。削除検討中。
mod msgpack_injection;

pub use bert_injection::apply_injection_from_bert;
