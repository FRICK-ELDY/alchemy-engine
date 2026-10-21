//! Zenoh / UDP と同じ RoomToken 封筒。
//!
//! `<<token_len::16-big, token::binary-size(token_len), protobuf::binary>>`
//! world-server の `Network.RoomAuth.wrap_payload/2` と対になる。

/// RoomToken の上限。サーバ側 `@max_token_bytes` と同じ。
pub const MAX_ROOM_TOKEN_BYTES: usize = 1000;

/// RoomToken 付きペイロードを組み立てる。
pub fn wrap_room_payload(token: &str, protobuf: &[u8]) -> Result<Vec<u8>, &'static str> {
    if token.is_empty() || token.len() > MAX_ROOM_TOKEN_BYTES {
        return Err("room token length out of range");
    }
    let mut out = Vec::with_capacity(2 + token.len() + protobuf.len());
    let len = u16::try_from(token.len()).map_err(|_| "room token length out of range")?;
    out.extend_from_slice(&len.to_be_bytes());
    out.extend_from_slice(token.as_bytes());
    out.extend_from_slice(protobuf);
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn wraps_length_prefix_and_body() {
        let wrapped = wrap_room_payload("abc", &[1, 2, 3]).unwrap();
        assert_eq!(wrapped, vec![0, 3, b'a', b'b', b'c', 1, 2, 3]);
    }

    #[test]
    fn rejects_empty_token() {
        assert!(wrap_room_payload("", &[0]).is_err());
    }
}
