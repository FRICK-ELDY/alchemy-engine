//! RenderFrame の protobuf デコードは `render_frame_proto` に実装され、`render` が再エクスポートする。
//! `network` は `render` 経由のみ参照し、依存グラフを一本化する。
pub use render::decode_pb_render_frame;
