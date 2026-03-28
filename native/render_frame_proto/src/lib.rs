//! `proto/render_frame.proto` のバイト列を `shared::render_frame::RenderFrame` にデコードする。
//! **wgpu / winit / egui には依存しない**（BEAM に載る NIF がこのクレートだけを引けるようにする）。
//!
//! **空ペイロード**: `prost` は空の `&[u8]` を「空のメッセージ」として **デコード成功**させうる。
//! 信頼境界では呼び出し側で拒否すること（例: NIF `push_render_frame_binary` は空バイナリを拒否）。
//! 他経路から `decode_pb_render_frame` を呼ぶときも、同じポリシーが必要か検討すること。

pub mod pb {
    include!(concat!(env!("OUT_DIR"), "/alchemy.render.rs"));
}

mod protobuf_render_frame;
pub use protobuf_render_frame::decode_pb_render_frame;
