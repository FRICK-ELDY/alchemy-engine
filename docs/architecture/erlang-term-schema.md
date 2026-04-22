# Erlang term スキーマ — Zenoh フレーム配信（レガシー ETF 参照）

> 作成日: 2026-03-23  
> 最終更新: 2026-03-28  
> ポリシー（歴史的経緯）: [zenoh-frame-serialization.md](../policy-as-code/why_adopted/zenoh-frame-serialization.md)
>
> **現在の主経路**: フレーム・injection は **protobuf** のみ（`proto/render_frame.proto`, `proto/frame_injection.proto`）。Elixir は生成モジュール経由、Rust は `prost` デコード。本章の ETF 記述は **旧バイナリ形式の参照・デバッグ用**（ワイヤ上では用いない）。
>
> フレームの意味論・フィールド対応は [draw-command-spec.md](draw-command-spec.md) および [render_frame.proto（alchemy-protocol `v0.1.1`）](https://github.com/FRICK-ELDY/alchemy-protocol/blob/v0.1.1/proto/render_frame.proto) を参照する。

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

`Content.FrameEncoder.encode_injection_map/1` は **`Alchemy.Frame.FrameInjection`** の protobuf バイナリを返す（スキーマ: `proto/frame_injection.proto`）。

### 7.2 サーバー上の適用（NIF はない）

旧 **NIF `set_frame_injection_binary`** および Rust の **`nif::protobuf_frame_injection`** は **本ブランチでは削除済み**。

`Contents.Events.Game` は `encode_injection_map/1` の結果を `apply_frame_injection_binary/2` に渡すが、**現行実装はスタブ**（`:ok` のみ。Rust NIF へバイナリを渡さない）。インジェクション map の意味論的活用は Elixir 内のコンポーネント同期・`on_nif_sync` 等に委ねる。**Rust 側に `FrameInjection` protobuf をデコードするコードは現状ない**（フレーム本体は `render_frame_proto` のみ参照）。

> **メンテナンス**: `rust/` 側に `FrameInjection` 専用デコード（クレート追加・`prost` 生成等）を入れたら、本節と §8 の参照を更新すること。

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
- `render_frame_proto::decode_pb_render_frame` — クライアント側フレーム protobuf デコード（`rust/client/render_frame_proto`）
- `Contents.Events.Game` — `apply_frame_injection_binary` スタブ（`apps/contents/lib/events/game.ex`）
