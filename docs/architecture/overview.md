# AlchemyEngine — アーキテクチャ概要

## 設計思想

AlchemyEngine は **Elixir を Single Source of Truth（SSoT）** として、Rust の ECS で物理演算・描画・オーディオを処理するハイブリッドゲームエンジンです。

- **Elixir 側**: ゲームロジックの制御フロー・セーブ/ロード・イベント配信（シーン管理は contents 層）
- **Rust 側**: 60Hz 固定の物理演算・衝突判定・描画・オーディオ

---

## 全体構成

```mermaid
graph TB
    subgraph Elixir["Elixir Umbrella"]
        GS[server<br/>起動制御]
        GE[core<br/>SSoT コア]
        GC[contents<br/>VampireSurvivor / AsteroidArena]
        GN[network<br/>Phoenix Channels / UDP]
        GS -->|依存| GE
        GC -->|依存| GE
    end

    GE <-->|Rustler NIF| GNIF

    subgraph Rust["Rust Workspace"]
        GNIF[nif<br/>NIF インターフェース / ゲームループ / レンダーブリッジ]
        GSIM[physics<br/>物理 / ECS]
        GRENDER[render<br/>wgpu 描画 / winit ウィンドウ]
        GAUDIO[audio<br/>rodio オーディオ]
        GNIF -->|依存| GSIM
        GNIF -->|依存| GRENDER
        GNIF -->|依存| GAUDIO
        GRENDER -->|依存| GSIM
    end
```

---

## ディレクトリ構造（ソース単位）

