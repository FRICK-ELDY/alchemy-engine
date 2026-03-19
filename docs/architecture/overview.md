# AlchemyEngine — アーキテクチャ概要

## 設計思想

AlchemyEngine は **Elixir を Single Source of Truth（SSoT）** として、Rust の ECS で物理演算・描画・オーディオを処理するハイブリッドゲームエンジンです。

- **Elixir 側**: ゲームロジックの制御フロー・セーブ/ロード・イベント配信（シーン管理は contents 層）
- **Rust 側**: 60Hz 固定の物理演算・衝突判定・描画・オーディオ

---

## 全体構成

```mermaid
graph TB
    subgraph Server["サーバー"]
        subgraph Elixir["Elixir"]
            GS[server<br/>起動制御]
            GE[core<br/>SSoT コア]
            GC[contents<br/>VampireSurvivor / AsteroidArena]
            GN[network<br/>Phoenix Channels / Zenoh]
        end
        subgraph RustServer["Rust（サーバー内）"]
            GNIF[nif<br/>NIF インターフェース / physics / ゲームループ]
            GAUDIO[audio<br/>rodio オーディオ]
        end
        GS --> GE
        GC --> GE
        GE <-->|Rustler NIF| GNIF
        GNIF --> GAUDIO
    end

    subgraph Client["クライアント（app）"]
        APP[app<br/>VRAlchemy exe]
        WIN[window<br/>winit イベントループ]
        RENDER[render<br/>wgpu 描画]
        NET[network<br/>Zenoh フレーム受信・入力送信]
        XR[xr<br/>OpenXR]
        APP --> WIN
        APP --> NET
        APP --> XR
        WIN --> RENDER
        NET --> RENDER
    end

    LAUNCHER[tools/launcher<br/>zenohd / Phoenix / VRAlchemy 起動]

    GN -->|Zenoh<br/>frame publish| NET
    NET -->|Zenoh<br/>input publish| GN
    LAUNCHER -.->|起動| Server
    LAUNCHER -.->|起動| Client
```

---

## ディレクトリ構造（ソース単位）

