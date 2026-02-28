# AlchemyEngine — アーキテクチャ概要

## 設計思想

AlchemyEngine は **Elixir を Single Source of Truth（SSoT）** として、Rust の ECS で物理演算・描画・オーディオを処理するハイブリッドゲームエンジンです。

- **Elixir 側**: ゲームロジックの制御フロー・シーン管理・セーブ/ロード・イベント配信
- **Rust 側**: 60Hz 固定の物理演算・衝突判定・描画・オーディオ

---

## 全体構成

```mermaid
graph TB
    subgraph Elixir["Elixir Umbrella"]
        GS[game_server<br/>起動制御]
        GE[game_engine<br/>SSoT コア]
        GC[game_content<br/>VampireSurvivor]
        GN[game_network<br/>通信スタブ]
        GS -->|依存| GE
        GC -->|依存| GE
    end

    GE <-->|Rustler NIF| GNIF

    subgraph Rust["Rust Workspace"]
        GNIF[game_nif<br/>NIF インターフェース / ゲームループ / レンダーブリッジ]
        GSIM[game_simulation<br/>物理 / ECS]
        GRENDER[game_render<br/>wgpu 描画]
        GAUDIO[game_audio<br/>rodio オーディオ]
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
│   └── config.exs                   # 起動ゲーム・マップ設定
│
├── apps/                            # Elixir アプリケーション群
│   ├── game_engine/                 # SSoT コアエンジン
│   │   ├── mix.exs
│   │   └── lib/game_engine/
│   │       ├── game_engine.ex       # 公開 API（エントリポイント）
│   │       ├── nif_bridge.ex        # Rustler NIF ラッパー
│   │       ├── game_behaviour.ex    # ゲーム実装インターフェース
│   │       ├── scene_behaviour.ex   # シーンコールバック定義
│   │       ├── scene_manager.ex     # シーンスタック管理 GenServer
│   │       ├── game_events.ex       # メインゲームループ GenServer
│   │       ├── room_supervisor.ex   # DynamicSupervisor
│   │       ├── room_registry.ex     # Registry ラッパー
│   │       ├── event_bus.ex         # フレームイベント配信 GenServer
│   │       ├── input_handler.ex     # キー入力 GenServer
│   │       ├── frame_cache.ex       # フレームスナップショット ETS
│   │       ├── map_loader.ex        # マップ障害物定義
│   │       ├── save_manager.ex      # セーブ/ロード
│   │       ├── stats.ex             # セッション統計 GenServer
│   │       ├── telemetry.ex         # Telemetry Supervisor
│   │       └── stress_monitor.ex    # パフォーマンス監視 GenServer
│   │
│   ├── game_server/                 # 起動プロセス
│   │   ├── mix.exs
│   │   └── lib/game_server/
│   │       ├── game_server.ex
│   │       └── application.ex       # OTP Application / Supervisor ツリー
│   │
│   ├── game_content/                # ゲームコンテンツ（VampireSurvivor）
│   │   ├── mix.exs
│   │   └── lib/game_content/
│   │       ├── vampire_survivor.ex  # GameBehaviour 実装
│   │       ├── spawn_system.ex      # ウェーブスポーン
│   │       ├── boss_system.ex       # ボス出現スケジュール
│   │       ├── level_system.ex      # 武器選択生成
│   │       └── scenes/
│   │           ├── playing.ex       # プレイ中シーン
│   │           ├── level_up.ex      # レベルアップ選択シーン
│   │           ├── boss_alert.ex    # ボス出現アラートシーン
│   │           └── game_over.ex     # ゲームオーバーシーン
│   │
│   └── game_network/                # 通信（スタブ・将来実装）
│       ├── mix.exs
│       └── lib/game_network.ex
│
├── native/                          # Rust クレート群
│   ├── Cargo.toml                   # Rust ワークスペース定義
│   ├── Cargo.lock
│   │
│   ├── game_simulation/             # 物理演算・ECS（依存: rustc-hash のみ）
│   │   └── src/
│   │       ├── lib.rs
│   │       ├── constants.rs         # 画面・マップ・速度定数
│   │       ├── entity_params.rs     # ID ベースパラメータテーブル
│   │       ├── enemy.rs             # EnemyKind enum
│   │       ├── weapon.rs            # WeaponKind / WeaponSlot
│   │       ├── boss.rs              # BossKind enum
│   │       ├── item.rs              # ItemKind / ItemWorld SoA
│   │       ├── util.rs              # EXP 計算・ウェーブ設定
│   │       ├── physics/
│   │       │   ├── rng.rs           # LCG 乱数（決定論的）
│   │       │   ├── spatial_hash.rs  # FxHashMap ベース空間ハッシュ
│   │       │   ├── separation.rs    # 敵分離アルゴリズム
│   │       │   └── obstacle_resolve.rs # 障害物押し出し
│   │       ├── world/
│   │       │   ├── mod.rs           # GameWorld / GameWorldInner
│   │       │   ├── enemy.rs         # EnemyWorld SoA
│   │       │   ├── bullet.rs        # BulletWorld SoA
│   │       │   ├── particle.rs      # ParticleWorld SoA
│   │       │   ├── boss.rs          # BossState
│   │       │   ├── game_loop_control.rs # AtomicBool pause/resume
│   │       │   └── frame_event.rs   # FrameEvent enum
│   │       └── game_logic/
│   │           ├── physics_step.rs  # 1 フレーム物理ステップ
│   │           ├── chase_ai.rs      # SSE2 SIMD / rayon 並列 AI
│   │           └── systems/
│   │               ├── weapons.rs   # 7 武器発射ロジック
│   │               ├── projectiles.rs # 弾丸移動・衝突・ドロップ
│   │               ├── boss.rs      # ボス AI・特殊行動
│   │               ├── effects.rs   # パーティクル更新
│   │               ├── items.rs     # アイテム収集
│   │               ├── leveling.rs  # 武器選択肢生成
│   │               ├── collision.rs # 敵 vs 障害物押し出し
│   │               └── spawn.rs     # スポーン位置生成
│   │
│   ├── game_nif/                    # NIF 通信インターフェース・ゲームループ
│   │   └── src/
│   │       ├── lib.rs               # Rustler エントリポイント・アトム定義
│   │       ├── nif/
│   │       │   ├── load.rs          # パニックフック・リソース登録
│   │       │   ├── world_nif.rs     # ワールド生成・入力・スポーン
│   │       │   ├── action_nif.rs    # 武器追加・レベルアップ・ボス操作
│   │       │   ├── read_nif.rs      # 状態読み取り（軽量クエリ）
│   │       │   ├── game_loop_nif.rs # ゲームループ制御
│   │       │   ├── push_tick_nif.rs # Elixir プッシュ型同期
│   │       │   ├── render_nif.rs    # レンダースレッド起動
│   │       │   ├── save_nif.rs      # セーブ/ロードスナップショット
│   │       │   ├── events.rs        # FrameEvent → Elixir アトム変換
│   │       │   └── util.rs          # 共通ユーティリティ
│   │       ├── render_bridge.rs     # RenderBridge 実装
│   │       ├── render_snapshot.rs   # RenderFrame 構築・補間
│   │       └── lock_metrics.rs      # RwLock 待機時間メトリクス
│   │
│   ├── game_audio/                  # rodio オーディオ管理
│   │   └── src/
│   │       ├── lib.rs
│   │       ├── audio.rs             # AudioManager・コマンドループ
│   │       └── asset/mod.rs         # アセット管理
│   │
│   └── game_render/                 # wgpu 描画パイプライン
│       └── src/
│           ├── lib.rs               # 公開型（RenderFrame / HudData）
│           ├── window.rs            # winit ウィンドウ管理・イベントループ
│           └── renderer/
│               ├── mod.rs           # Renderer 構造体（wgpu 初期化・描画）
│               ├── ui.rs            # egui HUD
│               └── shaders/
│                   └── sprite.wgsl  # WGSL スプライトシェーダー
│
├── assets/                          # スプライト・音声アセット
└── saves/                           # セーブデータ
    ├── session.dat                  # セッションデータ（Erlang term binary）
    └── high_scores.dat              # ハイスコア上位 10 件
```