```
alchemy-engine/
├── mix.exs                          # Umbrella ルートプロジェクト定義
├── mix.lock                         # Elixir 依存ロックファイル
├── config/
│   ├── config.exs                   # :current / :map / libcluster / save_hmac_secret 等
│   └── runtime.exs                  # 実行時設定（ポート等）
│
├── apps/                            # Elixir アプリケーション群
│   ├── core/                        # SSoT コアエンジン
│   │   ├── mix.exs
│   │   └── lib/core/
│   │       ├── core.ex              # 公開 API（エントリポイント）
│   │       ├── nif_bridge.ex        # Rustler NIF ラッパー
│   │       ├── nif_bridge_behaviour.ex  # NifBridge ビヘイビア（テスト用 Mock 対応）
│   │       ├── content_behaviour.ex # ContentBehaviour（コンテンツ定義インターフェース）
│   │       ├── component.ex         # Component ビヘイビア（コンテンツ構成単位）
│   │       ├── config.ex            # :current コンテンツモジュール解決
│   │       ├── room_supervisor.ex   # DynamicSupervisor
│   │       ├── room_registry.ex     # Registry ラッパー
│   │       ├── event_bus.ex         # フレームイベント配信 GenServer（subscribe / broadcast）
│   │       ├── input_handler.ex     # キー入力 GenServer
│   │       ├── frame_cache.ex       # フレームスナップショット ETS
│   │       ├── map_loader.ex        # マップ障害物定義
│   │       ├── save_manager.ex      # セーブ/ロード
│   │       ├── stats.ex             # セッション統計 GenServer
│   │       ├── telemetry.ex         # Telemetry Supervisor
│   │       └── stress_monitor.ex    # パフォーマンス監視 GenServer
│   │
│   ├── server/                      # 起動プロセス
│   │   ├── mix.exs
│   │   └── lib/server/
│   │       ├── server.ex
│   │       └── application.ex       # OTP Application / Supervisor ツリー
│   │
│   ├── contents/                    # ゲームコンテンツ
│   │   ├── mix.exs
│   │   └── lib/contents/
│   │       ├── contents.ex                # Content モジュール（コンテンツ一覧）
│   │       ├── game_events.ex             # メインゲームループ GenServer（contents 層）
│   │       ├── game_events/
│   │       │   └── diagnostics.ex         # ログ・FrameCache 更新ヘルパー
│   │       ├── scene_behaviour.ex         # シーンコールバック定義（contents 層）
│   │       ├── scene_stack.ex             # シーンスタック管理 GenServer（contents 層）
│   │       ├── entity_params.ex           # EXP・スコア・ボスパラメータ（Elixir SSoT）
│   │       ├── content_loader.ex          # 将来用: descriptor ベースコンテンツ（stub）
│   │       ├── content_runner.ex          # 将来用: descriptor ベースコンテンツ（stub）
│   │       ├── component_registry.ex      # 将来用: descriptor ベースコンテンツ（stub）
│   │       ├── vampire_survivor.ex        # Content.VampireSurvivor
│   │       ├── vampire_survivor/
│   │       │   ├── spawn_component.ex
│   │       │   ├── level_component.ex
│   │       │   ├── boss_component.ex
│   │       │   ├── render_component.ex
│   │       │   ├── spawn_system.ex
│   │       │   ├── boss_system.ex
│   │       │   ├── level_system.ex
│   │       │   └── scenes/ playing.ex, level_up.ex, boss_alert.ex, game_over.ex
│   │       ├── asteroid_arena.ex          # Content.AsteroidArena
│   │       ├── asteroid_arena/
│   │       │   ├── spawn_component.ex
│   │       │   ├── split_component.ex
│   │       │   ├── spawn_system.ex
│   │       │   └── scenes/ playing.ex, game_over.ex
│   │       ├── simple_box_3d.ex           # Content.SimpleBox3D（Phase R-6 動作検証）
│   │       ├── simple_box_3d/
│   │       │   ├── spawn_component.ex, input_component.ex, render_component.ex
│   │       │   └── scenes/ playing.ex, game_over.ex
│   │       ├── bullet_hell_3d.ex          # Content.BulletHell3D（3D 弾幕避け）
│   │       ├── bullet_hell_3d/
│   │       │   ├── spawn_component.ex, input_component.ex, render_component.ex
│   │       │   ├── bullet_component.ex, damage_component.ex
│   │       │   └── scenes/ playing.ex, game_over.ex
│   │       ├── rolling_ball.ex            # Content.RollingBall（玉転がし）
│   │       ├── rolling_ball/
│   │       │   ├── spawn_component.ex, physics_component.ex, render_component.ex
│   │       │   ├── stage_data.ex
│   │       │   └── scenes/ title.ex, playing.ex, stage_clear.ex, ending.ex, game_over.ex
│   │       ├── vr_test.ex                 # Content.VRTest（VR 動作検証）
│   │       ├── vr_test/
│   │       │   ├── spawn_component.ex, input_component.ex, render_component.ex
│   │       │   └── scenes/ playing.ex, game_over.ex
│   │       ├── canvas_test.ex             # Content.CanvasTest（描画テスト）
│   │       └── canvas_test/
│   │           ├── input_component.ex, render_component.ex
│   │           └── scenes/ playing.ex
│   │
│   └── network/                     # 通信レイヤー
│       ├── mix.exs                  # deps: phoenix ~> 1.8, phoenix_pubsub, plug_cowboy, libcluster
│       └── lib/network/
│           ├── network.ex           # Distributed / Local / Channel / UDP 委譲
│           ├── application.ex
│           ├── local.ex             # ローカルマルチルーム管理 GenServer
│           ├── distributed.ex       # 複数ノード間ルーム管理（libcluster クラスタ時）
│           ├── room_token.ex        # Phoenix.Token によるルーム参加認証
│           ├── channel.ex           # Phoenix Channels / WebSocket
│           ├── endpoint.ex          # Phoenix Endpoint（ポート 4000）
│           ├── router.ex
│           ├── user_socket.ex
│           └── udp/
│               ├── server.ex        # UDP サーバー（ポート 4001）
│               └── protocol.ex
│
├── native/                          # Rust クレート群
│   ├── Cargo.toml                   # Rust ワークスペース定義
│   ├── Cargo.lock
│   │
│   ├── physics/                  # 物理演算・ECS（依存: rustc-hash / rayon / log）
│   ├── nif/                         # NIF ブリッジ・ゲームループ・RenderFrameBuffer
│   ├── audio/                       # rodio オーディオ管理
│   ├── render/                      # wgpu 描画パイプライン
│   ├── input/                       # デスクトップ入力・winit イベントループ（render に依存）
│   └── input_openxr/                # OpenXR 入力ブリッジ（VR）
│
├── assets/                          # スプライト・音声アセット
└── saves/                           # セーブデータ
```