```
alchemy-engine/
├── mix.exs                          # Umbrella ルートプロジェクト定義
├── mix.lock                         # Elixir 依存ロックファイル
├── config/
│   ├── config.exs                   # :server :current / :map / libcluster / save_hmac_secret 等
│   └── runtime.exs                  # 実行時設定（ポート等）
│
├── apps/                            # Elixir アプリケーション群
│   ├── core/                        # SSoT コアエンジン
│   │   ├── mix.exs
│   │   └── lib/
│   │       ├── core.ex              # 公開 API（エントリポイント）
│   │       └── core/
│   │           ├── nif_bridge.ex        # Rustler NIF ラッパー
│   │           ├── nif_bridge_behaviour.ex  # NifBridge ビヘイビア（テスト用 Mock 対応）
│   │
│   │           ├── component.ex         # Component ビヘイビア（コンテンツ構成単位）
│   │           ├── config.ex            # :server :current でコンテンツモジュール解決
│   │           ├── room_supervisor.ex   # DynamicSupervisor
│   │           ├── room_registry.ex     # Registry ラッパー
│   │           ├── event_bus.ex         # フレームイベント配信 GenServer（subscribe / broadcast）
│   │           ├── input_handler.ex     # キー入力 GenServer
│   │           ├── frame_cache.ex       # フレームスナップショット ETS
│   │           ├── map_loader.ex        # マップ障害物定義
│   │           ├── save_manager.ex      # セーブ/ロード
│   │           ├── stats.ex             # セッション統計 GenServer
│   │           ├── telemetry.ex         # Telemetry Supervisor
│   │           ├── stress_monitor.ex    # パフォーマンス監視 GenServer
│   │           ├── formula.ex           # Formula 式評価 API
│   │           ├── formula_graph.ex     # 式グラフ（DAG）構築
│   │           ├── formula_store.ex     # Store バックエンド（read/write）
│   │           └── formula_store/
│   │               └── local_backend.ex # ローカル Store 実装
│   │
│   ├── server/                      # 起動プロセス
│   │   ├── mix.exs
│   │   └── lib/server/
│   │       └── application.ex       # OTP Application / Supervisor ツリー
│   │
│   ├── contents/                    # ゲームコンテンツ
│   │   ├── mix.exs
│   │   └── lib/
│   │       ├── behaviour/
│   │       │   └── content.ex             # Contents.Behaviour.Content（コンテンツ契約）
│   │       ├── contents/
│   │       │   ├── contents.ex            # Content 名前空間モジュール
│   │       │   ├── entity_params.ex       # 共通 EXP・スコア（Content.EntityParams）
│   │       │   ├── scene_behaviour.ex     # シーンコールバック定義
│   │       │   ├── frame_broadcaster.ex   # Zenoh フレーム配信（Process.put → ZenohBridge）
│   │       │   ├── component_list.ex      # コンポーネント解決（LocalUserComponent / TelemetryComponent 注入）
│   │       │   ├── message_pack_encoder.ex# Content.MessagePackEncoder（RenderFrame の MessagePack エンコード）
│   │       │   ├── local_user_component.ex# ローカル入力共通コンポーネント
│   │       │   ├── telemetry_component.ex # 入力状態参照用（全コンテンツに注入）
│   │       │   ├── menu_component.ex      # メニュー UI 共通コンポーネント
│   │       │   ├── content_loader.ex      # 将来用: descriptor ベース（stub）
│   │       │   ├── content_runner.ex      # 将来用（stub）
│   │       │   ├── component_registry.ex  # 将来用（stub）
│   │       │   ├── vampire_survivor.ex    # Content.VampireSurvivor（Spawner / Level / Boss / Render 使用）
│   │       │   ├── vampire_survivor/
│   │       │   │   ├── local_user_component.ex, entity_params.ex, sprite_params.ex
│   │       │   │   ├── spawn_system.ex, frame_builder.ex, helpers.ex
│   │       │   │   ├── playing.ex         # Playing シーン + LevelComponent + BossComponent + LevelSystem
│   │       │   │   ├── level_up.ex, boss_alert.ex, game_over.ex
│   │       │   ├── asteroid_arena.ex      # Spawner + PhysicsEntity 使用
│   │       │   ├── asteroid_arena/
│   │       │   │   └── playing.ex, game_over.ex
│   │       │   ├── simple_box_3d.ex / simple_box_3d/ playing.ex, game_over.ex
│   │       │   ├── bullet_hell_3d.ex / bullet_hell_3d/ playing.ex, game_over.ex
│   │       │   ├── rolling_ball.ex / rolling_ball/ title.ex, playing.ex, stage_clear.ex, ending.ex, game_over.ex
│   │       │   ├── canvas_test.ex / canvas_test/ playing.ex
│   │       │   └── formula_test.ex / formula_test/ playing.ex
│   │       ├── components/category/       # Spawner, PhysicsEntity, Rendering.Render 等（共有）
│   │       ├── events/
│   │       │   ├── game.ex                # Contents.Events.Game（メインゲームループ GenServer）
│   │       │   └── game/diagnostics.ex
│   │       └── scenes/
│   │           └── stack.ex               # Contents.Scenes.Stack（シーンスタック管理）
│   │
│   └── network/                     # 通信レイヤー
│       ├── mix.exs                  # deps: phoenix ~> 1.8, phoenix_pubsub, plug_cowboy, libcluster
│       └── lib/
│           ├── network.ex           # Network 公開 API（Distributed / Local / Channel / UDP 委譲）
│           └── network/
│               ├── application.ex
│               ├── local.ex             # ローカルマルチルーム管理 GenServer
│               ├── distributed.ex       # 複数ノード間ルーム管理（libcluster クラスタ時）
│               ├── zenoh_bridge.ex      # Zenoh フレーム publish・入力 subscribe（zenoh_enabled 時）
│               ├── room_token.ex        # Phoenix.Token によるルーム参加認証
│               ├── channel.ex           # Phoenix Channels / WebSocket
│               ├── endpoint.ex           # Phoenix Endpoint（ポート 4000）
│               ├── router.ex
│               ├── user_socket.ex
│               └── udp/
│                   ├── server.ex        # UDP サーバー（ポート 4001）
│                   └── protocol.ex
│
├── native/                          # Rust クレート群
│   ├── Cargo.toml                   # Rust ワークスペース定義
│   ├── Cargo.lock
│   │
│   ├── shared/                      # Elixir との契約・型・補間・予測（依存なし）
│   ├── audio/                       # rodio オーディオ（依存なし）
│   ├── xr/                          # OpenXR 入力ブリッジ（VR、依存なし）
│   ├── nif/                         # NIF ブリッジ・physics 内包 → audio
│   ├── render/                      # wgpu 描画・egui HUD → nif
│   ├── window/                      # winit イベントループ・窓層 → render
│   ├── network/                     # Zenoh 通信層 → render, shared
│   ├── app/                         # 統合層（VRAlchemy exe）→ network, render, window, xr, nif, audio
│   └── tools/
│       └── launcher/                # トレイアイコン・zenohd / Phoenix / VRAlchemy 起動（依存なし）
│
├── assets/                          # スプライト・音声アセット
└── saves/                           # セーブデータ
```

