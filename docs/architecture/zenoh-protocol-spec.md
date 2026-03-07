# Zenoh プロトコル仕様（クライアント・サーバー分離）

> 作成日: 2026-03-07  
> 出典: [client-server-separation-procedure.md](../plan/client-server-separation-procedure.md) フェーズ 1  
> 目的: サーバー（Elixir）とクライアント（Rust exe）間の Zenoh 経由プロトコルを定義する

---

## 1. 概要

クライアント・サーバー分離後、60Hz フレーム配信と入力を Zenoh（UDP/QUIC ベース）で行う。本仕様は以下のペイロード形式を定義する。


| 種別       | キー                                   | 方向            | 信頼性        |
| -------- | ------------------------------------ | ------------- | ---------- |
| フレーム     | `game/room/{room_id}/frame`          | サーバー → クライアント | —          |
| 移動入力     | `game/room/{room_id}/input/movement` | クライアント → サーバー | Unreliable |
| UI アクション | `game/room/{room_id}/input/action`   | クライアント → サーバー | Reliable   |


---

## 2. フレームペイロード（`game/room/{room_id}/frame`）

### 2.1 ベース構造

`push_render_frame_binary` NIF が受け取る MessagePack バイナリをベースとする。トップレベルは [messagepack-schema.md](messagepack-schema.md) の §2 を参照。ネットワーク配信用に以下を拡張する。

### 2.2 トップレベル map


| キー                 | 形式                                     | 必須  | 説明                                                                      |
| ------------------ | -------------------------------------- | --- | ----------------------------------------------------------------------- |
| `commands`         | MessagePack 配列                         | ✓   | DrawCommand リスト。スキーマは [messagepack-schema.md](messagepack-schema.md) §3 |
| `camera`           | MessagePack map                        | ✓   | Camera2D / Camera3D パラメータ。同上 §4                                         |
| `ui`               | MessagePack map                        | ✓   | UiCanvas。同上 §5                                                          |
| `mesh_definitions` | MessagePack 配列                         | ✓   | メッシュ定義リスト。同上 §6                                                         |
| `cursor_grab`      | `"grab"` | `"release"` | `"no_change"` | —   | カーソル固定。省略時は `"no_change"`                                               |
| `frame_id`         | u32                                    | —   | フレーム識別（将来のオーバーフロー・欠損検出用）                                                |
| `player_interp`    | map（下記）                                | —   | クライアント側プレイヤー補間用。2D のみ。省略可                                               |


### 2.3 player_interp（オプション）

2D シーンでクライアントがサーバーから受け取る tick と座標をもとに、描画側でプレイヤーを補間するために使用する。


| キー             | 型     | 説明                        |
| -------------- | ----- | ------------------------- |
| `prev_tick_ms` | u64   | 1 tick 前の時刻（milliseconds） |
| `curr_tick_ms` | u64   | 現在 tick の時刻               |
| `prev_x`       | float | 1 tick 前のプレイヤー X          |
| `prev_y`       | float | 1 tick 前のプレイヤー Y          |
| `curr_x`       | float | 現在 tick のプレイヤー X          |
| `curr_y`       | float | 現在 tick のプレイヤー Y          |


クライアントは `alpha = (now_ms - prev_tick_ms) / (curr_tick_ms - prev_tick_ms)` を計算し、`lerp(prev, curr, alpha)` で描画位置を決定する。

**対応元**: サーバー側の `GameWorldInner`（`prev_tick_ms`, `curr_tick_ms`, `prev_player_x/y`, `player.x/y`）。

### 2.4 同一プロセスとの関係

- **ローカル描画（NIF 内）**: `push_render_frame_binary(frame_binary, cursor_grab)` で `commands`, `camera`, `ui`, `mesh_definitions` を渡す。`cursor_grab` は NIF の別引数。
- **リモート配信（Zenoh）**: 上記に `cursor_grab` を map に含め、オプションで `frame_id`, `player_interp` を追加して MessagePack で publish する。
- Elixir の `Content.MessagePackEncoder.encode_frame/4` 出力に `cursor_grab`, `frame_id`, `player_interp` を付与すればそのまま Zenoh ペイロードとして利用可能。

