//! protobuf エンコード（movement / action / client_info）。

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
