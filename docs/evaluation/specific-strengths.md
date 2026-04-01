# AlchemyEngine — プラス点 詳細一覧

> 最終更新: 2026-04-01（[evaluation-2026-04-01.md](./evaluation-2026-04-01.md) に基づく）

## 採点基準

| 点数 | 基準 |
|:---:|:---|
| +1 | 正しく実装されている。問題はないが特筆するほどではない |
| +2 | 業界の一般的なベストプラクティスに沿った、良い設計判断 |
| +3 | 同規模・同種プロジェクトの平均を明確に上回る実装 |
| +4 | プロダクションレベルのゲームエンジン・OSSと比較しても遜色ない実装 |
| +5 | このクラスの個人プロジェクトでは見たことがないレベルの卓越した実装 |

---

## apps/core

### ✅ プラス点

- **ルーム単位 DynamicSupervisor** `+2`
  > `Core.RoomRegistry` と組み合わせ、`start_room` / `stop_room` でゲームループプロセスを隔離できる。  
  > 対象ファイル: `apps/core/lib/core/room_supervisor.ex`

- **FormulaStore のスコープ設計** `+3`
  > synced（ルーム＋ETS＋任意ブロードキャスト）/ local / context を分離し、Rust はキーと値の受け渡しに限定する方針が `moduledoc` に明文化されている。  
  > 対象ファイル: `apps/core/lib/core/formula_store.ex`

- **Telemetry・EventBus・StressMonitor** `+2`
  > フレームコスト・敵数・ドロップカウンタ等を `Telemetry.Metrics` に載せ、イベント配信と負荷監視プロセスを分ける。  
  > 対象ファイル: `apps/core/lib/core/telemetry.ex`, `event_bus.ex`, `stress_monitor.ex`

---

## apps/contents

### ✅ プラス点

- **Scenes.Stack** `+3`
  > シーンスタック操作 API が揃い、マルチルーム用 `room_id` 名付けと `get_scene_state` の限界注記まで含め、利用者への説明が具体的。  
  > 対象ファイル: `apps/contents/lib/scenes/stack.ex`

- **Events.Game の入力・UI ディスパッチ** `+2`
  > `move_input` / `ui_action` をビルドしたコンテキストでコンポーネントへ配信し、永続化系アクションはログのみで無視する分岐が明示的。  
  > 対象ファイル: `apps/contents/lib/events/game.ex`

---

## apps/network

### ✅ プラス点

- **Channel join のトークン検証** `+4`
  > `Network.RoomToken.verify/2` による期限・スコープ・改ざん検知の分岐と、ExUnit での網羅的検証。  
  > 対象ファイル: `apps/network/lib/network/channel.ex`, `apps/network/test/`

- **Local / Distributed / UDP** `+3`
  > 単一ノード・クラスタ・UDP をモジュール分割し、テストで接続・フレーム配信を実際に通している。  
  > 対象ファイル: `apps/network/lib/network.ex` ほか

---

## apps/server

### ✅ プラス点

- **Application 子の並びと :main ルーム起動** `+2`
  > Registry・FormulaStore・Scenes.Stack・EventBus・RoomSupervisor を起動後、`Core.RoomSupervisor.start_room(:main)` を確実に試みる。  
  > 対象ファイル: `apps/server/lib/server/application.ex`

---

## rust/nif

### ✅ プラス点

- **Formula NIF のエラー境界** `+3`
  > VM のドメインエラーは Elixir 向けタプルで返し、引数デコード失敗のみ `NifResult::Err` とする。  
  > 対象ファイル: `rust/nif/src/nif/formula_nif.rs`

---

## rust クライアント

### ✅ プラス点

- **render_frame_proto と契約テスト** `+4`
  > Protobuf から `RenderFrame` への変換を単独クレートに閉じ、ゴールデンデコードとガベージ拒否をテストで固定。  
  > 対象ファイル: `rust/client/render_frame_proto/`, `rust/client/network/tests/render_frame_e2e_contract.rs`

- **egui Save/Load のイベント優先順位** `+2`
  > `pending_action` をロードダイアログより先に処理し、同一フレームでの上書きを避ける。  
  > 対象ファイル: `rust/client/render/src/renderer/ui.rs`

---

## 横断

### ✅ プラス点

- **テストと静的解析** `+4`
  > umbrella で 102 ExUnit、Rust は契約テスト中心に成功。`cargo clippy -D warnings` と `mix credo --strict` が通過。  
  > 対象: リポジトリ全体

- **信頼境界のコメント** `+2`
  > prost の空入力成功など、バイナリ境界の落とし穴をソース先頭で警告。  
  > 対象ファイル: `rust/client/render_frame_proto/src/lib.rs`, `protobuf_render_frame.rs`

- **`mix alchemy.ci` 単一エントリ** `+1`
  > Rust / Elixir の fmt・lint・テストを直列実行し、`check` / `rust` / `elixir` で部分実行も可能。  
  > 対象ファイル: `apps/core/lib/mix/tasks/alchemy.ci.ex`, `docs/warranty/ci.md`
