# Elixir レイヤー詳細

## 概要

Elixir 側は **Umbrella プロジェクト** として構成され、4 つのアプリケーションに分割されています。ゲームの制御フロー・シーン管理・イベント配信・セーブ/ロードを担当します。

---

## アプリケーション構成

```mermaid
graph LR
    GS[game_server<br/>OTP Application 起動]
    GE[game_engine<br/>SSoT コアエンジン]
    GC[game_content<br/>VampireSurvivor]
    GN[game_network<br/>通信スタブ・将来実装]

    GS -->|依存| GE
    GS -->|依存| GC
    GC -->|依存| GE
```

---

## `game_server` — 起動プロセス

### `application.ex`

OTP Application のエントリポイント。Supervisor ツリーを構築し、全 GenServer を起動します。

```mermaid
graph TD
    APP[GameServer.Application]
    REG[Registry<br/>GameEngine.RoomRegistry]
    SM[GameEngine.SceneManager]
    IH[GameEngine.InputHandler]
    EB[GameEngine.EventBus]
    RS[GameEngine.RoomSupervisor]
    GEV[GameEngine.GameEvents<br/>:main ルーム]
    MON[GameEngine.StressMonitor]
    STATS[GameEngine.Stats]
    TEL[GameEngine.Telemetry]

    APP --> REG
    APP --> SM
    APP --> IH
    APP --> EB
    APP --> RS
    RS -->|start_room :main| GEV
    APP --> MON
    APP --> STATS
    APP --> TEL
```

起動後に `GameEngine.RoomSupervisor.start_room(:main)` を呼び出してメインルームを開始します。

**設定（`config/config.exs`）:**
```elixir
config :game_server, :current_world, GameContent.VampireSurvivorWorld
config :game_server, :current_rule,  GameContent.VampireSurvivorRule
config :game_server, :map, :plain
```

---

## `game_engine` — SSoT コアエンジン

### `game_engine.ex` — 公開 API

外部から呼び出す全操作の窓口。エンティティ ID は `Config.current_world().entity_registry()` から解決します。

**ゲームコンテンツ向け:**

| 関数 | 説明 |
|:---|:---|
| `spawn_enemies/3` | 敵をスポーン（atom → ID 自動解決） |
| `spawn_elite_enemy/4` | エリート敵をスポーン（HP 倍率付き） |
| `get_enemy_count/1` | 生存敵数を取得 |
| `is_player_dead?/1` | 死亡判定 |
| `get_frame_metadata/1` | フレームメタデータを取得 |
| `save_session/1` | セッションをセーブ |
| `load_session/1` | セッションをロード |
| `has_save?/0` | セーブデータ存在確認 |
| `save_high_score/1` | ハイスコアを保存 |
| `load_high_scores/0` | ハイスコア一覧を取得 |

**エンジン内部向け（GameEvents が使用）:**

| 関数 | 説明 |
|:---|:---|
| `create_world/0` | GameWorld リソースを生成 |
| `set_map_obstacles/2` | 障害物リストを設定 |
| `create_game_loop_control/0` | GameLoopControl リソースを生成 |
| `start_rust_game_loop/3` | Rust 60Hz ゲームループを開始 |
| `start_render_thread/2` | レンダースレッドを起動 |
| `pause_physics/1` | 物理演算を一時停止 |
| `resume_physics/1` | 物理演算を再開 |
| `physics_step/2` | 1 フレーム物理ステップ |
| `set_player_input/3` | 移動ベクトルを設定 |
| `drain_frame_events/1` | フレームイベントを取り出す |

---

### `nif_bridge.ex` — Rustler NIF ラッパー

Rust NIF 関数の Elixir スタブ定義。`use Rustler` で `game_nif` クレートをロードします。

```elixir
use Rustler, otp_app: :game_engine, crate: :game_nif, path: "../../native/game_nif"
```

NIF 関数は 3 カテゴリに分類されます：

| カテゴリ | 用途 | ロック種別 |
|:---|:---|:---|
| `control系` | ワールド生成・入力・ループ制御 | write lock |
| `query_light系` | HP・座標・HUD などの軽量読み取り | read lock（毎フレーム利用可） |
| `snapshot_heavy系` | セーブ/ロードスナップショット | write lock（明示操作時のみ） |

---

### `world_behaviour.ex` — World 定義インターフェース

World（舞台）が提供すべきコールバック定義。同じ World に複数の Rule を適用できる。