---

## レイヤー間の責務分担

| レイヤー | 責務 | 技術 |
|:---|:---|:---|
| `server` | OTP Application 起動・Supervisor ツリー構築 | Elixir / OTP |
| `core` | ゲームループ制御・イベント受信・セーブ・ContentBehaviour / Component インターフェース定義 | Elixir GenServer / ETS |
| `contents` | GameEvents・シーンスタック・SceneBehaviour・ContentBehaviour 実装・Component 群・エンティティパラメータ | Elixir |
| `network` | Phoenix Channels（WebSocket）・UDP トランスポート・ローカルマルチルーム管理 | Elixir / Phoenix |
| `nif` | Elixir-Rust 間 NIF ブリッジ・ゲームループ・RenderFrameBuffer・push_render_frame デコード | Rust / Rustler |
| `physics` | 物理演算・空間ハッシュ・ECS・外部注入パラメータテーブル | Rust |
| `render` | GPU 描画パイプライン・HUD・winit ウィンドウ管理・ヘッドレスモード | Rust / wgpu / egui / winit |
| `audio` | オーディオ管理・アセット読み込み | Rust / rodio |

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
    participant GE as GameEvents GenServer
    participant COMP as Component 群
    participant SS as Contents.SceneStack
    participant S as Scene.update()

    loop 毎フレーム（60Hz）
        R->>R: physics_step()
        R->>R: drain_frame_events()
        R-->>GE: {:frame_events, [enemy_killed, player_damaged, ...]}
        GE->>COMP: on_frame_event/2（スコア・HP・ボス HP 更新）
        GE->>SS: flow_runner 経由で Scene.update() → シーン遷移判断
        GE->>COMP: on_physics_process/1（ボス AI 等）
        GE->>COMP: on_nif_sync/1（Elixir state → Rust 注入）
    end
```

### 4. Phase R-2: Elixir 側による描画命令 push

Elixir 側（contents）が DrawCommand リスト・CameraParams・UiCanvas を組み立て、`push_render_frame` NIF 経由で `RenderFrameBuffer` に書き込む。Rust の `RenderBridge::next_frame()` はこのバッファから RenderFrame を取得し、2D の場合は GameWorld から補間データを読み取ってプレイヤー座標を補間する。

### 5. ContentBehaviour + Component による拡張設計

```mermaid
graph LR
    CFG["config.exs\n:current コンテンツモジュール"]
    CB["ContentBehaviour\ncomponents / initial_scenes\nentity_registry 等"]
    COMP["Component ビヘイビア\non_ready / on_frame_event\non_nif_sync 等（全オプショナル）"]
    GE["Contents.GameEvents\n（contents 層）"]
    VS["VampireSurvivor\n+ SpawnComponent\n+ LevelComponent\n+ BossComponent"]
    AA["AsteroidArena\n+ SpawnComponent\n+ SplitComponent"]

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
    participant APP as GameServer.Application
    participant RS as RoomSupervisor
    participant GEV as GameEvents
    participant NIF as NifBridge (nif)
    participant COMP as Component 群（on_ready）

    MX->>APP: start/2
    APP->>APP: Registry / Contents.SceneStack / InputHandler / EventBus 起動
    APP->>RS: RoomSupervisor 起動
    APP->>APP: StressMonitor / Stats / Telemetry 起動
    APP->>RS: start_room(:main)
    RS->>GEV: GameEvents 起動（:main ルーム）
    GEV->>NIF: create_world()
    NIF-->>GEV: GameWorld リソース
    GEV->>COMP: on_ready(world_ref) × コンポーネント数
    Note over COMP: set_world_size / set_entity_params NIF を呼び出す
    GEV->>NIF: set_map_obstacles(world_ref, obstacles)
    GEV->>NIF: create_game_loop_control()
    GEV->>NIF: create_render_frame_buffer()
    NIF-->>GEV: RenderFrameBuffer リソース
    GEV->>NIF: start_rust_game_loop(world_ref, control_ref, self())
    GEV->>NIF: start_render_thread(world_ref, render_buf_ref, self(), title, atlas_path)
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
    GEV[Elixir Contents.GameEvents プロセス]

    LOOP --> PS
    PS --> PM --> OB --> AI --> SEP --> COL --> WEP --> PAR --> ITEM --> BUL --> BOSS
    LOOP --> DFE --> SEND --> GEV
