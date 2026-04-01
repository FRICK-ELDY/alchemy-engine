# network

Zenoh による高速トランスポート層。クライアント側で Elixir サーバーとの通信を担当。

## 責務（The Pipe - 導管）

- **Transport Agnostic**: 上位レイヤーには「UDP か WebSocket か」を意識させず、「データが届いた」という事実だけを伝える
- Zenoh 経由での RenderFrame 受信・入力 publish

## 構成

- `common` — トピック管理、共通処理
- `platform/` — target_os による振り分け（desktop / web）

## 依存

- `render`（Frame デコード等）
- `shared`