```elixir
@callback assets_path()                              :: String.t()
@callback entity_registry()                          :: map()
@callback setup_world_params(world_ref :: reference()) :: :ok  # optional
```

`setup_world_params/1` はワールド生成後に一度だけ呼ばれ、`set_entity_params` / `set_world_size` NIF で Rust 側にパラメータを注入する。

---

### `rule_behaviour.ex` — Rule 定義インターフェース

Rule（遊び方）が提供すべきコールバック定義。

```elixir
@callback render_type()                              :: atom()
@callback initial_scenes()                           :: [scene_spec()]
@callback physics_scenes()                           :: [module()]
@callback title()                                    :: String.t()
@callback version()                                  :: String.t()
@callback context_defaults()                         :: map()
@callback playing_scene()                            :: module()
@callback generate_weapon_choices(weapon_levels)     :: [atom()]
@callback apply_level_up(scene_state, choices)       :: map()
@callback apply_weapon_selected(scene_state, weapon) :: map()
@callback apply_level_up_skipped(scene_state)        :: map()
@callback game_over_scene()                          :: module()
@callback level_up_scene()                           :: module()
@callback boss_alert_scene()                         :: module()
@callback initial_weapons()                          :: [atom()]
@callback enemy_exp_reward(enemy_kind)               :: non_neg_integer()
@callback boss_exp_reward(boss_kind)                 :: non_neg_integer()
@callback score_from_exp(exp)                        :: non_neg_integer()
@callback wave_label(elapsed_sec)                    :: String.t()
# optional
@callback on_entity_removed(world_ref, kind_id, x, y) :: :ok
@callback on_boss_defeated(world_ref, boss_kind, x, y) :: :ok
@callback update_boss_ai(context, boss_state)          :: :ok
```

---

### `config.ex` — 設定解決ヘルパー

`current_world` / `current_rule` の Application 設定を解決する。

```elixir
GameEngine.Config.current_world()  # WorldBehaviour 実装モジュールを返す
GameEngine.Config.current_rule()   # RuleBehaviour 実装モジュールを返す
```

---

### `scene_behaviour.ex` — シーンコールバック定義

各シーンが実装すべきコールバック。

```elixir
@callback init(init_arg)        :: {:ok, state}
@callback update(context, state) :: {:continue, new_state}
                                  | {:transition, transition, new_state}
@callback render_type()         :: atom()
```

**トランジション種別:**

| 種別 | 動作 |
|:---|:---|
| `:pop` | 現在のシーンをスタックから取り出す |
| `{:push, module, init_arg}` | 新しいシーンをスタックに積む |
| `{:replace, module, init_arg}` | 現在のシーンを置き換える |

---

### `scene_manager.ex` — シーンスタック管理 GenServer

シーンスタックを管理する GenServer。起動時に `game_module.initial_scenes()` からスタックを初期化します。

| 関数 | 説明 |
|:---|:---|
| `push_scene/2` | シーンをスタックに積む |
| `pop_scene/0` | 最上位シーンを取り出す |
| `replace_scene/2` | 最上位シーンを置き換える |
| `update_current/1` | 現在シーンの状態を更新 |

---

### `game_events.ex` — メインゲームループ GenServer

Rust の 60Hz ゲームループから `{:frame_events, events}` を受信し、シーン遷移・UI アクションを処理するコアコンポーネント。

**Elixir as SSoT 移行完了状況:**
- フェーズ1: `score`, `kill_count`, `elapsed_ms` を Elixir 側で管理
- フェーズ2: `player_hp`, `player_max_hp` を Elixir 側で管理
- フェーズ3: `level`, `exp`, `weapon_levels` 等を Playing シーン state で管理
- フェーズ4: `boss_hp`, `boss_kind_id` を Playing シーン state で管理
- フェーズ5: `render_started` フラグ管理・UI アクションを描画スレッドから直接受信

**フレーム処理フロー:**

```mermaid
flowchart TD
    R["Rust\n{:frame_events, events}"]
    ER[EntityRemoved]
    PD[PlayerDamaged]
    LU[LevelUp]
    BD[BossDefeated]
    IP[ItemPickup]
    PER[60フレームごと]

    RULE[RuleBehaviour\non_entity_removed\non_boss_defeated\nupdate_boss_ai]
    SR[Stats.record]
    HC{HP チェック}
    GO[GameOver 遷移]
    LS[LevelUp シーン遷移]
    LOG[ログ出力<br/>Telemetry 計測<br/>FrameCache 更新]

    R --> ER --> RULE
    R --> PD --> HC
    HC -->|HP <= 0| GO
    R --> LU --> LS
    R --> BD --> RULE
    R --> IP --> SR
    R --> PER --> LOG
```