---

## Rust クレート依存関係

```mermaid
graph TB
    subgraph Base["基底クレート（依存なし）"]
        SHARED[shared]
        AUDIO[audio]
        XR[xr]
    end

    NIF[nif] --> AUDIO
    RENDER[render] --> NIF
    WINDOW[window] --> RENDER
    NETWORK[network] --> RENDER
    NETWORK --> SHARED

    subgraph App["統合層"]
        APP[app<br/>VRAlchemy exe]
    end

    APP --> NETWORK
    APP --> RENDER
    APP --> WINDOW
    APP --> XR
    APP --> NIF
    APP --> AUDIO

    LAUNCHER[tools/launcher<br/>独立ツール]
```

- **サーバー側**: `nif` が Elixir NIF としてロードされ、`audio` でオーディオ再生
- **クライアント側**: `app` が `window` + `render` で描画、`network` で Zenoh 経由のフレーム受信・入力送信
- **physics**: `nif` クレート内の `nif/src/physics/` に内包（独立クレートではない）

---

## レイヤー間の責務分担

| レイヤー | 責務 | 技術 |
|:---|:---|:---|
| `server` | OTP Application 起動・Supervisor ツリー構築 | Elixir / OTP |
| `core` | ゲームループ制御・イベント受信・セーブ・Core.Component インターフェース定義 | Elixir GenServer / ETS |
| `contents` | Contents.Events.Game・Contents.Scenes.Stack・Contents.Behaviour.Content 実装・Component 群・エンティティパラメータ | Elixir |
| `network` | Phoenix Channels・UDP・Zenoh（フレーム publish・入力 subscribe）・ローカルマルチルーム管理 | Elixir / Phoenix / Zenohex |
| `nif` | Elixir-Rust 間 NIF ブリッジ・ゲームループ・physics 内包 | Rust / Rustler |
| `render` | GPU 描画パイプライン・HUD・ヘッドレスモード（ウィンドウは window が生成） | Rust / wgpu / egui |
| `window` | winit イベントループ・窓生成・キーボード・マウス入力 | Rust / winit |
| `xr` | OpenXR セッション・VR 入力管理 | Rust / OpenXR |
| `app` | 統合層（VRAlchemy exe：Zenoh 経由で RenderFrame 受信・入力送信） | Rust / Zenoh |
| `tools/launcher` | トレイアイコン・zenohd / Phoenix Server / VRAlchemy の起動・終了 | Rust / tao / tray-icon |
| `audio` | オーディオ管理・アセット読み込み（platform/ で OS 切り替え） | Rust / rodio |

---

## 主要な設計パターン

### 1. Rustler NIF による状態共有

```mermaid
graph LR
    EP[Elixir Process]
    GW["GameWorld\n(RwLock&lt;GameWorldInner&gt;)\nResourceArc で Elixir が保持"]
    RL[read lock<br/>query_light 系<br/>毎フレーム利用可]
    WL[write lock<br/>snapshot_heavy 系<br/>明示操作時のみ]

    EP -->|NIF 呼び出し Rustler| GW
    GW --> RL
    GW --> WL
```

### 2. SoA（Structure of Arrays）によるキャッシュ効率化

```rust
EnemyWorld {
    positions_x: Vec<f32>,   // 全敵の X 座標
    positions_y: Vec<f32>,   // 全敵の Y 座標
    velocities:  Vec<[f32;2]>,
    hp:          Vec<f32>,
    alive:       Vec<bool>,
    free_list:   Vec<usize>, // O(1) スポーン/キル
}
```

### 3. イベント駆動ゲームループ

