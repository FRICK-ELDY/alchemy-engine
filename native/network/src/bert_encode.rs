//! 互換モジュール: 既存呼び出し名 `bert_encode::*` を維持しつつ、
//! 実装は protobuf エンコードへ委譲する。

/// movement ペイロードを protobuf バイナリにエンコードする。
pub fn encode_movement(dx: f32, dy: f32) -> Result<Vec<u8>, prost::EncodeError> {
    crate::protobuf_codec::encode_movement(dx, dy)
}

/// action ペイロードを protobuf バイナリにエンコードする。
pub fn encode_action(name: &str) -> Result<Vec<u8>, prost::EncodeError> {
    crate::protobuf_codec::encode_action(name)
}