**シーン遷移パターン:**

```mermaid
stateDiagram-v2
    Playing --> LevelUp   : LevelUp イベント
    LevelUp --> Playing   : 選択 / 3秒タイムアウト

    Playing --> BossAlert : BossSpawn イベント
    BossAlert --> Playing : 3秒後にボスをスポーン

    Playing --> GameOver  : 死亡（HP <= 0）
    GameOver --> Playing  : リトライ
```

---

### `room_supervisor.ex` — DynamicSupervisor

ルーム（ゲームセッション）のライフサイクルを管理します。

| 関数 | 説明 |
|:---|:---|
| `start_room/1` | 新しいルームを起動 |
| `stop_room/1` | ルームを停止 |
| `list_rooms/0` | 実行中ルーム一覧 |

起動時に `:main` ルームを自動開始します。

---

### `room_registry.ex` — Registry ラッパー

`room_id → GameEvents pid` のマッピングを管理します。

---

### `event_bus.ex` — フレームイベント配信 GenServer

Rust から受信したフレームイベントを複数のサブスクライバーに配信します。

| 関数 | 説明 |
|:---|:---|
| `subscribe/1` | イベント購読を登録 |
| `broadcast/1` | イベントを全サブスクライバーに配信 |

`Process.monitor` でサブスクライバーの死活監視を行い、死亡時に自動的に購読解除します。

---

### `input_handler.ex` — キー入力 GenServer

キー入力を受け付け、ETS テーブル `:input_state` に移動ベクトルを書き込みます。

- **対応キー**: WASD + 矢印キー
- **斜め移動**: 正規化処理あり（速度が一定になる）

---

### `frame_cache.ex` — フレームスナップショット ETS

最新フレームのスナップショットを ETS に保持します。`StressMonitor` と `GameEvents` が利用します。

| 関数 | 説明 |
|:---|:---|
| `put/6` | フレームデータを書き込み |
| `get/0` | 最新フレームデータを取得 |

---

### `map_loader.ex` — マップ障害物定義

マップ種別ごとの障害物リストを返します。

| マップ | 障害物数 | 説明 |
|:---|:---|:---|
| `:plain` | 0 | 障害物なし |
| `:forest` | 8 | 木・岩など |
| `:minimal` | 2 | テスト用最小構成 |

---

### `save_manager.ex` — セーブ/ロード

| ファイル | 形式 | 内容 |
|:---|:---|:---|
| `saves/session.dat` | Erlang term binary | セッション全データ |
| `saves/high_scores.dat` | Erlang term binary | ハイスコア上位 10 件リスト |

---

### `stats.ex` — セッション統計 GenServer

`EventBus` を購読して統計を集計します。

| イベント | 集計内容 |
|:---|:---|
| `enemy_killed` | 撃破数 |
| `level_up_event` | レベルアップ回数 |
| `item_pickup` | アイテム取得数 |

---

### `telemetry.ex` — Telemetry Supervisor

ゲームパフォーマンスメトリクスを計測します。

| メトリクス | 説明 |
|:---|:---|
| `game.tick.physics_ms` | 物理演算処理時間 |
| `game.tick.enemy_count` | 現在の敵数 |
| `game.level_up.count` | レベルアップ累計 |
| `game.boss_spawn.count` | ボス出現累計 |

---

### `stress_monitor.ex` — パフォーマンス監視 GenServer

1 秒ごとに `FrameCache` をサンプリングし、フレームバジェット超過時に `Logger.warning` を出力します。

---

## 依存関係

```mermaid
graph LR
    GS[game_server]
    GE["game_engine\n(rustler ~> 0.34\ntelemetry ~> 1.3\ntelemetry_metrics ~> 1.0)"]
    GC[game_content]

    GS --> GE
    GS --> GC
    GC --> GE
```

---

## 関連ドキュメント

- [アーキテクチャ概要](./architecture-overview.md)
- [Rust レイヤー詳細](./rust-layer.md)
- [データフロー・通信](./data-flow.md)
- [ゲームコンテンツ詳細](./game-content.md)
