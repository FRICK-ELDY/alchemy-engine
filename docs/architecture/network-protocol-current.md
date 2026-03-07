# 既存ネットワークプロトコル仕様

> 作成日: 2026-03-07  
> 出典: [client-server-separation-procedure.md](../plan/client-server-separation-procedure.md) フェーズ 0.2  
> 目的: 現状の Network.Channel と Network.UDP のプロトコル形式を文書化する

---

## 1. 概要

本ドキュメントは、クライアント・サーバー分離前の既存プロトコル仕様を記述する。
フェーズ 3 で Zenoh 経路を追加する際の参照として使用する。

### 接続状況

**注意**: 現状、`Contents.GameEvents` は `{:frame_events, events}` を受信するが、これを `Network.Channel` や `Network.UDP` に転送する経路は **本番フローには未接続** である。
Channel の `handle_info({:frame_events, events}, socket)` や `Network.UDP.broadcast_frame/2` は実装済みだが、GameEvents から呼ばれていない。
テストでは直接 `broadcast_frame` を呼び出して検証している。フェーズ 3 で Zenoh 経路とあわせて接続を行う。

---

## 2. Network.Channel（Phoenix WebSocket）

### 2.1 クライアント → サーバー

| イベント | ペイロード | 説明 |
|:---|:---|:---|
| `"input"` | `%{"dx" => 0.5, "dy" => -1.0}` | 移動入力。dx/dy は省略可（省略時は 0.0）。数値または整数 |
| `"action"` | `%{"name" => "select_weapon", ...}` | UI アクション。`name` 必須 |
| `"ping"` | `%{}` | 疎通確認 |

### 2.2 サーバー → クライアント

| イベント | ペイロード | 説明 |
|:---|:---|:---|
| `"frame"` | `%{"events" => [encoded_event, ...]}` | フレームイベント配信 |
| `"room_event"` | `%{"from" => "room_b", "data" => ...}` | ルーム間ブロードキャスト |
| `"pong"` | `%{"ts" => 1234567890}` | ping への応答 |
| `"error"` | `%{"reason" => "room_not_found"}` | エラー通知 |

### 2.3 frame の events エンコード

- タプル → リスト: `{:enemy_killed, 1, 10, 20}` → `["enemy_killed", 1, 10, 20]`
- アトム → 文字列: `:enemy_killed` → `"enemy_killed"`
- **DrawCommand は含まない**: `"frame"` の `events` は **frame_events（物理イベント）のみ**

---

## 3. Network.UDP.Protocol

### 3.1 パケット形式

全パケット共通ヘッダー:

```
<<type::8, seq::32, payload::binary>>
```

| フィールド | サイズ | 説明 |
|:---|:---|:---|
| `type` | 1 byte | パケット種別 |
| `seq` | 4 byte | シーケンス番号（big-endian uint32） |
| `payload` | 可変 | 種別ごとのペイロード |

### 3.2 パケット種別

| 値 | 名前 | 方向 | payload |
|:---|:---|:---|:---|
| `0x01` | `:join` | C→S | `room_id` (binary) |
| `0x02` | `:join_ack` | S→C | `room_id` (binary) |
| `0x03` | `:leave` | C→S | `room_id` (binary) |
| `0x04` | `:input` | C→S | `<<dx::float-64, dy::float-64>>` |
| `0x05` | `:action` | C→S | `name` (binary) |
| `0x06` | `:frame` | S→C | zlib 圧縮した Erlang term（`term_to_binary(events)` を `:zlib.compress`） |
| `0x07` | `:ping` | C→S | なし |
| `0x08` | `:pong` | S→C | `<<ts::64>>` |
| `0x09` | `:error` | S→C | `reason` (binary) |

### 3.3 frame パケットのペイロード

- `events` は frame_events のリスト（Erlang term）
- `term_to_binary(events)` を `:zlib.compress()` したバイナリ
- **DrawCommand は含まない**: 物理イベントのみ

### 3.4 FrameEvent の種類（Rust → Elixir 変換後）

| Elixir タプル例 | 説明 |
|:---|:---|
| `{:enemy_killed, enemy_kind, x_bits, y_bits, 0}` | 敵撃破 |
| `{:player_damaged, damage_u32, 0, 0, 0}` | プレイヤー被弾 |
| `{:item_pickup, item_kind, value, 0, 0}` | アイテム取得 |
| `{:boss_defeated, 0, x_bits, y_bits, 0}` | ボス撃破 |
| `{:boss_spawn, entity_kind, 0, 0, 0}` | ボス出現 |
| `{:boss_damaged, damage_u32, 0, 0, 0}` | ボス被弾 |
| `{:weapon_cooldown_updated, kind_id, timer_bits, 0, 0}` | 武器クールダウン更新 |

---

## 4. DrawCommand の扱い

**DrawCommand は現行の Channel / UDP プロトコルには含まれていない。**

DrawCommand は Elixir の RenderComponent が組み立て、`push_render_frame` / `push_render_frame_binary` で NIF の RenderFrameBuffer に書き込む。同一プロセス内の描画スレッドのみで使用され、ネットワークには送信されていない。

Zenoh 経由のフレーム配信（フェーズ 1 以降）では、MessagePack 形式の DrawCommand を含むフレームペイロードを送信する設計。スキーマは [messagepack-schema.md](messagepack-schema.md) を参照。

---

## 5. 関連ドキュメント

- [Network.Channel](../../apps/network/lib/network/channel.ex)
- [Network.UDP.Protocol](../../apps/network/lib/network/udp/protocol.ex)
- [client-server-separation-procedure.md](../plan/client-server-separation-procedure.md)
- [messagepack-schema.md](messagepack-schema.md)