---

## レイヤー間の責務分担

| レイヤー | 責務 | 技術 |
|:---|:---|:---|
| `game_server` | OTP Application 起動・Supervisor ツリー構築 | Elixir / OTP |
| `game_engine` | ゲームループ制御・シーン管理・イベント配信・セーブ | Elixir GenServer / ETS |
| `game_content` | ゲーム固有ロジック（VampireSurvivor のルール） | Elixir |
| `game_nif` | Elixir-Rust 間 NIF ブリッジ・ゲームループ・レンダーブリッジ | Rust / Rustler |
| `game_simulation` | 物理演算・空間ハッシュ・エンティティ定義・ECS | Rust（no_std 互換） |
| `game_render` | GPU 描画パイプライン・HUD・winit ウィンドウ管理 | Rust / wgpu / egui / winit |
| `game_audio` | オーディオ管理・アセット読み込み | Rust / rodio |

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
    participant SM as SceneManager
    participant S as Scene.update()

    loop 毎フレーム（60Hz）
        R->>R: physics_step()
        R->>R: drain_frame_events()
        R-->>GE: {:frame_events, [enemy_killed, level_up, ...]}
        GE->>GE: シーン遷移・セーブ・UI アクション処理
        GE->>SM: push / pop / replace
        SM->>S: update(context, state)
    end
```

---

## 関連ドキュメント

- [Elixir レイヤー詳細](./elixir-layer.md)
- [Rust レイヤー詳細](./rust-layer.md)
- [データフロー・通信](./data-flow.md)
- [ゲームコンテンツ詳細](./game-content.md)
- [Elixir as SSoT 移行計画](./elixir-as-ssot-migration.md)
- [ビジュアルエディタ アーキテクチャ](./visual-editor-architecture.md)
