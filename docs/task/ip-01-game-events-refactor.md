# IP-01: GameEvents リファクタリング実装計画書

> 対応する改善提案: `docs/task/improvement-plan.md` — IP-01  
> 関連する残課題: `docs/pending-issues.md` — 課題12（解消済み）、課題13、課題14  
> 作成日: 2026-03-01

---

## 目的

`GameEvents` がコンテンツの内部構造を直接知っている問題を根本から解消する。

Unity/Godot の「エンジンはコンポーネントを呼ぶだけ、中身は知らない」という思想に基づき、
以下の2つの責務をエンジンからコンポーネントへ移動する。

1. **フレームイベント処理**（`apply_event` → `on_frame_event` コールバック）
2. **NIF 注入**（`sync_nif_state` → `on_nif_sync` コールバック）

---

## 現状の問題

### 問題1: エンジンがシーン state のキー名を直接読んでいる

```elixir
# GameEvents.sync_nif_state/2（現状）
playing_state = get_playing_scene_state(content)
Map.get(playing_state, :level)        # ← VampireSurvivor 固有のキー
Map.get(playing_state, :boss_hp)      # ← VampireSurvivor 固有のキー
Map.get(playing_state, :weapon_levels) # ← VampireSurvivor 固有のキー
```

新しいゲームを追加するとき、同じキー名を使わないと `GameEvents` が壊れる。

### 問題2: エンジンがシーンのメソッドを直接呼んでいる

```elixir
# GameEvents.apply_event/2（現状）
content.playing_scene().accumulate_exp(state, exp)
content.playing_scene().apply_boss_spawn(state, boss_kind)
content.playing_scene().apply_boss_damaged(state, damage)
```

ボスの概念がない `AsteroidArena` にも、エンジンに合わせるためのダミー実装が強制されている。

```elixir
# AsteroidArena.Scenes.Playing（現状）— ダミー実装が必要
def apply_boss_spawn(state, _boss_kind), do: state   # ← 不要なのに存在する
def apply_boss_damaged(state, _damage), do: state    # ← 不要なのに存在する
def apply_boss_defeated(state), do: state            # ← 不要なのに存在する
```

### 問題3: `GameEvents.state` がゲーム固有の値を持っている

`score`, `kill_count`, `player_hp`, `elapsed_ms` はゲームコンテンツの概念だが、
エンジンの state に混在している。

---

## 設計方針

### 採用する原則

| 原則 | 内容 |
|:---|:---|
| **context は最小限** | `world_ref`, `now`, `elapsed`, `frame_count`, シーン遷移 API のみ |
| **コンポーネントが自律** | シーン state の読み書きはコンポーネントが `SceneManager` 経由で行う |
| **エンジンはディスパッチのみ** | `GameEvents` はコールバックを呼ぶだけ、中身を知らない |

### 新しいコールバック

```elixir
defmodule GameEngine.Component do
  # 既存
  @callback on_ready(world_ref()) :: :ok
  @callback on_physics_process(context()) :: :ok
  @callback on_event(event(), context()) :: :ok

  # 追加
  @callback on_frame_event(event(), context()) :: :ok  # Rust フレームイベントの処理
  @callback on_nif_sync(context()) :: :ok              # 毎フレームの NIF 注入

  @optional_callbacks [
    on_ready: 1,
    on_physics_process: 1,
    on_event: 2,
    on_frame_event: 2,   # 追加
    on_nif_sync: 1       # 追加
  ]
end
```

### `on_frame_event` と `on_event` の使い分け

| コールバック | 発火元 | 用途 |
|:---|:---|:---|
| `on_frame_event/2` | Rust フレームイベント（`{:enemy_killed, ...}` 等） | ゲーム状態の更新（EXP 加算、HP 減算等） |
| `on_event/2` | UI アクション（`{:ui_action, ...}` 等）、エンジン内部イベント | UI 操作への応答 |

現状の `on_event/2` は両方を受けているが、責務が異なるため分離する。
将来的には統合も検討できるが、まず分離して明確にする。

### `context` の変更

```elixir
# 削除するフィールド（ゲーム固有）
- score
- kill_count
- elapsed_ms
- player_hp
- player_max_hp
- last_spawn_ms  ← context_updates で渡すのではなく、コンポーネントが自己管理

# 残すフィールド（エンジン固有）
+ world_ref
+ now
+ elapsed        ← System.monotonic_time ベースの経過 ms（エンジンが持つ）
+ frame_count
+ tick_ms
+ start_ms
+ push_scene     ← シーン遷移 API
+ pop_scene
+ replace_scene
```

---

## 実装ステップ

### Step 1: `on_nif_sync` の追加と `sync_nif_state` の削除

**変更ファイル**

