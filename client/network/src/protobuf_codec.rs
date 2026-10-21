//! protobuf エンコード（movement / action / client_info）。

use crate::pb;
use prost::Message;
use shared::ClientInfo;

pub fn encode_movement(dx: f32, dy: f32) -> Result<Vec<u8>, prost::EncodeError> {
    let msg = pb::Movement { dx, dy };
    let mut out = Vec::new();
    msg.encode(&mut out)?;
    Ok(out)
}

pub fn encode_action(name: &str) -> Result<Vec<u8>, prost::EncodeError> {
    let msg = pb::Action {
        name: name.to_string(),
    };
    let mut out = Vec::new();
    msg.encode(&mut out)?;
    Ok(out)
}

pub fn encode_client_info(info: &ClientInfo) -> Result<Vec<u8>, prost::EncodeError> {
    let msg = pb::ClientInfo {
        os: info.os.to_string(),
        arch: info.arch.to_string(),
        family: info.family.to_string(),
    };
    let mut out = Vec::new();
    msg.encode(&mut out)?;
    Ok(out)
}
