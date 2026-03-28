//! P5: `RenderFrame` protobuf のデコード検証（`render_frame_proto::decode_pb_render_frame`）。
//! NIF は `render`（wgpu 等）に依存しない。`render_frame_proto` のみをリンクする。
//! NIF 層は描画を持たないため、デコード結果を描画バッファへ渡す処理は置かない（ローカル NIF 描画は復活させない）。
//!
//! **本番想定**: ゲームループの毎フレーム必須パスではない。CI・開発時の **契約検証**、オプトインのデバッグ用途を主とする（Zenoh / クライアント `render` が消費するバイト列と同一スキーマでデコードできることの確認）。

use crate::ok;
use crate::physics::world::GameWorld;
use render_frame_proto::decode_pb_render_frame;
use rustler::{Atom, Binary, NifResult, ResourceArc};

/// Elixir が `Content.FrameEncoder.encode_frame/5` 相当で生成したバイナリをデコードし成功すれば `:ok`。
/// 実際の描画は Zenoh / クライアント `render` が担当する。
#[rustler::nif]
pub fn push_render_frame_binary(
    _world: ResourceArc<GameWorld>,
    binary: Binary,
) -> NifResult<Atom> {
    let bytes = binary.as_slice();
    if bytes.is_empty() {
        return Err(rustler::Error::Term(Box::new(
            "push_render_frame_binary: empty payload",
        )));
    }
    decode_pb_render_frame(bytes).map_err(|e| {
        rustler::Error::Term(Box::new(format!("protobuf render frame decode: {}", e)))
    })?;
    Ok(ok())
}