- `apps/game_engine/lib/game_engine/component.ex`
- `apps/game_engine/lib/game_engine/game_events.ex`
- `apps/game_content/lib/game_content/vampire_survivor/level_component.ex`
- `apps/game_content/lib/game_content/vampire_survivor/boss_component.ex`
- `apps/game_content/lib/game_content/vampire_survivor/spawn_component.ex`（weapon_slots）

**やること**

1. `Component` ビヘイビアに `on_nif_sync/1` を追加
2. `LevelComponent` に `on_nif_sync/1` を実装
   - `:level`, `:exp`, `:exp_to_next`, `:level_up_pending`, `:weapon_choices` を読んで `set_hud_level_state` NIF を呼ぶ
   - `:weapon_levels` を読んで `set_weapon_slots` NIF を呼ぶ
3. `BossComponent` に `on_nif_sync/1` を実装
   - `:boss_hp` を読んで `set_boss_hp` NIF を呼ぶ
4. `GameEvents.sync_nif_state/2` を削除し、代わりにコンポーネントへのディスパッチに置き換える
5. `GameEvents.state` から `last_hud_*` / `last_boss_hp` / `last_weapon_levels` フィールドを削除
   - ダーティフラグはコンポーネントが自分で管理する（モジュール属性 or プロセス辞書）

**ダーティフラグの管理方針**

コンポーネントはモジュールレベルの状態を持てないため、プロセス辞書を使う。

```elixir
# LevelComponent.on_nif_sync/1
def on_nif_sync(context) do
  content = GameEngine.Config.current()
  playing_state = GameEngine.SceneManager.get_scene_state(content.playing_scene())
  
  new_level_state = extract_level_state(playing_state)
  prev = Process.get({__MODULE__, :last_level_state})
  
  if new_level_state != prev do
    inject_level_state_to_nif(context.world_ref, new_level_state)
    Process.put({__MODULE__, :last_level_state}, new_level_state)
  end
  
  :ok
end
```

**受け入れ基準**

- `GameEvents.sync_nif_state/2` が存在しない
- `GameEvents.state` に `last_hud_*` / `last_boss_hp` / `last_weapon_levels` が存在しない
- ゲームが正常に動作する（HUD 表示・ボス HP バー・武器スロット）

---

### Step 2: `on_frame_event` の追加と `apply_event` の削除

**変更ファイル**

- `apps/game_engine/lib/game_engine/component.ex`
- `apps/game_engine/lib/game_engine/game_events.ex`
- `apps/game_content/lib/game_content/vampire_survivor/level_component.ex`
- `apps/game_content/lib/game_content/vampire_survivor/boss_component.ex`
- `apps/game_content/lib/game_content/asteroid_arena/scenes/playing.ex`（ダミー実装の削除）

**やること**

1. `Component` ビヘイビアに `on_frame_event/2` を追加
2. `LevelComponent` に `on_frame_event/2` を実装
   - `{:enemy_killed, ...}` → EXP 加算・スコア更新・アイテムドロップ（現 `apply_event` の中身）
   - `{:player_damaged, ...}` → HP 減算
3. `BossComponent` に `on_frame_event/2` を実装
   - `{:boss_defeated, ...}` → スコア更新・アイテムドロップ
   - `{:boss_spawn, ...}` → ボス状態の初期化
   - `{:boss_damaged, ...}` → ボス HP 減算
4. `GameEvents.apply_event/2` を削除し、`dispatch_frame_events_to_components/2` に置き換える
5. `AsteroidArena.Scenes.Playing` からダミー実装（`apply_boss_spawn` 等）を削除
6. `ContentBehaviour` から `playing_scene().accumulate_exp` 等の呼び出しを削除

**score / kill_count / player_hp の移管**

`GameEvents.state` から削除し、`Playing` シーンの state に移動する。

```elixir
# VampireSurvivor.Scenes.Playing.init/1 に追加
%{
  ...,
  score: 0,
  kill_count: 0,
  player_hp: 100.0,
  player_max_hp: 100.0,
  elapsed_ms: 0
}
```

`context` からも削除する。コンポーネントが `SceneManager.get_scene_state/1` で取得する。

**受け入れ基準**

- `GameEvents.apply_event/2` が存在しない
- `AsteroidArena.Scenes.Playing` にダミー実装が存在しない
- `GameEvents.state` に `score`, `kill_count`, `player_hp`, `elapsed_ms` が存在しない
- `context` に `score`, `kill_count`, `player_hp` が存在しない

---

### Step 3: `GameEvents` のスリム化と `context` の整理

**変更ファイル**

- `apps/game_engine/lib/game_engine/game_events.ex`
- `apps/game_engine/lib/game_engine/component.ex`（`context` 型定義の更新）

