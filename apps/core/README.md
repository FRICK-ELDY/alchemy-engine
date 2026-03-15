# core

SSoT（Single Source of Truth）コアエンジン。ゲームは **Core モジュール経由でのみ** エンジンとやり取りする。

## 責務

- ゲームループ制御、イベント受信
- ContentBehaviour / Component インターフェース定義
- NifBridge（Rustler NIF ラッパー）による Rust 連携
- セーブ/ロード、EventBus、FrameCache
- Formula 式評価 API
- RoomSupervisor、StressMonitor、Stats、Telemetry

## 主要モジュール

- `Core` — 公開 API エントリポイント
- `Core.NifBridge` — NIF 呼び出し
- `Core.ContentBehaviour` — コンテンツ定義インターフェース
- `Core.Component` — コンポーネントビヘイビア
- `Core.EventBus` — フレームイベント配信
- `Core.SaveManager` — セーブ/ロード
