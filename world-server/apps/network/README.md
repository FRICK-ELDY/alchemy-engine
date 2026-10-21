# network

通信レイヤー。クライアント間・サーバー間の通信を統一的に扱う。

## 責務

- **Distributed** — 複数ノード間のルーム管理（libcluster クラスタ時）
- **Local** — 同一 BEAM ノード内のローカルマルチルーム管理
- **ZenohBridge** — Zenoh フレーム publish・入力 subscribe（zenoh_enabled 時）
- **Channel** — Phoenix Channels / WebSocket（ポート 4000）
- **UDP** — UDP トランスポート（ポート 4001）

## 主要 API

- `open_room/1`, `close_room/1` — ルームの起動・停止
- `register_room/1`, `unregister_room/1` — ルーム登録
- `connect_rooms/2` — ルーム間接続

## 依存

Phoenix, phoenix_pubsub, plug_cowboy, libcluster