**やること**

1. `build_context/3` からゲーム固有フィールドを削除
2. `GameEvents.state` の整理
   - 残すもの: `room_id`, `world_ref`, `control_ref`, `last_tick`, `frame_count`, `start_ms`, `render_started`
   - 削除するもの: `score`, `kill_count`, `elapsed_ms`, `player_hp`, `player_max_hp`, `last_spawn_ms`, `last_weapon_levels`, `last_hud_*`, `last_boss_hp`
3. `reset_elixir_state/1` を削除（コンポーネントが `on_load` で自己リセットする — 課題14 で対応）
   - 暫定: `SceneManager.replace_scene` が `Playing.init/1` を呼ぶため、シーン state は自動リセットされる
4. `handle_frame_events_main/2` の簡略化

**理想の `handle_frame_events_main` の姿**

```elixir
defp handle_frame_events_main(events, state) do
  now = now_ms()
  elapsed = now - state.start_ms
  content = current_content()
  physics_scenes = content.physics_scenes()

  case GameEngine.SceneManager.current() do
    :empty ->
      {:noreply, %{state | last_tick: now}}

    {:ok, %{module: mod, state: scene_state}} ->
      context = build_context(state, now, elapsed)

      # 1. フレームイベントをコンポーネントに委譲
      Enum.each(events, &dispatch_frame_event_to_components(&1, context))

      # 2. NIF 注入をコンポーネントに委譲
      dispatch_nif_sync_to_components(context)

      # 3. 入力・ブロードキャスト
      maybe_set_input_and_broadcast(state, mod, physics_scenes, events)

      # 4. シーン update（遷移判断のみ）
      result = mod.update(context, scene_state)
      {new_scene_state, opts} = extract_state_and_opts(result)
      GameEngine.SceneManager.update_current(fn _ -> new_scene_state end)

      # 5. シーン遷移処理
      state = process_transition(result, state, now, content)

      # 6. ログ・キャッシュ（60フレームごと）
      state = maybe_log_and_cache(state, mod, elapsed, content)

      {:noreply, %{state | last_tick: now, frame_count: state.frame_count + 1}}
  end
end
```

**受け入れ基準**

- `GameEvents` が 300 行以下になる
- `build_context/3` にゲーム固有フィールドが存在しない
- `GameEvents.state` のフィールドが 7 個以下になる

---

### Step 4: `SceneBehaviour` の整理

**変更ファイル**

- `apps/game_content/lib/game_content/vampire_survivor/scenes/playing.ex`
- `apps/game_content/lib/game_content/asteroid_arena/scenes/playing.ex`
- `apps/game_engine/lib/game_engine/scene_behaviour.ex`

**やること**

1. `Playing.update/2` が `context` からゲーム固有値を取得しないように修正
   - `player_hp` は自シーンの state から取得する
   - `elapsed` は `context.elapsed` を引き続き使用（エンジン固有値として残す）
2. `SceneBehaviour` の `update/2` の `context` 型定義を更新

**受け入れ基準**

- `Playing.update/2` が `context.score`, `context.player_hp` 等を参照していない
- `SceneBehaviour` の `@moduledoc` が新しい `context` 構造を反映している

---

## 移行中の互換性維持

Step 1〜4 は独立して動作確認できるように設計する。

| Step | 動作確認方法 |
|:---|:---|
| Step 1 完了後 | HUD 表示・ボス HP バー・武器スロットが正常に動作する |
| Step 2 完了後 | EXP 加算・スコア更新・アイテムドロップが正常に動作する |
| Step 3 完了後 | 全体的なゲームプレイが正常に動作する |
| Step 4 完了後 | シーン遷移（レベルアップ・ボスアラート・ゲームオーバー）が正常に動作する |

---

## 未解決の課題（後続タスクへ）

| 課題 | ドキュメント | 対応タイミング |
|:---|:---|:---|
| コンポーネントがシーンモジュールを直接参照 | `pending-issues.md` 課題13 | IP-01 完了後 |
| セーブ対象データの収集責務 | `pending-issues.md` 課題14 | IP-01 完了後 |

---

## 完了定義

以下をすべて満たしたとき IP-01 完了とする。

- [ ] `GameEvents` が 300 行以下
- [ ] `GameEvents.state` のフィールドが 7 個以下
- [ ] `GameEvents` に `Map.get(playing_state, :*)` が存在しない
- [ ] `AsteroidArena.Scenes.Playing` にダミー実装が存在しない
- [ ] `ContentBehaviour` に `accumulate_exp` / `apply_boss_*` への呼び出しが存在しない
- [ ] 新しいコンポーネントに最低 3 件の単体テストが存在する
- [ ] `mix test` がすべてパスする