---

## 3. 入力ペイロード

### 3.1 movement（`game/room/{room_id}/input/movement`）

**形式**: MessagePack map


| キー   | 型     | 説明               |
| ---- | ----- | ---------------- |
| `dx` | float | 移動 X（-1.0 〜 1.0） |
| `dy` | float | 移動 Y（-1.0 〜 1.0） |


**Phoenix Channel 互換**: `"input"` イベントの `%{"dx" => dx, "dy" => dy}` と同一。

**サーバー側受け手**: `Contents.GameEvents` に `{:move_input, dx, dy}` として送信。既存の `handle_info({:move_input, dx, dy}, state)` で処理。

### 3.2 action（`game/room/{room_id}/input/action`）

**形式**: MessagePack map


| キー        | 型      | 必須  | 説明                                                       |
| --------- | ------ | --- | -------------------------------------------------------- |
| `name`    | string | ✓   | アクション名（例: `"select_weapon"`, `"__save__"`, `"__load__"`） |
| `payload` | map    | —   | 追加パラメータ。将来拡張用                                            |


**Phoenix Channel 互換**: `"action"` イベントの `%{"name" => name, ...}` と同一。`name` が必須である点も同じ。

**サーバー側受け手**: `Contents.GameEvents` に `{:ui_action, name}` として送信。`payload` は現行 GameEvents では未使用。将来的に `{:ui_action, name, payload}` へ拡張可能。

**既存 action 例**: `select_weapon`, `__save_`_, `__load__`, `__load_confirm__`, `__load_cancel__`, `__skip__`

---

## 4. Phoenix Channel / GameEvents との対応


| 経路                 | イベント | ペイロード例                                           | GameEvents への変換                 |
| ------------------ | ---- | ------------------------------------------------ | ------------------------------- |
| Phoenix `"input"`  | C→S  | `%{"dx" => 0.5, "dy" => -1.0}`                   | `{:move_input, 0.5, -1.0}`      |
| Zenoh movement     | C→S  | `%{"dx" => 0.5, "dy" => -1.0}`                   | `{:move_input, 0.5, -1.0}`      |
| Phoenix `"action"` | C→S  | `%{"name" => "select_weapon"}`                   | `{:ui_action, "select_weapon"}` |
| Zenoh action       | C→S  | `%{"name" => "select_weapon", "payload" => %{}}` | `{:ui_action, "select_weapon"}` |


フェーズ 3 で Zenohex subscriber が movement / action を受信したら、上記と同様の形式で `GameEvents` に `send(pid, ...)` する。既存の `handle_info({:move_input, ...})` および `handle_info({:ui_action, ...})` をそのまま利用可能。

---

## 5. 将来拡張


| 項目                   | 説明                                       | 優先度 |
| -------------------- | ---------------------------------------- | --- |
| **raw_key**          | キーコード・押下/解放の個別イベント。現在は movement のみ       | 低   |
| **cursor_grab（入力側）** | クライアントから「カーソル固定したい」等の要求。現状はフレーム側でサーバーが指示 | 低   |
| **action payload**   | `select_weapon` の武器 ID 等を payload で渡す    | 中   |
| **frame_id 検証**      | 欠損・順序逆転の検出・統計                            | 中   |


---

## 6. 関連ドキュメント

- [client-server-separation-procedure.md](../plan/client-server-separation-procedure.md) — 分離手順
- [messagepack-schema.md](messagepack-schema.md) — フレームバイナリ形式
- [network-protocol-current.md](network-protocol-current.md) — 既存 Channel / UDP プロトコル
- [draw-command-spec.md](draw-command-spec.md) — DrawCommand タグ・フィールド
- [Network.Channel](../../apps/network/lib/network/channel.ex) — Phoenix input/action ハンドラ

