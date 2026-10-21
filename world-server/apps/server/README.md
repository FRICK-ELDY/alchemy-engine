# server

OTP アプリケーションのエントリポイント。ゲームエンジンの各スーパーバイザーとワーカーを起動する。

## 責務

- Registry、Contents.Scenes.Stack、EventBus、RoomSupervisor 等の起動
- `:current` コンテンツモジュールに基づく main ルーム起動
- Supervisor ツリーの構築

## 起動フロー

1. `Application.start/2` で各種 GenServer を起動
2. `Core.RoomSupervisor.start_room(:main)` で GameEvents を開始
3. NIF 経由で Rust ゲームループが 60Hz で動作開始
