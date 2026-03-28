# Erlang term スキーマ — Zenoh フレーム配信（レガシー ETF 参照）

> 作成日: 2026-03-23  
> 最終更新: 2026-03-28  
> ポリシー（歴史的経緯）: [zenoh-frame-serialization.md](../policy-as-code/why_adopted/zenoh-frame-serialization.md)
>
> **現在の主経路**: フレーム・injection は **protobuf** のみ（`proto/render_frame.proto`, `proto/frame_injection.proto`）。Elixir は生成モジュール経由、Rust は `prost` デコード。本章の ETF 記述は **旧バイナリ形式の参照・デバッグ用**（ワイヤ上では用いない）。
>
> フレームの意味論・フィールド対応は [draw-command-spec.md](draw-command-spec.md) および `proto/render_frame.proto` を参照する。

---

## 1. 概要

**運用上の既定**: Zenoh フレームは `Content.FrameEncoder.encode_frame/5` が **`Alchemy.Render.RenderFrame`** の protobuf バイナリを出力する。Rust は **`decode_pb_render_frame`** のみ（ETF フォールバックなし）。

以下の各節は、歴史的に **ETF（`:erlang.term_to_binary/1`）** で表現していた map 構造の参照である。現行ワイヤでは使用しない。

## 2. トップレベル構造

1フレーム分のバイナリは次の map 構造を `term_to_binary` したもの（**レガシー参照用**）:

```elixir
%{
  "commands" => [draw_command, ...],
  "camera" => camera_params_map,
  "ui" => ui_canvas_map,
  "mesh_definitions" => [mesh_def_map, ...],
  "cursor_grab" => "grab" | "release"  # オプショナル
}
```

- キーは文字列
- `cursor_grab` は省略可能

## 3. DrawCommand ↔ ETF 型マッピング

[draw-command-spec.md](draw-command-spec.md) のタグ・フィールドと対応する。map の `"t"` キーでタグを識別する（レガシー ETF 表現）。

## 4. CameraParams ↔ ETF

[draw-command-spec.md](draw-command-spec.md) の Camera2D / Camera3D 記述と対応。

## 5. UiCanvas / UiNode / UiComponent ↔ ETF

[draw-command-spec.md](draw-command-spec.md) の UI ツリー記述と対応。

## 6. MeshDef ↔ ETF

[draw-command-spec.md](draw-command-spec.md) の MeshDef 記述と対応。

## 7. set_frame_injection（injection_map）

### 7.1 現在の送信形式（protobuf）

`Content.FrameEncoder.encode_injection_map/1` は **`FrameInjection`** を `Protobuf.encode/1` したバイナリを返す（スキーマ: `proto/frame_injection.proto`）。

### 7.2 NIF `set_frame_injection_binary` の解釈

1. 空バイト列は **エラー**（誤った空 protobuf 成功を避ける）。
2. **`FrameInjectionEnvelope`**（`bytes payload`）としてデコードできる場合は内側 bytes のみ取り出す。
3. 得られた bytes を **`FrameInjection` protobuf** として `apply_injection_from_pb` で適用する（ETF 経路なし）。

### 7.3 レガシー ETF スキーマ（参照のみ）

旧 bert デコードが想定していた map。存在するキーのみ pack する（オプショナルキー）。

| キー | 型 | 説明 |
|:---|:---|:---|
| "player_input" | `[dx, dy]` | プレイヤー移動入力 |
| "player_snapshot" | `[hp, invincible_timer]` | HP と無敵タイマー |
| "elapsed_seconds" | float | 経過秒数 |
| "weapon_slots" | `[[kind_id, level, cooldown, cooldown_sec, precomputed_damage], ...]` | 武器スロット |
| "enemy_damage_this_frame" | `[[kind_id, damage], ...]` | 敵接触ダメージ |
| "special_entity_snapshot" | map | `%{"t" => "none"}` または `%{"t" => "alive", ...}` |

## 8. 参照

- `Content.FrameEncoder` — フレーム・injection の protobuf エンコード
- `proto/render_frame.proto`, `proto/frame_injection.proto` — 契約スキーマ
- `network::protobuf_render_frame` / `network_render_bridge` — Rust 側フレーム protobuf デコード
- `nif::protobuf_frame_injection` — injection protobuf デコード
