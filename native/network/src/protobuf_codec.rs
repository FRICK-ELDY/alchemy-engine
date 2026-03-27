//! protobuf エンコード/デコード（段階移行用）。
//!
//! movement / action / client_info のメッセージに加え、レガシー ETF を包む
//! `RenderFrameEnvelope`（`proto/render_frame.proto`）の encode/decode もここに置く。

use prost::Message;
use shared::ClientInfo;

#[derive(Clone, PartialEq, Message)]
struct MovementMessage {
    #[prost(float, tag = "1")]
    pub dx: f32,
    #[prost(float, tag = "2")]
    pub dy: f32,
}

#[derive(Clone, PartialEq, Message)]
struct ActionMessage {
    #[prost(string, tag = "1")]
    pub name: String,
}

#[derive(Clone, PartialEq, Message)]
struct ClientInfoMessage {
    #[prost(string, tag = "1")]
    pub os: String,
    #[prost(string, tag = "2")]
    pub arch: String,
    #[prost(string, tag = "3")]
    pub family: String,
}

#[derive(Clone, PartialEq, Message)]
struct RenderFrameEnvelope {
    #[prost(bytes = "vec", tag = "1")]
    pub payload: Vec<u8>,
}

pub fn encode_movement(dx: f32, dy: f32) -> Result<Vec<u8>, prost::EncodeError> {
    let msg = MovementMessage { dx, dy };
    let mut out = Vec::new();
    msg.encode(&mut out)?;
    Ok(out)
}

pub fn encode_action(name: &str) -> Result<Vec<u8>, prost::EncodeError> {
    let msg = ActionMessage {
        name: name.to_string(),
    };
    let mut out = Vec::new();
    msg.encode(&mut out)?;
    Ok(out)
}

pub fn encode_client_info(info: &ClientInfo) -> Result<Vec<u8>, prost::EncodeError> {
    let msg = ClientInfoMessage {
        os: info.os.to_string(),
        arch: info.arch.to_string(),
        family: info.family.to_string(),
    };
    let mut out = Vec::new();
    msg.encode(&mut out)?;
    Ok(out)
}

pub fn encode_render_frame_envelope(payload: &[u8]) -> Result<Vec<u8>, prost::EncodeError> {
    let msg = RenderFrameEnvelope {
        payload: payload.to_vec(),
    };
    let mut out = Vec::new();
    msg.encode(&mut out)?;
    Ok(out)
}

pub fn decode_render_frame_envelope(bytes: &[u8]) -> Result<Vec<u8>, prost::DecodeError> {
    let msg = RenderFrameEnvelope::decode(bytes)?;
    Ok(msg.payload)
}
