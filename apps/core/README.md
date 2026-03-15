# core

SSoT（Single Source of Truth）コアエンジン。ゲームは **Core モジュール経由でのみ** エンジンとやり取りする。

## 責務

- ゲームループ制御、イベント受信
- Component インターフェース定義（コンテンツは `Contents.Behaviour.Content`（contents アプリで定義）を実装。core は実行時に Config で渡された content モジュールを参照して呼び出す）
- NifBridge（Rustler NIF ラッパー）による Rust 連携
- セーブ/ロード、EventBus、FrameCache
- Formula 式評価 API
- RoomSupervisor、StressMonitor、Stats、Telemetry

## 主要モジュール

- `Core` — 公開 API エントリポイント
- `Core.NifBridge` — NIF 呼び出し
- コンテンツ契約は contents の `Contents.Behaviour.Content`。core は `Core.Config.current/0` で content モジュールを参照
- `Core.Component` — コンポーネントビヘイビア
- `Core.EventBus` — フレームイベント配信
- `Core.SaveManager` — セーブ/ロード
