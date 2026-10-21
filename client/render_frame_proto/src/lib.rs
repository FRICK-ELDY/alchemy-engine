//! `proto/render_frame.proto` のバイト列を `shared::render_frame::RenderFrame` にデコードする。
//! **wgpu / winit / egui には依存しない**（BEAM に載る NIF がこのクレートだけを引けるようにする）。
//!
//! **空ペイロード**: `prost` は空の `&[u8]` を「空のメッセージ」として **デコード成功**させうる。
//! 信頼境界では呼び出し側で拒否すること（空ペイロードを誤って成功扱いにしない）。
//! 他経路から `decode_pb_render_frame` を呼ぶときも、同じポリシーが必要か検討すること。

pub mod pb {
    include!(concat!(env!("OUT_DIR"), "/alchemy.render.rs"));
}

mod protobuf_render_frame;
pub use protobuf_render_frame::decode_pb_render_frame;
