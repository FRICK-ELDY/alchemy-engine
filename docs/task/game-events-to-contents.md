# GameEvents を contents へ移行するタスク

> 作成日: 2026-03-04  
> 設計方針: **オプション B（責務分離）** を採用  
> 出典: [improvement-plan.md](../improvement-plan.md) の「GameEvents / GameEvents.Diagnostics の所在」

---

## 概要

| 項目 | 内容 |
|:---|:---|
| 目的 | `Core.GameEvents` および `Core.GameEvents.Diagnostics` を core から contents へ移行し、core の責務を「ループ制御・イベント配信・コンポーネントライフサイクル」に限定する |
| 背景 | GameEvents は ContentBehaviour・flow_runner・シーン構造・playing_scene state 等のコンテンツ固有知識を多く持つ。実装ルールの「core はゲームコンテンツ固有ロジックを持たない」に沿い、contents 層に配置すべき |
| 設計方針 | **オプション B: 責務分離** — core に薄い EventReceiver を残し、contents に GameEvents を移行する |
| 関連ドキュメント | [vision.md](../vision.md), [implementation.mdc](../../.cursor/rules/implementation.mdc), [specific-weaknesses.md](../evaluation/specific-weaknesses.md)（BatLord 固有ロジック漏出） |

---

## 背景と設計方針

### 現状の問題

- **core** に `GameEvents` と `GameEvents.Diagnostics` が存在する
- GameEvents が持つコンテンツ固有知識の例:
  - `ContentBehaviour`（flow_runner, physics_scenes, playing_scene, game_over_scene, pause_on_push?, context_defaults）
  - `Core.Config.components()`（コンテンツ別のコンポーネントリスト）
  - `build_window_title(content)`, `resolve_atlas_path(content)`（コンテンツ別アセット）
  - `handle_info({:boss_dash_end, world_ref})`（BatLord 固有ロジック。実装ルール違反として評価で指摘済み）
- Diagnostics が `playing_scene` state の構造（score, player_hp, weapon_levels, boss_hp 等）を知っている

### 採用方針: オプション B（責務分離）

**core の責務を「ループ制御・イベント配信・コンポーネントライフサイクル」に限定する**

- イベントの **受信**（Rust NIF → Elixir）は core の `EventReceiver` が担う
- イベントの **ディスパッチ**（flow_runner 呼び出し・シーン update・コンポーネントコールバック）は contents の `GameEvents` が担う

| レイヤー | 役割 | 例 |
|:---|:---|:---|
| **core** | Rust からのメッセージ受信・ゲームループ起動・world_ref 管理・転送先への委譲 | `Core.EventReceiver`: `{:frame_events, events}` 等を受信し、`ContentBehaviour.event_handler(room_id)` に転送 |
| **contents** | イベントの解釈・flow_runner 呼び出し・シーン update・コンポーネントディスパッチ | `Contents.GameEvents`（現行ロジックを移行） |

- core は「誰に転送するか」を ContentBehaviour のコールバックで取得するだけで、コンテンツ固有ロジックを持たない
- contents の GameEvents が Config・ContentBehaviour・SceneStack を直接参照する

---

## 目標アーキテクチャ

### Before

```
core/
  GameEvents         ← ContentBehaviour・flow_runner・Config を参照
  GameEvents.Diagnostics

contents/
  (GameEvents を呼ばず、core から呼ばれる)
```

### After

```
core/
  EventReceiver      ← 新規: Rust からのメッセージ受信・ContentBehaviour.event_handler(room_id) に転送
  (GameEvents 削除)
  (Diagnostics 削除)

contents/
  game_events.ex           ← 新規: 現行 GameEvents ロジックを移行
  game_events/diagnostics.ex  ← 新規: 現行 Diagnostics を移行
  ContentBehaviour.event_handler/1  ← 新規: そのルームの GameEvents pid を返す
```

---

## 実装フェーズ

### フェーズ1: contents に GameEvents を用意

1. `apps/contents/lib/contents/game_events.ex` を作成（`Core.GameEvents` を contents へコピー・移動）
2. `apps/contents/lib/contents/game_events/diagnostics.ex` を作成
3. モジュール名を `Contents.GameEvents` / `Contents.GameEvents.Diagnostics` に変更
4. `ContentBehaviour` に `event_handler/1` を追加（`flow_runner/1` と同様のパターン。`event_handler(room_id) -> pid() | nil`）
5. 各 ContentBehaviour 実装で `event_handler(room_id)` がそのルームの GameEvents pid を返すようにする

### フェーズ2: core に EventReceiver を用意

6. `Core.EventReceiver`（仮称）を新規作成
   - Rust からの `{:frame_events, events}` 等を受信
   - `content = Core.Config.current()`
   - `handler = content.event_handler(room_id)`
   - `send(handler, {:frame_events, events})` で転送
7. ゲームループ起動・world_ref 作成・NifBridge 呼び出しを EventReceiver が担うか、GameEvents が担うか決定
   - 案: EventReceiver が init で world_ref・control_ref を作成し、GameEvents を起動。GameEvents に world_ref 等を渡す
   - または: GameEvents が init で world_ref 等を作成し、Rust ゲームループから EventReceiver 経由で GameEvents に送る二重構造を避ける
