//! Path: native/nif/src/formula/mod.rs
//! Summary: コンテンツ数式エンジン（ProtoFlux/Logix 風の計算グラフ実行）

mod decode;
mod opcode;
mod value;
mod vm;

pub use decode::DecodeError;
pub use value::Value;
pub use vm::{run, VmError};
