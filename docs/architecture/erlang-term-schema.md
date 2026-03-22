# Erlang term スキーマ — Zenoh フレーム配信

> 作成日: 2026-03-23  
> ポリシー: [zenoh-frame-serialization.md](../policy-as-code/why_adopted/zenoh-frame-serialization.md)
>
> **非推奨**: MessagePack 形式は [messagepack-schema.md](messagepack-schema.md) を参照（レガシー参照用）。

---

## 1. 概要

Zenoh によるフレーム配信では `:erlang.term_to_binary/1` を用いた Erlang External Term Format (ETF) を使用する。
Elixir 側 `Content.FrameEncoder` と Rust 側 `network::bert_decode` で同一の構造を扱う。

## 2. トップレベル構造

1フレーム分のバイナリは次の map 構造を `term_to_binary` したもの:

```elixir
%{
  "commands" => [draw_command, ...],
  "camera" => camera_params_map,
  "ui" => ui_canvas_map,
  "mesh_definitions" => [mesh_def_map, ...],
  "cursor_grab" => "grab" | "release"  # オプショナル
}
```

- キーは文字列（MessagePack スキーマと互換）
- `cursor_grab` は省略可能

## 3. DrawCommand ↔ ETF 型マッピング

[messagepack-schema.md](messagepack-schema.md) §3 と同一。map の `"t"` キーでタグを識別。

## 4. CameraParams ↔ ETF

[messagepack-schema.md](messagepack-schema.md) §4 と同一。

## 5. UiCanvas / UiNode / UiComponent ↔ ETF

[messagepack-schema.md](messagepack-schema.md) §5 と同一。

## 6. MeshDef ↔ ETF

[messagepack-schema.md](messagepack-schema.md) §6 と同一。

## 7. set_frame_injection（injection_map）↔ ETF

`set_frame_injection_binary` NIF が受け取るバイナリのスキーマ。
トップレベルは map。存在するキーのみ pack する（オプショナルキー）。
[messagepack-schema.md](messagepack-schema.md) §7 と構造は同一。

| キー | 型 | 説明 |
|:---|:---|:---|
| "player_input" | `[dx, dy]` | プレイヤー移動入力 |
| "player_snapshot" | `[hp, invincible_timer]` | HP と無敵タイマー |
| "elapsed_seconds" | float | 経過秒数 |
| "weapon_slots" | `[[kind_id, level, cooldown, cooldown_sec, precomputed_damage], ...]` | 武器スロット |
| "enemy_damage_this_frame" | `[[kind_id, damage], ...]` | 敵接触ダメージ |
| "special_entity_snapshot" | map | `%{"t" => "none"}` または `%{"t" => "alive", ...}` |

- Elixir: `Content.FrameEncoder.encode_injection_map/1`
- Rust: `nif::decode::bert_injection::apply_injection_from_bert`

## 8. 参照

- `Content.FrameEncoder` — Elixir 側エンコーダ（フレーム・injection_map）
- `network::bert_decode::decode_render_frame` — Rust 側フレームデコーダ（eetf クレート使用）
- `nif::decode::bert_injection::apply_injection_from_bert` — NIF 側 injection_map デコーダ