```

### Elixir 側（イベント駆動）

```mermaid
flowchart TD
    GEV[Contents.GameEvents GenServer\nhandle_info :frame_events]
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
2. `Scene.update/2` — シーン遷移判断
3. `on_physics_process/1` — ボス AI 等の物理コールバック（NIF 書き込みを含む）
4. `on_nif_sync/1` — Elixir state を Rust 側に注入。RenderComponent は `push_render_frame` で DrawCommand・Camera・UiCanvas を RenderFrameBuffer に書き込む

---

## レンダリングスレッド（非同期）

Phase R-2: RenderBridge は `RenderFrameBuffer` から RenderFrame を取得する。Elixir の RenderComponent が `push_render_frame` で毎フレーム書き込む。2D の場合は GameWorld から補間データを読み取り PlayerSprite の座標を補間する。

```mermaid
sequenceDiagram
    participant E as Elixir RenderComponent
    participant RB as RenderBridge
    participant RFB as RenderFrameBuffer
    participant GW as GameWorld
    participant R as Renderer

    loop 毎フレーム（Elixir on_nif_sync）
        E->>RFB: push_render_frame(commands, camera, ui, cursor_grab)
    end

    loop RedrawRequested（VSync）
        RB->>RFB: get()
        RFB-->>RB: RenderFrame
        RB->>GW: read lock（補間データ取得・2D 時のみ PlayerSprite 補間）
        RB-->>R: RenderFrame
        R->>R: update_instances(frame)
        R->>R: render()
        RB->>RB: on_ui_action(pending_action)
        Note over RB: Elixir に UI アクション送信
    end
```

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
    GEV["Contents.GameEvents.handle_info\n{:ui_action, action}"]
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
| control | `create_world`, `create_render_frame_buffer`, `spawn_enemies`, `set_entity_params` | write | 低（起動時・イベント時） |
| inject | `set_hud_state`, `set_hud_level_state`, `set_boss_velocity`, `set_weapon_slots` | write | 高（毎フレーム） |
| render_push | `push_render_frame` | RenderFrameBuffer（別 RwLock） | 高（毎フレーム・on_nif_sync） |
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
        GEV[Contents.GameEvents\nGenServer]
        SS[Contents.SceneStack\nGenServer]
        EVB[EventBus\nGenServer]
        STS[Stats\nGenServer]
    end

    BEAM <-->|NIF Rustler| GW

    subgraph RUST["Rust スレッド群（nif / physics / render / audio）"]
        GL[ゲームループスレッド\n60Hz physics\nnif]
        RT[レンダースレッド\nwinit EventLoop\nrender]
        AT[オーディオスレッド\nrodio / コマンド\naudio]
        GW["GameWorld\n(RwLock&lt;GameWorldInner&gt;)\nphysics"]

        GL <-->|write lock| GW
        RT <-->|read lock| GW
    end
```

---

## 関連ドキュメント

- [**ビジョンと設計思想**](../vision.md) ← エンジン・ワールド・ルール・ゲームの定義
- **Elixir レイヤー**: [server](./elixir/server.md) / [core](./elixir/core.md) / [contents](./elixir/contents.md)（ゲームコンテンツ一覧・設計パターン含む）/ [network](./elixir/network.md)
- **Rust レイヤー**: [nif](./rust/nif.md) / [physics](./rust/physics.md) / [render](./rust/render.md) / [audio](./rust/audio.md) / [input_openxr](./rust/input_openxr.md)
- [改善計画](../task/improvement-plan.md) ← 既知の弱点と改善方針
