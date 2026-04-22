# Zenoh プロトコル仕様（クライアント・サーバー分離）

> 作成日: 2026-03-07  
> 出典: [client-server-separation-procedure.md](../plan/completed/client-server-separation-procedure.md) フェーズ 1  
> 目的: サーバー（Elixir）とクライアント（Rust exe）間の Zenoh 経由プロトコルを定義する

---

## 1. 概要

クライアント・サーバー分離後、60Hz フレーム配信と入力を Zenoh（UDP/QUIC ベース）で行う。ワイヤ上のペイロードは **protobuf** のみ。

| 種別       | キー                                   | 方向            | 信頼性        |
| -------- | ------------------------------------ | ------------- | ---------- |
| フレーム     | `game/room/{room_id}/frame`          | サーバー → クライアント | —          |
| 移動入力     | `game/room/{room_id}/input/movement` | クライアント → サーバー | Unreliable |
| UI アクション | `game/room/{room_id}/input/action`   | クライアント → サーバー | Reliable   |

---

## 2. フレームペイロード（`game/room/{room_id}/frame`）

### 2.1 形式

- **protobuf** の `alchemy.render.RenderFrame`（[render_frame.proto（alchemy-protocol `v0.1.1`）](https://github.com/FRICK-ELDY/alchemy-protocol/blob/v0.1.1/proto/render_frame.proto)）。
- Elixir は `Content.FrameEncoder.encode_frame/5` が生成するバイナリを publish する。
- Rust は `render_frame_proto::decode_pb_render_frame`（または `network` / `render` の再エクスポート）でデコードする。

意味論・フィールドは [draw-command-spec.md](draw-command-spec.md) および [render_frame.proto（alchemy-protocol `v0.1.1`）](https://github.com/FRICK-ELDY/alchemy-protocol/blob/v0.1.1/proto/render_frame.proto) を参照。

### 2.2 オプション拡張（将来）

トップレベル `.proto` に追加する形で、`cursor_grab` 以外に `frame_id` やプレイヤー補間用フィールドを載せる場合は、スキーマ変更と Elixir/Rust 双方の追随が必要。

### 2.3 サーバー NIF との関係

- **描画はサーバー NIF が持たない。** `Core.NifBridge` は `run_formula_bytecode/3` のみ。実際の描画は Zenoh を subscribe するクライアント（Rust `app` / `render`）が行う。
- 同一バイト列のデコード検証はクライアント側の `decode_pb_render_frame`（またはテスト）で行う。

---

## 3. 入力ペイロード

### 3.1 movement（`game/room/{room_id}/input/movement`）

**形式**: protobuf `alchemy.input.Movement`（[input_events.proto（alchemy-protocol `v0.1.1`）](https://github.com/FRICK-ELDY/alchemy-protocol/blob/v0.1.1/proto/input_events.proto)）。フィールド `dx`, `dy`（float）。

**Phoenix Channel 互換**: `"input"` イベントの `%{"dx" => dx, "dy" => dy}` と意味的に同一。

**サーバー側受け手**: `Contents.Events.Game` に `{:move_input, dx, dy}` として送信。

### 3.2 action（`game/room/{room_id}/input/action`）

**形式**: protobuf `alchemy.input.Action`（`name` 文字列）。

**Phoenix Channel 互換**: `"action"` イベントの `%{"name" => name, ...}` と同一の意味。

**サーバー側受け手**: `Contents.Events.Game` に `{:ui_action, name}` として送信。

---

## 4. Phoenix Channel / Contents.Events.Game との対応

| 経路                 | イベント | ペイロード例                                           | Contents.Events.Game への変換                 |
| ------------------ | ---- | ------------------------------------------------ | ------------------------------- |
| Phoenix `"input"`  | C→S  | `%{"dx" => 0.5, "dy" => -1.0}`                   | `{:move_input, 0.5, -1.0}`      |
| Zenoh movement     | C→S  | protobuf `Movement`                             | `{:move_input, dx, dy}`         |
| Phoenix `"action"` | C→S  | `%{"name" => "select_weapon"}`                   | `{:ui_action, "select_weapon"}` |
| Zenoh action       | C→S  | protobuf `Action`                               | `{:ui_action, name}`            |

フェーズ 3 で Zenohex subscriber が movement / action を受信したら、上記と同様の形式で `Contents.Events.Game` に `send(pid, ...)` する。

---

## 5. 将来拡張

| 項目                   | 説明                                       | 優先度 |
| -------------------- | ---------------------------------------- | --- |
| **raw_key**          | キーコード・押下/解放の個別イベント。現在は movement のみ       | 低   |
| **cursor_grab（入力側）** | クライアントから「カーソル固定したい」等の要求。現状はフレーム側でサーバーが指示 | 低   |
| **action payload**   | `Action` メッセージへの追加フィールド（`proto` 拡張）    | 中   |
| **frame_id 検証**      | 欠損・順序逆転の検出・統計                            | 中   |

---

## 6. 関連ドキュメント

- [client-server-separation-procedure.md](../plan/completed/client-server-separation-procedure.md) — 分離手順（未実施項目は [client-server-separation-future.md](../plan/reference/client-server-separation-future.md)）
- [network-protocol-current.md](network-protocol-current.md) — 既存 Channel / UDP プロトコル
- [draw-command-spec.md](draw-command-spec.md) — DrawCommand タグ・フィールド
- [render_frame.proto（alchemy-protocol `v0.1.1`）](https://github.com/FRICK-ELDY/alchemy-protocol/blob/v0.1.1/proto/render_frame.proto) — フレーム protobuf 定義
- [Network.Channel](../../apps/network/lib/network/channel.ex) — Phoenix input/action ハンドラ