```mermaid
sequenceDiagram
    participant R as Rust 60Hz ループ
    participant GE as Contents.Events.Game
    participant COMP as Component 群
    participant SS as Contents.Scenes.Stack
    participant S as content.scene_update

    loop 毎フレーム（60Hz）
        R->>R: physics_step()
        R->>R: drain_frame_events()
        R-->>GE: {:frame_events, [enemy_killed, player_damaged, ...]}
        GE->>COMP: on_frame_event/2（スコア・HP・ボス HP 更新）
        GE->>SS: flow_runner 経由で scene_update/3 → シーン遷移判断
        GE->>COMP: on_physics_process/1（ボス AI 等）
        GE->>COMP: on_nif_sync/1（Elixir state → Rust 注入）
    end
```

### 4. 描画命令の Zenoh 配信

Elixir 側（contents）の Render コンポーネントが DrawCommand リスト・CameraParams・UiCanvas を組み立て、`Content.MessagePackEncoder` で MessagePack にエンコードし、`FrameBroadcaster.put(room_id, frame_binary)` で Zenoh へ publish する。`Network.ZenohBridge` が受信し、`app`（VRAlchemy exe）が subscribe して描画する。ローカル描画は廃止済み（Zenoh 専用）。

### 5. Contents.Behaviour.Content + Component による拡張設計

```mermaid
graph LR
    CFG["config.exs\n:server :current コンテンツモジュール"]
    CB["Contents.Behaviour.Content\ncomponents / scene_init / scene_update\nentity_registry 等"]
    COMP["Core.Component ビヘイビア\non_ready / on_frame_event\non_nif_sync 等（全オプショナル）"]
    GE["Contents.Events.Game\n（contents 層）"]
    VS["Content.VampireSurvivor\nSpawner + LevelComponent\n+ BossComponent + Render"]
    AA["Content.AsteroidArena\nSpawner + PhysicsEntity"]

    CFG -->|解決| CB
    CB -->|実装| VS
    CB -->|実装| AA
    VS -->|使用| COMP
    AA -->|使用| COMP
    GE -->|参照| CB
    GE -->|ディスパッチ| COMP
```

---

# データフロー・通信

## 起動シーケンス

```mermaid
sequenceDiagram
    participant MX as mix run
    participant APP as Server.Application
    participant RS as RoomSupervisor
    participant GEV as Contents.Events.Game
    participant NIF as NifBridge (nif)
    participant COMP as Component 群（on_ready）

    MX->>APP: start/2
    APP->>APP: Registry / Scenes.Stack / EventBus / RoomSupervisor / StressMonitor / Stats / Telemetry 起動
    APP->>RS: RoomSupervisor 起動
    APP->>APP: StressMonitor / Stats / Telemetry 起動
    APP->>RS: start_room(:main)
    RS->>GEV: Contents.Events.Game 起動（:main ルーム）
    GEV->>NIF: create_world()
    NIF-->>GEV: GameWorld リソース
    GEV->>COMP: on_ready(world_ref) × コンポーネント数
    Note over COMP: set_world_size / set_entity_params NIF を呼び出す
    GEV->>NIF: set_map_obstacles(world_ref, obstacles)
    GEV->>NIF: create_game_loop_control()
    GEV->>NIF: start_rust_game_loop(world_ref, control_ref, self())
    Note over NIF: Rust 60Hz ループ開始
```

---

## メインゲームループ（定常状態）

### Rust 側（60Hz 固定ループ）

```mermaid
flowchart TD
    LOOP[Rust ゲームループスレッド 60Hz]
    PS[physics_step]
    PM[プレイヤー移動]
    OB[障害物押し出し]
    AI[Chase AI\nSSE2 SIMD / rayon]
    SEP[敵分離]
    COL[衝突判定]
    WEP[武器攻撃]
    PAR[パーティクル更新]
    ITEM[アイテム更新]
    BUL[弾丸更新]
    BOSS[ボス物理]
    DFE[drain_frame_events]
    SEND["send {:frame_events, [...]}"]
    GEV[Elixir Contents.Events.Game プロセス]

    LOOP --> PS
    PS --> PM --> OB --> AI --> SEP --> COL --> WEP --> PAR --> ITEM --> BUL --> BOSS
    LOOP --> DFE --> SEND --> GEV
```

### Elixir 側（イベント駆動）

