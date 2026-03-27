# Erlang term スキーマ — Zenoh フレーム配信（レガシー ETF 参照）

> 作成日: 2026-03-23  
> 最終更新: 2026-03-27  
> ポリシー（歴史的経緯）: [zenoh-frame-serialization.md](../policy-as-code/why_adopted/zenoh-frame-serialization.md)
>
> **現在の主経路**: フレーム・injection は **protobuf**（`proto/render_frame.proto`, `proto/frame_injection.proto`）。Elixir は `Network.Proto.*`、Rust は `prost` デコード。本章は **ETF フォールバック**および旧手順の参照用。
>
> MessagePack 形式は [messagepack-schema.md](messagepack-schema.md) を参照（レガシー参照用）。

---

## 1. 概要

**運用上の既定**: Zenoh フレームは `Content.FrameEncoder.encode_frame/4` が **`Network.Proto.RenderFrame`** のバイナリを出力する。Rust `network_render_bridge` は **protobuf を先に解釈**し、失敗時に `RenderFrameEnvelope` 包み ETF → 生 ETF の順でフォールバックする。

以下の各節は、まだ **ETF（`:erlang.term_to_binary/1`）** として送受信される場合の map 構造である。Elixir の `Content.FrameEncoder`（レガシー経路）と Rust `network::bert_decode` / eetf が同一の形を扱う。

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

## 7. set_frame_injection（injection_map）

### 7.1 現在の送信形式（protobuf）

`Content.FrameEncoder.encode_injection_map/1` は **`Network.Proto.FrameInjection`** を `Protobuf.encode/1` したバイナリを返す（スキーマ: `proto/frame_injection.proto`）。

### 7.2 NIF `set_frame_injection_binary` の解釈順

1. **ペイロードが空でない**場合、まず **ネイティブ `FrameInjection` protobuf** として適用（`native/nif` の `apply_injection_from_pb`）。
2. 失敗時、**`FrameInjectionEnvelope`**（`bytes payload`）で包まれたバイナリなら内側の ETF を取り出し、`apply_injection_from_bert`。
3. それ以外は **生 ETF** として bert デコード。

空バイト列 `<<>>` は (1) を試さず、(2)(3) へ回す（誤って「空の protobuf 成功」とならないようにする）。

### 7.3 レガシー ETF スキーマ（bert 経路）

フォールバックで解釈される map。存在するキーのみ pack する（オプショナルキー）。
[messagepack-schema.md](messagepack-schema.md) §7 と構造は同一。

| キー | 型 | 説明 |
|:---|:---|:---|
| "player_input" | `[dx, dy]` | プレイヤー移動入力 |
| "player_snapshot" | `[hp, invincible_timer]` | HP と無敵タイマー |
| "elapsed_seconds" | float | 経過秒数 |
| "weapon_slots" | `[[kind_id, level, cooldown, cooldown_sec, precomputed_damage], ...]` | 武器スロット |
| "enemy_damage_this_frame" | `[[kind_id, damage], ...]` | 敵接触ダメージ |
| "special_entity_snapshot" | map | `%{"t" => "none"}` または `%{"t" => "alive", ...}` |

- Rust: `nif::decode::bert_injection::apply_injection_from_bert`

## 8. 参照

- `Content.FrameEncoder` — フレーム・injection の protobuf エンコード
- `proto/render_frame.proto`, `proto/frame_injection.proto` — 契約スキーマ
- `network::protobuf_render_frame` / `network_render_bridge` — Rust 側フレーム protobuf デコードとフォールバック
- `network::bert_decode::decode_render_frame` — ETF フォールバック用（eetf）
- `nif::decode::bert_injection::apply_injection_from_bert` — injection ETF フォールバック
