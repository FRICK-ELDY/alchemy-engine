# 既存ネットワークプロトコル仕様

> **ステータス**: 現行実装の記述  
> **目標**: [architecture-v2/](../architecture-v2/)  
> **決定済みの上書き**: [diff-from-v1.md](../architecture-v2/diff-from-v1.md) §2.1（特に **C9**: Network Transport = Zenoh 一本化。独自 UDP / 空間同期用 Phoenix は廃止方向。OSC over UDP は Device Input Edge としてクライアント局所に存続）を優先  
> **読む順**: [architecture-v2/README.md](../architecture-v2/README.md)

> 作成日: 2026-03-07  
> 出典: [client-server-separation-procedure.md](../plan/completed/client-server-separation-procedure.md) フェーズ 0.2  
> 目的: 現状の Network.Channel と Network.UDP のプロトコル形式を文書化する（**歴史・現行コード参照**。目標転送経路は Zenoh）  
> 最終更新: 2026-10-23 — §0 に C9（Network Transport / Device Input Edge）追記

---

## 0. 目標転送方針（v2 決定・C9 / D6）

> **正**: [diff-from-v1.md §2.1 / C9](../architecture-v2/diff-from-v1.md)

| 層 | 範囲 | 方針 |
|:---|:---|:---|
| **Network Transport** | クライアント ⇔ サーバー／ホスト間 | **Zenoh に完全一本化**。空間状態・入力・RenderFrame は Zenoh + Protobuf |
| **Device Input Edge** | トラッカー ⇔ クライアント（局所） | **OSC over UDP**（127.0.0.1 / LAN）をクライアントが受信 → 検証・Protobuf 化 → **Zenoh で送信** |

**廃止方向（D6）**: `Network.UDP.Protocol`、空間同期を担う Phoenix Channel を前面に出す経路。  
**存続**: クライアント上の OSC 受信。world-server が OSC/UDP を直接受けて空間同期することはしない。

以下 §1 以降は **現行コード／歴史**の記録であり、目標経路ではない。

---

## 1. 概要

本ドキュメントは、クライアント・サーバー分離前の既存プロトコル仕様を記述する。
フェーズ 3 で Zenoh 経路を追加する際の参照として使用する。

### 接続状況

**注意**: 現状、`Contents.Events.Game` は `{:frame_events, events}` を受信するが、これを `Network.Channel` や `Network.UDP` に転送する経路は **本番フローには未接続** である。
Channel の `handle_info({:frame_events, events}, socket)` や `Network.UDP.broadcast_frame/2` は実装済みだが、`Contents.Events.Game` から呼ばれていない。
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

**DrawCommand は現行の Channel / UDP プロトコルには含まれていない**（物理イベントのみ）。

DrawCommand は Elixir の Render コンポーネントが組み立て、`Contents.FrameEncoder.encode_frame/6` で **protobuf**（[render_frame.proto（alchemy-protocol `v0.1.1`）](https://github.com/FRICK-ELDY/alchemy-protocol/blob/v0.1.1/proto/render_frame.proto)）にし、`FrameBroadcaster.put` 経由で Zenoh の `game/room/{room_id}/frame` へ publish する。クライアント（Rust `app`）が subscribe し、`render_frame_proto::decode_pb_render_frame` でデコードして描画する。サーバー側 NIF は描画を持たない（`Core.NifBridge` は Formula VM のみ）。過去の MessagePack 専用ドキュメントを参照していたブックマークは [draw-command-spec.md](draw-command-spec.md) および本節へ置き換え。


スキーマは [draw-command-spec.md](draw-command-spec.md)、[zenoh-protocol-spec.md](zenoh-protocol-spec.md)、[render_frame.proto（alchemy-protocol `v0.1.1`）](https://github.com/FRICK-ELDY/alchemy-protocol/blob/v0.1.1/proto/render_frame.proto) を参照。

---

## 5. 関連ドキュメント

- [Network.Channel](../../../apps/network/lib/network/channel.ex)
- [Network.UDP.Protocol](../../../apps/network/lib/network/udp/protocol.ex)
- [client-server-separation-procedure.md](../../3_done/client-server-separation-procedure.md)（未実施項目は [client-server-separation-future.md](../plan/reference/client-server-separation-future.md)）
- [zenoh-protocol-spec.md](zenoh-protocol-spec.md)
- [draw-command-spec.md](draw-command-spec.md)