```mermaid
flowchart TD
    GEV[Contents.Events.Game GenServer\nhandle_info :frame_events]
    EK[EnemyKilled]
    PD[PlayerDamaged]
    SE[SpecialEntitySpawned\nSpecialEntityDamaged\nSpecialEntityDefeated]
    IP[ItemPickup]
    PER[60フレームごと]

    COMP[Component 群\non_frame_event/2\non_physics_process/1\non_nif_sync/1]
    EB[EventBus.broadcast]
    ST[Stats.record]
    LOG[Logger.debug\nFPS・敵数]
    TEL[:telemetry.execute]
    FC[FrameCache.put]

    GEV --> EK --> COMP
    GEV --> PD --> COMP
    GEV --> SE --> COMP
    GEV --> IP --> EB --> ST
    GEV --> PER --> LOG
    PER --> TEL
    PER --> FC
```

**フレーム処理の順序（毎フレーム）:**

1. `on_frame_event/2` — 全コンポーネントにフレームイベントを配信（スコア・HP・ボス HP 更新）
2. `content.scene_update/3` — シーン遷移判断（flow_runner 経由）
3. `on_physics_process/1` — ボス AI 等の物理コールバック（NIF 書き込みを含む）
4. `on_nif_sync/1` — Elixir state を Rust 側に注入。Render コンポーネントは `FrameBroadcaster.put` で DrawCommand・Camera・UiCanvas を Zenoh へ配信する

---

## クライアント動作モード

常に Zenoh 経由で `VRAlchemy`（app が生成）がフレームを受信する。`mix run` 単体ではウィンドウは開かず、サーバーのみ起動する。ゲームをプレイするには `zenohd` + `mix run` + `VRAlchemy` の 3 プロセスが必要。

---

## レンダリングフロー

Elixir の RenderComponent が `FrameBroadcaster.put` で Zenoh へ frame を publish。`app`（VRAlchemy exe）の `NetworkRenderBridge`（network クレート）が subscribe して描画する。

---

## ユーザー入力フロー

### キーボード入力（移動）

```mermaid
flowchart LR
    KI[winit KeyboardInput]
    VEC["移動ベクトル計算\n斜め正規化"]
    OMI["GameWorld.on_move_input(dx, dy)\nRenderBridge / write lock"]
    PI["GameWorldInner\nplayer_input = [dx, dy]"]
    PS[次の physics_step で消費\nプレイヤー移動計算]

    KI -->|WASD / 矢印キー| VEC --> OMI --> PI --> PS
```

### UI アクション（武器選択・セーブ等）

```mermaid
flowchart TD
    UI[egui ボタン / キー入力]
    OUA["GameWorld.on_ui_action(action)\nMutex pending_action"]
    Q[on_ui_action キュー]
    SEND["Elixir プロセスに send\nRedrawRequested 末尾で取り出し"]
    GEV["Contents.Events.Game.handle_info\n{:ui_action, action}"]
    W1["Component.on_event/2\n:select_weapon_1/2/3 等"]
    W2["SaveManager.save_session()\n:__save__"]
    W3["SaveManager.load_session()\n→ NifBridge.load_save_snapshot()\n:__load__"]

    UI --> OUA --> Q --> SEND --> GEV
    GEV --> W1
    GEV --> W2
    GEV --> W3
```

---

## NIF 通信詳細

### RwLock 競合戦略

```mermaid
graph TD
    GW["GameWorld\n(RwLock&lt;GameWorldInner&gt;)"]

    subgraph RL["read lock（複数スレッド同時取得可）"]
        R1[レンダースレッド\nnext_frame]
        R2[Elixir query_light 系 NIF]
    end

    subgraph WL["write lock（排他・1スレッドのみ）"]
        W1[ゲームループスレッド\nphysics_step]
        W2[Elixir control 系 NIF\nspawn_enemies 等]
        W3[UI アクション\non_ui_action]
    end

    GW --> RL
    GW --> WL
```

**競合監視（`lock_metrics.rs`）:**
- read lock 待機 > 300μs → `log::warn!`
- write lock 待機 > 500μs → `log::warn!`
- 5 秒ごとに平均待機時間をレポート

### NIF 関数カテゴリ別ロック種別

