# apps/contents → native/physics データフローと技術的ボトルネック

> **アーカイブ（2026-04）**: ゲーム用 Rust NIF（`GameWorld`・`physics_step`・60Hz ループ）は撤去済み。以下は **旧アーキテクチャ** のボトルネック分析記録。現行は [overview.md](overview.md) を参照。

> 本ドキュメントは `apps/contents` から `native/physics` までのデータの流れを可視化し、
> 当時技術的にボトルネックになり得る箇所を分析した。

---

## 1. 全体データフロー概要

```mermaid
flowchart TB
    subgraph Elixir["apps/contents (Elixir)"]
        GE[Contents.Events.Game<br/>handle_info :frame_events]
        FE[on_frame_event]
        UP[mod.update]
        PP[on_physics_process]
        NS[on_nif_sync]
        
        GE --> FE
        GE --> UP
        GE --> PP
        GE --> NS
    end
    
    subgraph NIF["native/nif (NIF ブリッジ)"]
        WN[world_nif]
        AN[action_nif]
        RN[read_nif]
        RFN[render_frame_nif]
        GL[game_loop_nif]
    end
    
    subgraph Physics["native/physics (Rust)"]
        GW[(GameWorld<br/>RwLock)]
        PS[physics_step_inner]
    end
    
    subgraph Render["native/render"]
        RFB[(RenderFrameBuffer)]
        RB[render_bridge<br/>next_frame]
    end
    
    FE --> |set_entity_hp<br/>add_score_popup<br/>spawn_item 等| AN
    PP --> |set_player_input<br/>spawn_projectile 等| WN
    NS --> |set_player_snapshot<br/>set_weapon_slots 等| AN
    NS --> |get_render_entities| RN
    NS --> |push_render_frame| RFN
    
    WN --> GW
    AN --> GW
    RN --> GW
    GL --> |physics_step<br/>drain_frame_events| GW
    RFN --> RFB
    RB --> |補間用 read| GW
```

---

## 2. 1 フレームあたりの NIF 呼び出しシーケンス

Rust ゲームループ駆動のフレーム処理において、典型的な（旧）VampireSurvivor コンテンツでの NIF 呼び出し順序。

```mermaid
sequenceDiagram
    participant RGL as Rust Game Loop
    participant GW as GameWorld (RwLock)
    participant E as Elixir Contents.Events.Game
    participant LC as LevelComponent
    participant BC as BossComponent
    participant RC as RenderComponent
    
    Note over RGL,GW: 1. Rust 側 (60Hz)
    RGL->>GW: physics_step (write lock)
    RGL->>GW: drain_frame_events (write lock)
    RGL->>E: send {:frame_events, events}
    
    Note over E,RC: 2. Elixir 側 (イベント処理)
    E->>LC: on_frame_event × N 件
    loop イベント毎
        LC->>GW: add_score_popup (write)
        LC->>GW: spawn_item (write)
    end
    
    Note over E,RC: 3. 入力・物理コールバック
    E->>GW: set_player_input (write)
    E->>BC: on_physics_process
    BC->>GW: set_special_entity_snapshot (write)
    BC->>GW: spawn_projectile (write)
    
    Note over E,RC: 4. NIF 同期 (on_nif_sync)
    E->>LC: on_nif_sync
    LC->>GW: set_player_snapshot (write)
    LC->>GW: set_elapsed_seconds (write)
    LC->>GW: set_weapon_slots (write)
    LC->>GW: set_enemy_damage_this_frame (write)
    
    E->>RC: on_nif_sync
    RC->>GW: get_render_entities (read)
    RC->>RFB: push_render_frame (decode + write)
```

---

## 3. ボトルネック一覧と重症度

| # | ボトルネック | 重症度 | 影響範囲 |
|:--:|:---|:---:|:---|
| 1 | **GameWorld 単一 RwLock 競合** | 高 | 全 NIF・レンダー |
| 2 | **毎フレーム複数 write NIF 呼び出し** | 高 | Elixir ↔ Rust 境界 |
| 3 | **get_render_entities の O(n) コピー** | 中 | 敵・弾・パーティクル増加時 |
| 4 | **push_render_frame の decode オーバーヘッド** | 中 | UI 複雑化・DrawCommand 増加時 |
| 5 | **Rust ループと Elixir のタイミング競合** | 中 | ロック待ち・スケジューリング |
| 6 | **NIF 実行による BEAM ブロック** | 低〜中 | DirtyCpu 指定の有無に依存 |

---

## 4. ボトルネック詳細図

### 4.1 GameWorld RwLock 競合

```mermaid
flowchart LR
    subgraph Writers["write lock 競合"]
        PS[physics_step]
        SI[set_player_input]
        WS[set_weapon_slots]
        SS[set_special_entity_snapshot]
        SPS[set_player_snapshot]
        SED[set_enemy_damage_this_frame]
    end
    
    subgraph Readers["read lock 競合"]
        GRE[get_render_entities]
        RB[render_bridge]
    end
    
    GW[(GameWorld<br/>単一 RwLock)]
    
    PS --> GW
    SI --> GW
    WS --> GW
    SS --> GW
    SPS --> GW
    SED --> GW
    GRE --> GW
    RB --> GW
```

**問題点:**
- 単一の `RwLock<GameWorldInner>` を全 NIF・レンダースレッドが共有
- write 要求が並ぶと、各 NIF 呼び出しごとに lock 取得・解放が発生
- `lock_metrics.rs` で 300μs(read) / 500μs(write) 超えで warn 出力

