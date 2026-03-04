# シーン管理を contents へ移行するタスク

> 作成日: 2026-03-04  
> 方針: 「あらゆる概念を contents に寄せる」

---

## 概要

| 項目 | 内容 |
|:---|:---|
| 目的 | シーン管理（SceneManager / SceneBehaviour）を core から contents へ移行し、core を「空間・物理・ライフサイクル」のみに責務を限定する |
| 背景 | シーン（Playing / LevelUp / GameOver 等）はゲームフローであり、コンテンツ切り替えには使われない。エンジンが汎用シーン機構を持つより、contents に委ねる方がビジョンに沿う |
| 関連ドキュメント | [vision.md](../vision.md), [implementation.mdc](../../.cursor/rules/implementation.mdc) |

---

## 背景と設計方針

### 現状

- **core** が `SceneManager` と `SceneBehaviour` を持つ
- シーンモジュール（Playing, LevelUp, GameOver 等）は **contents** が定義
- `ContentBehaviour` が `initial_scenes`, `playing_scene`, `game_over_scene` 等で core にシーン構造を渡している

### 方針

**「あらゆる概念を contents に寄せる」**

- シーンはゲーム固有の UI フローであり、エンジン基盤ではない
- コンテンツ切り替え（VampireSurvivor ↔ AsteroidArena）は SceneManager を使わない
- core は「コンポーネントのライフサイクル」「イベント配信」「NIF ブリッジ」のみを提供する
- シーンスタック機構・シーン遷移ロジックは contents が自前で持つ

### 移行後の責務

| レイヤー | 責務 |
|:---|:---|
| **core** | ループ制御・イベント配信・コンポーネントライフサイクル（SceneManager を削除） |
| **contents** | シーンスタック機構・SceneBehaviour・シーンモジュール・ContentBehaviour のシーン関連コールバック |

---

## 目標アーキテクチャ

### Before

```
core/
  SceneManager    ← シングルトン GenServer、ContentBehaviour.initial_scenes() から初期化
  SceneBehaviour  ← シーンコールバック定義

contents/
  *_survivor/scenes/*.ex  ← SceneBehaviour を実装
  level_component.ex      ← Core.SceneManager.update_by_module / get_scene_state を呼ぶ
```

### After

```
core/
  (SceneManager 削除)
  (SceneBehaviour 削除)
  ContentBehaviour       ← シーン関連コールバックを削除、フロー更新の委譲インターフェースに変更
  GameEvents             ← SceneManager を呼ばず、content のフロー更新を呼ぶ

contents/
  scene_stack.ex         ← 新規: シーンスタック GenServer（room_id 紐づけ可能）
  scene_behaviour.ex     ← 新規: シーンコールバック定義（core から移行）
  */scenes/*.ex          ← Contents.SceneBehaviour を実装
  level_component.ex     ← Contents.SceneStack（または content 固有のフロー管理）を呼ぶ
```

---

## 実装フェーズ

### フェーズ1: contents に SceneStack と SceneBehaviour を用意

1. `apps/contents/lib/contents/scene_behaviour.ex` を作成（`Core.SceneBehaviour` を contents へコピー・移動）
2. `apps/contents/lib/contents/scene_stack.ex` を作成（`Core.SceneManager` のロジックを contents へ移行）
   - `room_id` をオプションで受け取り、マルチルーム対応の準備をする
   - `ContentBehaviour` に `scene_stack_spec/1` を追加し、ルーム起動時に content が自分の SceneStack を起動する設計を検討

### フェーズ2: ContentBehaviour のインターフェース変更

3. `ContentBehaviour` に `flow_runner/1` のようなコールバックを追加
   - `flow_runner(room_id) -> pid()`：そのルームのシーンスタック（またはフロー管理）の pid を返す
   - GameEvents は `content.flow_runner(room_id)` 経由でフロー更新を委譲する
4. 既存の `initial_scenes`, `playing_scene`, `game_over_scene`, `physics_scenes`, `level_up_scene`, `boss_alert_scene`, `pause_on_push?` は `SceneStack` または content 固有モジュールが参照する形に移行

### フェーズ3: GameEvents の SceneManager 参照を置換

5. `GameEvents` 内の `Core.SceneManager.*` 呼び出しを `content.flow_runner(room_id)` 経由に変更
6. `GameEvents.Diagnostics` の `SceneManager` 参照を同様に置換

### フェーズ4: contents 内の SceneManager / SceneBehaviour 参照を置換