| カテゴリ | 代表関数 | ロック | 呼び出し頻度 |
|:---|:---|:---|:---|
| control | `create_world`, `spawn_enemies`, `set_entity_params` | write | 低（起動時・イベント時） |
| inject | `set_hud_state`, `set_hud_level_state`, `set_boss_velocity`, `set_weapon_slots` | write | 高（毎フレーム） |
| query_light | `get_player_hp`, `get_enemy_count`, `get_boss_state` | read | 高（毎フレーム可） |
| snapshot_heavy | `get_save_snapshot`, `load_save_snapshot` | write | 低（明示操作時） |
| game_loop | `physics_step`, `drain_frame_events` | write | 高（60Hz） |

---

## イベントバス（Elixir 内）

```mermaid
graph LR
    EB[EventBus GenServer]
    SUB["subscribe(pid)\nProcess.monitor で死活監視"]
    BC["broadcast(event)"]
    ST[Stats GenServer\n統計集計]
    GN["GameNetwork\n外部配信等"]
    DOWN[":DOWN メッセージ\n→ 自動購読解除"]

    EB --> SUB
    EB --> BC
    BC --> ST
    BC -.->| | GN
    SUB -->|死亡検知| DOWN
```

サブスクライバーが死亡した場合、`{:DOWN, ...}` メッセージで自動的に購読解除されます。

---

## セーブ/ロードフロー

### セーブ

```mermaid
sequenceDiagram
    participant SM as SaveManager
    participant NIF as NifBridge (nif)
    participant FS as ファイルシステム

    SM->>NIF: get_save_snapshot(world)
    Note over NIF: read lock → SaveSnapshot 生成
    NIF-->>SM: SaveSnapshot (NifMap)
    SM->>SM: :erlang.term_to_binary(snapshot)
    SM->>FS: File.write("saves/session.dat")
```

### ロード

```mermaid
sequenceDiagram
    participant SM as SaveManager
    participant NIF as NifBridge (nif)
    participant FS as ファイルシステム

    SM->>FS: File.read("saves/session.dat")
    FS-->>SM: binary
    SM->>SM: :erlang.binary_to_term(binary)
    SM->>NIF: load_save_snapshot(world, snapshot)
    Note over NIF: write lock → ワールド状態を復元
```

### ハイスコア

```mermaid
flowchart LR
    SHS["save_high_score(score)"]
    LHS["load_high_scores()\n既存リスト取得"]
    SORT["[score | list]\n|> sort(:desc)\n|> take(10)"]
    FW["File.write\nsaves/high_scores.dat"]

    SHS --> LHS --> SORT --> FW
```

---

## スレッドモデル

```mermaid
graph TB
    subgraph BEAM["Elixir BEAM VM"]
        GEV[Contents.Events.Game\nGenServer]
        SS[Contents.Scenes.Stack\nGenServer]
        EVB[EventBus\nGenServer]
        STS[Stats\nGenServer]
    end

    BEAM <-->|NIF Rustler| GW

    subgraph RUST["Rust スレッド群（nif / audio）"]
        GL[ゲームループスレッド\n60Hz physics\nnif 内]
        AT[オーディオスレッド\nrodio / コマンド\naudio]
        GW["GameWorld\n(RwLock&lt;GameWorldInner&gt;)\nnif/physics"]

        GL <-->|write lock| GW
    end
```

描画は `app`（VRAlchemy exe）プロセス内で行われる（Zenoh 経由で frame を受信）。

---

## 関連ドキュメント

- [**ビジョンと設計思想**](../vision.md) ← エンジン・ワールド・ルール・ゲームの定義
- **Elixir レイヤー**: [server](./elixir/server.md) / [core](./elixir/core.md) / [contents](./elixir/contents.md)（ゲームコンテンツ一覧・設計パターン含む）/ [network](./elixir/network.md)
- **Rust レイヤー**: [nif](./rust/nif.md)（physics 内包）/ [desktop_client](./rust/desktop_client.md)（app / VRAlchemy）/ [desktop 詳細](./rust/desktop/)（[input](./rust/desktop/input.md) = window / [render](./rust/desktop/render.md) = render / [input_openxr](./rust/desktop/input_openxr.md)）/ [nif/physics](./rust/nif/physics.md) / [audio](./rust/nif/audio.md) / [launcher](./rust/launcher.md)
- [改善計画](../plan/reference/improvement-plan.md) ← 既知の弱点と改善方針
