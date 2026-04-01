# AlchemyEngine — 総合評価レポート（2026-04-01）

> 検証方針: 過去の評価文書に依存せず、リポジトリのソースと個別コマンド（`mix test` / `cargo test` / `cargo clippy -D warnings` / `mix credo --strict` / `mix compile --warnings-as-errors` 等）で現状を確認した。ローカル CI 一括は **`mix alchemy.ci`**（[docs/warranty/ci.md](../warranty/ci.md)）。  
> 2026-03 系の日付付き評価レポートは `docs/evaluation/archive/` に移動済み。

---

## 検証ログ（この環境）

| チェック | 結果 |
|:---|:---|
| `mix compile --warnings-as-errors` | 成功 |
| `mix test`（umbrella 全体） | **102 テスト**、失敗 0（core 29 + network 59 + contents 14。server はテスト無し） |
| `cargo clippy --all-targets -- -D warnings` | 成功 |
| `cargo test`（`rust/` ワークスペース） | 契約テスト含め成功（`render_frame_proto` 2、`network` 1 等） |
| `mix credo --strict` | 指摘 0 |
| `mix format --check-formatted` | 成功 |
| `mix alchemy.ci` | 単一エントリのローカル CI（`apps/core/lib/mix/tasks/alchemy.ci.ex`）。`rust` / `elixir` / `check` で部分実行可。手順は [docs/warranty/ci.md](../warranty/ci.md)、[development.md](../../development.md) 参照 |

`.cursor/rules/evaluation.mdc` は歴史的に `bin/ci.bat` を言及しているが、**本リポジトリの正は `mix alchemy.ci`** である。

---

## ネットワーク想定のセーブ／ロードについて（方針との整合）

クライアント UI から `__save__` / `__load__` 等が送られても、サーバー側 `Contents.Events.Game` は **ローカル永続化を意図的に行わず**、ログに「network TBD」と残して状態を変えない。

```103:117:apps/contents/lib/events/game.ex
  def handle_info({:ui_action, action}, state) when is_binary(action) do
    new_state =
      case action do
        "__save__" ->
          Logger.info("[PERSIST] save ignored (local persistence disabled; network TBD)")
          state

        "__load__" ->
          Logger.info("[PERSIST] load ignored (local persistence disabled; network TBD)")
          state

        "__load_confirm__" ->
          Logger.info("[PERSIST] load confirm ignored (local persistence disabled; network TBD)")
          state
```

オンラインゲームでは「誰のセーブか」「改ざん」「競合」「リコンシリエーション」を決めないままローカルファイルや単純 HMAC だけを足すより、**現状の「未実装を明示」**の方が安全。今後はサーバー権威のスナップショット＋バージョン・プレイヤー ID・リプレイ検証など、別 ADR で取り決めるのが妥当。

---

## 技術評価層 — apps/core

### ✅ プラス点

- **ルーム単位の OTP 境界** `+2`  
  `DynamicSupervisor` + `Registry` でルームプロセスを分離し、`start_room` / `stop_room` が明示的。  
  > 対象: `apps/core/lib/core/room_supervisor.ex`

- **FormulaStore（synced / local / context）** `+3`  
  ETS と `LocalBackend`、synced 更新のブロードキャストフックを `config` で差し替え可能にし、**Elixir がストアの SSoT**、Rust は受け渡しに徹する方針が一貫している。  
  > 対象: `apps/core/lib/core/formula_store.ex`

- **Telemetry・EventBus・StressMonitor** `+2`  
  `game.tick.*` メトリクス、購読者への `{:game_events, events}` 配信、監視プロセスの分離がそろっており、運用時の観測点が取りやすい。  
  > 対象: `apps/core/lib/core/telemetry.ex`, `event_bus.ex`, `stress_monitor.ex`

### ❌ マイナス点

- **（該当弱め）NIF 表面積の縮小** `-1`  
  現行 `rust/nif` は Formula VM のみ。旧来の physics / world NIF が無いため、「SIMD・決定論的物理」の実証は **このツリーからは読み取れない**（意図的削除は `rust/nif/src/lib.rs` に記載）。エンジン価値の主張軸が Formula＋配信パイプライン側に寄っている。  
  > 対象: `rust/nif/src/lib.rs`

**小計: +7 / -1 = +6**

---

## 技術評価層 — apps/contents

### ✅ プラス点

- **Scenes.Stack の API とドキュメント** `+3`  
  `push` / `pop` / `replace` / `update_current`、マルチルーム用 `room_id` 名付け、`get_scene_state` の限界の注記まで含め、保守者向けの説明が厚い。  
  > 対象: `apps/contents/lib/scenes/stack.ex`

- **Events.Game のディスパッチと物理シーンゲート** `+2`  
  コンポーネントへ `move_input` / `ui_action` をコンテキスト付きで配り、`physics_scenes` に属する場合のみ `on_physics_process` を回す分離が明確。  
  > 対象: `apps/contents/lib/events/game.ex`

### ❌ マイナス点

- **（軽微）Diagnostics とコンテンツ知識** `-1`  
  ログ用に playing 状態のキーを直接触る経路は残りうる（旧評価の I-M と同系）。完全な汎用化は未了。  
  > 対象: `apps/contents/lib/events/game/diagnostics.ex`

**小計: +5 / -1 = +4**

---

## 技術評価層 — apps/network

### ✅ プラス点

- **Channel join のスコープ付きトークン** `+4`  
  `Network.RoomToken.verify/2` で missing / expired / invalid / scope_mismatch を分岐し、ExUnit で網羅的に検証している。  
  > 対象: `apps/network/lib/network/channel.ex`、テスト群 `apps/network/test/`