7. 各コンテンツのシーンモジュール: `@behaviour Core.SceneBehaviour` → `@behaviour Contents.SceneBehaviour`
8. 各コンテンツのコンポーネント: `Core.SceneManager.*` → `Contents.SceneStack.*` または content 固有の API

### フェーズ5: core からの削除と起動順序の変更

9. `Core.SceneManager` を削除
10. `Core.SceneBehaviour` を削除
11. `Server.Application` から `Core.SceneManager` の起動を削除
12. ルーム起動時（RoomSupervisor / GameEvents）に content の SceneStack を起動するように変更

### フェーズ6: ドキュメント・ルールの更新

13. `implementation.mdc` の「シーン管理」を core の責務から削除し、contents の責務に追加
14. `vision.md`, `architecture-overview.md`, `elixir-layer.md`, `game-content.md` を更新
15. `improvement-plan.md` の SceneManager 関連課題を本タスクで解決済みとして更新

---

## 影響ファイル一覧

### core（削除・変更）

| ファイル | 変更内容 |
|:---|:---|
| `apps/core/lib/core/scene_manager.ex` | **削除** |
| `apps/core/lib/core/scene_behaviour.ex` | **削除** |
| `apps/core/lib/core/content_behaviour.ex` | シーン関連コールバック削除、`flow_runner/1` 追加 |
| `apps/core/lib/core/game_events.ex` | SceneManager 参照を content 経由に変更 |
| `apps/core/lib/core/game_events/diagnostics.ex` | SceneManager 参照を content 経由に変更 |
| `apps/server/lib/server/application.ex` | SceneManager の起動削除 |

### contents（新規・変更）

| ファイル | 変更内容 |
|:---|:---|
| `apps/contents/lib/contents/scene_stack.ex` | **新規**（SceneManager ロジック移行） |
| `apps/contents/lib/contents/scene_behaviour.ex` | **新規**（SceneBehaviour 定義移行） |
| `apps/contents/lib/contents/vampire_survivor/*.ex` | SceneManager → SceneStack、SceneBehaviour 参照変更 |
| `apps/contents/lib/contents/asteroid_arena/*.ex` | 同上 |
| `apps/contents/lib/contents/simple_box_3d/*.ex` | 同上 |
| `apps/contents/lib/contents/bullet_hell_3d/*.ex` | 同上 |
| `apps/contents/lib/contents/rolling_ball/*.ex` | 同上 |
| `apps/contents/lib/contents/canvas_test/*.ex` | 同上 |
| `apps/contents/lib/contents/vr_test/*.ex` | 同上 |

### ドキュメント

| ファイル | 変更内容 |
|:---|:---|
| `.cursor/rules/implementation.mdc` | core/contents 責務の記述更新 |
| `docs/vision.md` | SceneBehaviour の所在変更 |
| `docs/architecture-overview.md` | SceneManager 削除・SceneStack 追加 |
| `docs/elixir-layer.md` | 同上 |
| `docs/game-content.md` | 同上 |
| `docs/data-flow.md` | 同上 |
| `docs/task/improvement-plan.md` | SceneManager 関連課題の解決済みマーク |
| `docs/pending-issues.md` | 課題13 等の参照更新 |
| `docs/evaluation/specific-weaknesses.md` | SceneManager シングルトン課題の解決済みマーク |

---

## 受け入れ条件

- [ ] `Core.SceneManager` および `Core.SceneBehaviour` が存在しない
- [ ] すべての既存コンテンツ（VampireSurvivor, AsteroidArena 等）が `Contents.SceneStack` 経由で動作する
- [ ] `mix test` が通過する
- [ ] `iex -S mix` でエンジンが起動し、既存コンテンツでプレイ可能である
- [ ] `implementation.mdc` の責務表で core に「シーン管理」が含まれていない
- [ ] マルチルーム対応の準備として、SceneStack が room_id と紐づけ可能な設計になっている（optional）

---

## 未解決事項・確認ポイント

| 項目 | 内容 |
|:---|:---|
| SceneStack の起動タイミング | ルーム起動時に RoomSupervisor が content の `scene_stack_spec(room_id)` を起動するか、GameEvents の子プロセスとして起動するか要検討 |
| 既存 ContentBehaviour コールバック | `initial_scenes`, `playing_scene` 等を完全に削除するか、SceneStack 初期化用に content 経由で渡す形に留めるか |
| 後方互換性 | 段階的移行のため、一時的に core と contents の両方に SceneManager/SceneStack が存在する期間を設けるか |

---

*このタスクは vision.md の「エンジンはコンテンツを知らない」原則に沿った設計変更である。*