---

### 4.2 毎フレーム write NIF 呼び出し数（旧 VampireSurvivor 想定）

```mermaid
pie title 1フレームあたりの GameWorld write lock 取得回数（想定）
    "physics_step (Rust loop)" : 1
    "set_player_input" : 1
    "set_weapon_slots" : 1
    "set_special_entity_snapshot" : 1
    "set_player_snapshot" : 1
    "set_elapsed_seconds" : 1
    "set_enemy_damage_this_frame" : 1
    "on_frame_event 内 (add_score_popup, spawn_item 等)" : 2
```

**最小 7〜9 回/フレーム** の write lock 取得が発生。バッチ化設計がないため、lock の取得・解放オーバーヘッドが積み重なる。

---

### 4.3 get_render_entities のデータ量

```mermaid
flowchart TB
    subgraph GameWorldInner["GameWorldInner (SoA)"]
        EX[enemies.positions_x/y]
        BX[bullets.positions_x/y]
        PX[particles.*]
        IX[items.*]
    end
    
    subgraph Copy["毎フレーム O(n) コピー"]
        EV[Vec&lt;f64,f64,u32&gt;]
        BV[Vec&lt;f64,f64,u32&gt;]
        PV[Vec&lt;7要素&gt;]
        IV[Vec&lt;f64,f64,u32&gt;]
    end
    
    EX --> EV
    BX --> BV
    PX --> PV
    IX --> IV
    
    EV --> RC[RenderComponent]
    BV --> RC
    PV --> RC
    IV --> RC
```

**問題点:**
- 敵 100体・弾 200発・パーティクル 500 の場合、毎フレーム数千要素の `Vec` を新規アロケーション
- read lock 保持時間が長くなり、Rust ループの physics_step 開始をブロック

---

### 4.4 push_render_frame の decode パイプライン

```mermaid
flowchart LR
    subgraph Elixir["Elixir タプル"]
        DC[DrawCommand リスト]
        CAM[CameraParams]
        UI[UiCanvas ツリー]
    end
    
    subgraph Decode["NIF 内 decode"]
        DD[decode_commands]
        DCAM[decode_camera]
        DUI[decode_ui_canvas<br/>再帰的]
    end
    
    subgraph Rust["Rust 構造体"]
        RF[RenderFrame]
    end
    
    DC --> DD
    CAM --> DCAM
    UI --> DUI
    
    DD --> RF
    DCAM --> RF
    DUI --> RF
```

**問題点:**
- `decode_ui_canvas` は UiNode の再帰的デコード。UI が深いとコスト増
- DrawCommand が敵・弾・パーティクル分だけ増えると、タプル decode の繰り返しが重い

---

## 5. タイムライン上の競合

```mermaid
flowchart TB
    subgraph Phase1["Phase 1: Rust (write)"]
        R1[physics_step]
        R2[drain_frame_events]
        R3[send to Elixir]
    end
    
    subgraph Phase2["Phase 2: Elixir (write×多数)"]
        E1[on_frame_event]
        E2[set_player_input]
        E3[on_physics_process]
        E4[set_* x5]
    end
    
    subgraph Phase3["Phase 3: Elixir (read + push)"]
        E5[get_render_entities]
        E6[push_render_frame]
    end
    
    subgraph Parallel["並行: Render Thread (read)"]
        T1[next_frame<br/>補間用 read]
    end
    
    R1 --> R2 --> R3
    R3 --> E1 --> E2 --> E3 --> E4
    E4 --> E5 --> E6
    
    T1 -.->|競合| R1
    T1 -.->|競合| E4
```

**競合の要点:**
- Rust ループが write 中は Elixir の NIF が待機
- Elixir が get_render_entities で read 中は、Rust の次の physics_step が write で待機
- レンダースレッドは next_frame で read を要求。write が長いと補間データ取得が遅延

---

## 6. 改善提案の方向性

| ボトルネック | 改善案 |
|:---|:---|
| 単一 RwLock | 注入データ用バッファを分離し、physics 計算と並列化可能な構造を検討。または lock-free キューでバッチ転送 |
| 複数 write NIF | `set_frame_injection(world, snapshot)` のような **1 回の NIF で全注入データをまとめて渡す** バッチ API を検討 |
| get_render_entities | 差分更新・オブジェクトプール・描画用ダブルバッファなど、コピー削減の設計を検討 |
| push_render_frame decode | UiCanvas の差分更新、またはバイナリ形式（protobuf）での転送を検討 |
| タイミング競合 | Rust ループと Elixir の処理順序を明確化。または「Rust が dt 進める → Elixir が NIF で注入」のフェーズ分離を固定 |

---

## 7. 採用しない方針（案 B）

**案 B: Rust 側で SoA から DrawCommand を生成** は **採用しない**。

理由: Rust に描画判断（メッシュ選択・UV・スプライト配置等）を持たせることになり、
「Elixir が定義、Rust が実行」の原則に反する。現行の設計（Elixir が DrawCommand を組み立て、
Rust が decode して描画する）を維持する。

参照: [contents-defines-rust-executes.md](../plan/backlog/contents-defines-rust-executes.md) セクション 5

---

## 8. 関連ドキュメント

- [Rust: nif](rust/nif.md)
- [Rust: physics](rust/nif/physics.md)
- [Elixir: core](elixir/core.md)
- [Elixir: contents](elixir/contents.md)
- [draw-command-spec.md](draw-command-spec.md) — DrawCommand タグ・フィールド仕様（SSoT）
