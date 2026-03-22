//! Erlang term (ETF) エンコード — movement / action ペイロード
//!
//! Zenoh 経由で Elixir へ送信する movement / action を term_to_binary 相当の形式でエンコードする。

use eetf::{Binary, EncodeError, Float, Map, Term};
use std::collections::HashMap;

/// movement ペイロードを Erlang term バイナリにエンコードする。
/// 出力形式: %{"dx" => dx, "dy" => dy}（Elixir の binary_to_term で Map.get(map, "dx") が使えるよう文字列キー）
pub fn encode_movement(dx: f32, dy: f32) -> Result<Vec<u8>, EncodeError> {
    let mut map = HashMap::new();
    map.insert(
        Term::from(Binary::from(b"dx".as_slice())),
        Term::from(Float { value: dx as f64 }),
    );
    map.insert(
        Term::from(Binary::from(b"dy".as_slice())),
        Term::from(Float { value: dy as f64 }),
    );
    let term = Term::from(Map { map });
    let mut buf = Vec::new();
    term.encode(&mut buf)?;
    Ok(buf)
}

/// action ペイロードを Erlang term バイナリにエンコードする。
/// 出力形式: %{"name" => name}
pub fn encode_action(name: &str) -> Result<Vec<u8>, EncodeError> {
    let mut map = HashMap::new();
    map.insert(
        Term::from(Binary::from(b"name".as_slice())),
        Term::from(Binary::from(name.as_bytes())),
    );
    let term = Term::from(Map { map });
    let mut buf = Vec::new();
    term.encode(&mut buf)?;
    Ok(buf)
}
