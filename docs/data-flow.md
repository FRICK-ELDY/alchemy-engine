# データフロー・通信

## 概要

AlchemyEngine は **Elixir（制御）** と **Rust（演算）** の 2 層構造で動作します。両者の通信は Rustler NIF を介して行われ、ゲームワールドの状態は `GameWorld(RwLock<GameWorldInner>)` として Rust 側に保持されます。

---

## 起動シーケンス

```mermaid
sequenceDiagram
    participant MX as mix run
    participant APP as GameServer.Application
    participant RS as RoomSupervisor
    participant GEV as GameEvents
    participant NIF as NifBridge (Rust)

    MX->>APP: start/2
    APP->>APP: Registry 起動
    APP->>APP: SceneManager 起動
    APP->>APP: InputHandler 起動
    APP->>APP: EventBus 起動
    APP->>RS: RoomSupervisor 起動
    APP->>APP: StressMonitor / Stats / Telemetry 起動
    APP->>RS: start_room(:main)
    RS->>GEV: GameEvents 起動（:main ルーム）
    GEV->>NIF: create_world()
    NIF-->>GEV: GameWorld リソース
    GEV->>NIF: set_map_obstacles(...)
    GEV->>NIF: start_render_thread()
    GEV->>NIF: start_rust_game_loop()
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
    BOSS[ボス AI]
    DFE[drain_frame_events]
    SEND["send {:frame_events, [...]}"]
    GEV[Elixir GameEvents プロセス]

    LOOP --> PS
    PS --> PM --> OB --> AI --> SEP --> COL --> WEP --> PAR --> ITEM --> BUL --> BOSS
    LOOP --> DFE --> SEND --> GEV
```

### Elixir 側（イベント駆動）

```mermaid
flowchart TD
    GEV[GameEvents GenServer\nhandle_info :frame_events]
    EK[EnemyKilled]
    PD[PlayerDamaged]
    LU[LevelUp]
    BD[BossDefeated]
    IP[ItemPickup]
    PER[60フレームごと]

    EB[EventBus.broadcast]
    ST[Stats.record]
    HC{HP <= 0?}
    GO[SceneManager.replace_scene\nGameOver]
    LS[SceneManager.push_scene\nLevelUp]
    LUD[get_level_up_data\n武器選択肢取得]
    LOG[Logger.debug\nFPS・敵数]
    TEL[:telemetry.execute]
    FC[FrameCache.put]

    GEV --> EK --> EB --> ST
    GEV --> PD --> HC
    HC -->|Yes| GO
    GEV --> LU --> LS --> LUD
    GEV --> BD --> EB
    GEV --> IP --> EB
    GEV --> PER --> LOG
    PER --> TEL
    PER --> FC
```

---

## レンダリングスレッド（非同期）

```mermaid
sequenceDiagram
    participant W as winit EventLoop
    participant GW as GameWorld
    participant R as Renderer
    participant GPU as GPU

    loop RedrawRequested（VSync）
        W->>GW: next_frame()
        Note over GW: read lock 取得
        GW->>GW: 最小データをコピー
        Note over GW: read lock 解放（最小化）
        GW->>GW: 補間計算（ロック外）<br/>alpha = (now - prev) / (curr - prev)<br/>player_pos = lerp(prev, curr, alpha)
        GW-->>W: RenderFrame
        W->>R: update_instances(frame)
        R->>GPU: インスタンスバッファ更新
        W->>R: render()
        R->>GPU: スプライトパス
        R->>GPU: egui HUD パス
        W->>GW: on_ui_action(pending_action)
        Note over GW: write lock で UI アクションをキュー
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

### UI アクション（レベルアップ選択・セーブ等）

```mermaid
flowchart TD
    UI[egui ボタン / キー入力]
    OUA["GameWorld.on_ui_action(action)\nMutex pending_action"]
    Q[on_ui_action キュー]
    SEND["Elixir プロセスに send\nRedrawRequested 末尾で取り出し"]
    GEV["GameEvents.handle_info\n{:ui_action, action}"]
    W1["NifBridge.add_weapon()\n:select_weapon_1/2/3"]
    W2["SaveManager.save_session()\n:save"]
    W3["SaveManager.load_session()\n→ NifBridge.load_save_snapshot()\n:load"]

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
| control | `create_world`, `spawn_enemies` | write | 低（イベント時） |
| query_light | `get_player_hp`, `get_enemy_count` | read | 高（毎フレーム可） |
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
    GN["将来: GameNetwork\n外部ログ等"]
    DOWN[":DOWN メッセージ\n→ 自動購読解除"]

    EB --> SUB
    EB --> BC
    BC --> ST
    BC -.->|将来| GN
    SUB -->|死亡検知| DOWN
```

サブスクライバーが死亡した場合、`{:DOWN, ...}` メッセージで自動的に購読解除されます。

---

## セーブ/ロードフロー

### セーブ

```mermaid
sequenceDiagram
    participant SM as SaveManager
    participant NIF as NifBridge (Rust)
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
    participant NIF as NifBridge (Rust)
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
        GEV[GameEvents\nGenServer]
        SCM[SceneManager\nGenServer]
        EVB[EventBus\nGenServer]
        STS[Stats\nGenServer]
    end

    BEAM <-->|NIF Rustler| GW

    subgraph RUST["Rust スレッド群"]
        GL[ゲームループスレッド\n60Hz physics]
        RT[レンダースレッド\nwinit EventLoop]
        AT[オーディオスレッド\nrodio / コマンド]
        GW["GameWorld\n(RwLock&lt;GameWorldInner&gt;)"]

        GL <-->|write lock| GW
        RT <-->|read lock| GW
    end
```

---

## 関連ドキュメント

- [アーキテクチャ概要](./architecture-overview.md)
- [Elixir レイヤー詳細](./elixir-layer.md)
- [Rust レイヤー詳細](./rust-layer.md)
- [ゲームコンテンツ詳細](./game-content.md)