8. InputHandler・Network・NIF（Rust）等の送信先を `Core.GameEvents` から `ContentBehaviour.event_handler(:main)` 経由に変更するか、Registry 経由で解決する設計を検討

### フェーズ3: 起動順序と参照の切り替え

9. `RoomSupervisor` が `Core.GameEvents` ではなく `Contents.GameEvents` を起動するように変更
10. または EventReceiver が子プロセスとして GameEvents を起動し、RoomSupervisor は EventReceiver を起動する形に変更
11. `Core.GameEvents` および `Core.GameEvents.Diagnostics` を削除
12. `Server.Application` から `Core.GameEvents` の起動を削除（RoomSupervisor 経由になる想定）

### フェーズ4: BatLord 固有ロジックの解消（別タスクと兼用可）

13. `handle_info({:boss_dash_end, world_ref})` を汎用ディスパッチ機構（例: `on_engine_message/2`）に置き換え

### フェーズ5: ドキュメント・ルールの更新

14. `implementation.mdc` の core 責務から「GameEvents」を削除し、contents 責務に追加
15. `vision.md`, `architecture-overview.md`, `elixir-layer.md`, `data-flow.md`, `pending-issues.md` を更新
16. `improvement-plan.md` の「GameEvents / GameEvents.Diagnostics の所在」を解決済みとして更新

---

## 影響ファイル一覧

### core（削除・変更）

| ファイル | 変更内容 |
|:---|:---|
| `apps/core/lib/core/game_events.ex` | **削除**（contents へ移行） |
| `apps/core/lib/core/game_events/diagnostics.ex` | **削除**（contents へ移行） |
| `apps/core/lib/core/content_behaviour.ex` | `event_handler/1` 追加 |
| `apps/core/lib/core/room_supervisor.ex` | GameEvents 起動先を変更 |
| `apps/core/lib/core.ex` | エンジン内部用モジュール一覧から GameEvents を削除 |

### contents（新規・変更）

| ファイル | 変更内容 |
|:---|:---|
| `apps/contents/lib/contents/game_events.ex` | **新規**（Core.GameEvents から移行） |
| `apps/contents/lib/contents/game_events/diagnostics.ex` | **新規** |
| 各 ContentBehaviour 実装 | `event_handler/1` 実装 |

### 参照箇所（要更新）

| ファイル | 変更内容 |
|:---|:---|
| `apps/core/lib/core/input_handler.ex` | `Core.GameEvents` → 送信先の取得方法を変更 |
| `apps/network/lib/network/channel.ex` | GameEvents 参照の更新 |
| `apps/network/lib/network/local.ex` | GameEvents 参照の更新 |
| `native/nif/src/nif/xr_nif.rs` 等 | Elixir 側で送信先を Registry 等から解決する設計なら、NIF 側は変更不要の可能性 |

### ドキュメント

| ファイル | 変更内容 |
|:---|:---|
| `.cursor/rules/implementation.mdc` | core/contents 責務の記述更新 |
| `docs/vision.md` | GameEvents の所在変更 |
| `docs/architecture-overview.md` | 同上 |
| `docs/elixir-layer.md` | 同上 |
| `docs/data-flow.md` | 同上 |
| `docs/pending-issues.md` | 同上 |
| `docs/improvement-plan.md` | 当該課題を解決済みとして更新 |

---

## 受け入れ条件

- [ ] `Core.GameEvents` および `Core.GameEvents.Diagnostics` が存在しない
- [ ] イベントの受信・ディスパッチが `Contents.GameEvents` 経由で動作する
- [ ] `mix test` が通過する
- [ ] `iex -S mix` でエンジンが起動し、既存コンテンツでプレイ可能である
- [ ] `implementation.mdc` の責務表で core に「GameEvents（コンテンツディスパッチ）」が含まれていない
- [ ] BatLord 固有ロジックが core に残っていない（フェーズ4 完了時）

---

## 未解決事項・確認ポイント

| 項目 | 内容 |
|:---|:---|
| **送信先の解決方法** | InputHandler・Network・NIF が「メインルームの GameEvents」に送る方法。`Process.whereis(Core.GameEvents)` に依存している現状から、`ContentBehaviour.event_handler(:main)` や Registry 経由に切り替える必要あり |
| **RoomSupervisor との関係** | 現状は RoomSupervisor が `{Core.GameEvents, [room_id: room_id]}` を起動。contents の GameEvents を起動するには、contents アプリが先に起動している必要がある（Application の children 順序で満たせる） |
| **mix.exs 依存関係** | contents が core に依存している前提。GameEvents を contents に移すと、core は contents を直接参照しない設計にする必要あり。EventReceiver が `ContentBehaviour.event_handler` を呼ぶ場合、core は ContentBehaviour を参照するが contents モジュールは参照しない（ContentBehaviour は core に定義）。この依存関係は維持可能 |

---

*このタスクは vision.md の「エンジンはコンテンツを知らない」原則および implementation.mdc のレイヤー責務に沿った設計変更である。*