- **Local / Distributed / UDP の併存** `+3`  
  同一ノードのマルチルーム、クラスタ委譲、UDP プロトコルがモジュール分割され、テストが実際のメッセージフローを踏む。  
  > 対象: `apps/network/lib/network.ex` ほか

### ❌ マイナス点

- （該当なし — 評価時点で `UserSocket` moduledoc が Channel 実装と矛盾していたが、**本セッションで connect 段階と join 段階の説明に修正済み**。）

**小計: +7 / 0 = +7**

---

## 技術評価層 — apps/server

### ✅ プラス点

- **起動シーケンスの明示** `+2`  
  Registry・FormulaStore・Scenes.Stack・EventBus・RoomSupervisor・監視系を `one_for_one` で起動し、続けて `:main` ルームを `start_room`。失敗時は `raise` で早期に気づける。  
  > 対象: `apps/server/lib/server/application.ex`

### ❌ マイナス点

- **server アプリに ExUnit が無い** `-1`  
  統合起動の回帰は umbrella 全体テストに依存し、server 単体の境界テストが無い。

**小計: +2 / -1 = +1**

---

## 技術評価層 — rust/nif（Formula）

### ✅ プラス点

- **ドメインエラーと NIF 異常の分離** `+3`  
  `run_formula_bytecode` は VM のドメイン失敗を `Ok({:error, ...})` で返し、デコード失敗のみ `NifResult::Err` としている。BEAM クラッシュリスクを下げる明確な境界。  
  > 対象: `rust/nif/src/nif/formula_nif.rs`

**小計: +3 / 0 = +3**

---

## 技術評価層 — rust クライアント（shared / render_frame_proto / network / render）

### ✅ プラス点

- **Protobuf → RenderFrame の専用クレートと契約テスト** `+4`  
  空ペイロードやガベージ拒否、ゴールデンバイナリのデコードを `tests/` で固定。`decode_pb_render_frame` の緩いデコード方針もコメントで明示。  
  > 対象: `rust/client/render_frame_proto/`、`rust/client/network/tests/render_frame_e2e_contract.rs`

- **UI 層の Save/Load 操作順序** `+2`  
  `pending_action` をロードダイアログより先に確定させ、同一フレームの競合を避けるコメント付き実装。  
  > 対象: `rust/client/render/src/renderer/ui.rs`

### ❌ マイナス点

- **（軽微）クレート単体のユニット密度** `-1`  
  多くのクレートでテストが契約系に集中。描画・ウィンドウ結合の自動テストは薄い（ゲームクライアントとしては一般的だが改善余地）。

**小計: +6 / -1 = +5**

---

## 横断評価層

### ✅ プラス点

- **テスト＋静的解析の一貫性** `+4`  
  102 ExUnit + Rust 契約テスト + clippy `-D warnings` + credo strict が通る。個人／小チーム規模としては高水準。

- **プロトコルとコメントの「信頼境界」意識** `+2`  
  prost の空デコード問題などをライブラリ先頭で警告しており、セキュリティ・整合性の議論を後続でしやすい。

- **`mix alchemy.ci` による単一エントリ** `+1`  
  `Mix.Tasks.Alchemy.Ci` が Rust（fmt / clippy / test）と Elixir（format / credo / `mix test --warnings-as-errors`）を直列化し、GHA 相当をローカルで再現できる。フィルタ引数で部分実行も可能。  
  > 対象: `apps/core/lib/mix/tasks/alchemy.ci.ex`, `docs/warranty/ci.md`

### ❌ マイナス点

- （該当なし）

### 💡 提案 `0`

- **オンライン永続化 ADR**（プレイヤー ID、サーバー権威、競合、暗号化／署名の所在）

**小計: +7 / 0 = +7（提案 1 件）**

---

## 採点合算（本レポートの集計）

| 層 | 小計 |
|:---|:---:|
| core | +6 |
| contents | +4 |
| network | +7 |
| server | +1 |
| rust nif | +3 |
| rust client | +5 |
| 横断 | +7 |
| **合計** | **+33** |

※ 加点・減点は [evaluation.mdc](../../.cursor/rules/evaluation.mdc) の目安に従い、**同じ事象を二重に減点しない**よう整理した。  
※ Network の `-2` は `UserSocket` 文書修正により相殺。**単一 CI** は `mix alchemy.ci` が存在するため旧稿の `bin/ci.bat` 欠如による `-1` を撤回し、タスク整備を `+1` として反映した（合計 **+33**）。

---

## 総評（忌憚なく）

**強み**は、Elixir 側のルーム／ストア／配信設計と、Rust 側の **Formula VM + Protobuf レンダリングパイプライン**が一体で動き、テストと静的解析で守られている点である。Network 層は Channel・UDP・ローカル接続テストが揃っており、「ネットワークゲームの土台」を語れる密度になっている。

**弱み**は、旧来ドキュメントや `.cursor` 評価ルールが想定する **`native/nif/physics` 系のコードパスが現行ツリーに存在しない**こと、および **`.cursor` 側がまだ `bin/ci.bat` を前提にしている**点である（実装の正は `mix alchemy.ci`）。また **永続化は意図的に未実装**であり、ユーザーの方針（オンラインで慎重に決める）と実装は一致しているが、プロダクトとしては次のマイルストーンで ADR による設計文書化が必要である。

---

## 関連ドキュメント（本評価の出力）

- [specific-strengths.md](./specific-strengths.md)
- [specific-weaknesses.md](./specific-weaknesses.md)
- [specific-proposals.md](./specific-proposals.md)
- [improvement-plan.md](../../workspace/0_reference/improvement-plan.md)
