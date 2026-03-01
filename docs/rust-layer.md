# Rust レイヤー詳細

## 概要

Rust 側は **Cargo ワークスペース** として構成され、4 つのクレートに分割されています。60Hz 固定の物理演算・衝突判定・描画・オーディオを担当します。

---

## クレート構成と依存関係

```mermaid
graph LR
    GN[game_nif<br/>NIF インターフェース<br/>ゲームループ / レンダーブリッジ]
    GS[game_physics<br/>物理 / ECS<br/>依存: rustc-hash / rayon / log]
    GR[game_render<br/>wgpu 描画 / winit ウィンドウ<br/>ヘッドレスモード対応]
    GA[game_audio<br/>rodio オーディオ]

    GN -->|依存| GS
    GN -->|依存| GR
    GN -->|依存| GA
    GR -->|依存| GS
```

---

## `game_physics` — 物理演算・ECS

依存クレートは `rustc-hash = "2"`, `rayon = "1"`, `log = "0.4"`。

### `constants.rs`

| 定数 | 値 | 説明 |
|:---|:---|:---|
| `SCREEN_WIDTH` | 1280 | 画面幅（px） |
| `SCREEN_HEIGHT` | 720 | 画面高さ（px） |
| `MAP_WIDTH` | 4096 | マップ幅（px） |
| `MAP_HEIGHT` | 4096 | マップ高さ（px） |
| `PLAYER_SPEED` | 200.0 | プレイヤー速度（px/s） |
| `BULLET_SPEED` | 400.0 | 弾速（px/s） |
| `CELL_SIZE` | 80 | 空間ハッシュセルサイズ（px） |
| `INVINCIBLE_DURATION` | 0.5 | 無敵時間（秒） |

### `entity_params.rs` — 外部注入パラメータテーブル

`EntityParamTables` 構造体として定義され、`set_entity_params` NIF 経由で Elixir 側から注入される。
ハードコードされたパラメータは持たず、`default()` は空テーブルを返す。

```rust
pub struct EntityParamTables {
    pub enemies:  Vec<EnemyParams>,
    pub weapons:  Vec<WeaponParams>,
    pub bosses:   Vec<BossParams>,
}
```

**`EnemyParams`:**

```rust
pub struct EnemyParams {
    pub max_hp:           f32,
    pub speed:            f32,
    pub radius:           f32,
    pub damage_per_sec:   f32,
    pub render_kind:      u8,
    pub particle_color:   [f32; 4],
    pub passes_obstacles: bool,   // Ghost など障害物すり抜け
}
```

**`WeaponParams` と `FirePattern`:**

```rust
pub enum FirePattern {
    Aimed,     // 最近接敵に向けて扇状（magic_wand）
    FixedUp,   // 固定方向（axe: 上方向）
    Radial,    // 全方向（cross: 4/8方向）
    Whip,      // 扇形直接判定（弾丸なし）
    Aura,      // プレイヤー周囲オーラ（garlic）
    Piercing,  // 貫通弾（fireball）
    Chain,     // 連鎖電撃（lightning）
}

pub struct WeaponParams {
    pub cooldown:     f32,
    pub damage:       i32,
    pub as_u8:        u8,
    pub bullet_table: Option<Vec<usize>>,  // レベル別弾数テーブル
    pub fire_pattern: FirePattern,
    pub range:        f32,        // Whip/Aura の基本半径
    pub chain_count:  u8,         // Chain パターンの連鎖数
}
```

**`BossParams`:**

```rust
pub struct BossParams {
    pub max_hp:           f32,
    pub speed:            f32,
    pub radius:           f32,
    pub damage_per_sec:   f32,
    pub render_kind:      u8,
    pub special_interval: f32,  // 特殊行動インターバル（秒）
}
```

### `weapon.rs` — WeaponSlot

クールダウン管理のみを担当。ダメージ計算は `WeaponParams` を参照する。

```rust
pub struct WeaponSlot {
    pub kind_id:       u8,
    pub level:         u32,
    pub cooldown_timer: f32,  // 残りクールダウン（秒）
}
```

### `physics/` — 物理演算ユーティリティ

```mermaid
graph LR
    PH[physics/]
    RNG[rng.rs<br/>LCG 乱数<br/>決定論的・no-std]
    SH[spatial_hash.rs<br/>FxHashMap ベース<br/>空間ハッシュ]
    SEP[separation.rs<br/>敵分離アルゴリズム<br/>O n]
    OBR[obstacle_resolve.rs<br/>障害物押し出し<br/>最大 5 回反復]

    PH --> RNG
    PH --> SH
    PH --> SEP
    PH --> OBR
    SEP -->|利用| SH
```

#### `spatial_hash.rs` — 空間ハッシュ

```rust
struct CollisionWorld {
    dynamic: SpatialHash,  // 毎フレーム更新（敵・弾）
    static_: SpatialHash,  // 障害物（変化なし）
}
```

セルサイズ 80px で `O(n)` の近傍検索を実現。

### `world/` — ゲームワールド型

```mermaid
graph TD
    GW["GameWorld\n(RwLock&lt;GameWorldInner&gt;)"]
    GWI[GameWorldInner<br/>全ゲーム状態]
    PS[PlayerState]
    EW[EnemyWorld<br/>SoA 構造]
    BW[BulletWorld<br/>SoA 構造]
    PW[ParticleWorld<br/>SoA 構造]
    IW[ItemWorld<br/>SoA 構造]
    BS[BossState<br/>ボス状態]
    ET[EntityParamTables<br/>NIF で外部注入]
    GLC[GameLoopControl<br/>AtomicBool pause/resume]
    FE[FrameEvent<br/>イベント enum]

    GW --> GWI
    GWI --> PS
    GWI --> EW
    GWI --> BW
    GWI --> PW
    GWI --> IW
    GWI --> BS
    GWI --> ET
    GWI --> FE
    GW --> GLC
```

**`GameWorldInner` の主要フィールドと Elixir SSoT の対応:**

| フィールド | 権威 | 注入 NIF |
|:---|:---|:---|
| `player.hp` | Elixir | `set_player_hp` |
| `player.input_dx/dy` | Elixir | `set_player_input` |
| `elapsed_seconds` | Elixir | `set_elapsed_seconds` |
| `boss.hp` | Elixir | `set_boss_hp` |
| `score`, `kill_count` | Elixir | `set_hud_state` |
| `params` | Elixir | `set_entity_params` |
| `map_width/height` | Elixir | `set_world_size` |
| `hud_level/exp/exp_to_next` 等 | Elixir | `set_hud_level_state`（描画専用） |
| `weapon_slots` | Elixir | `set_weapon_slots`（I-2: 毎フレーム差分注入） |

#### SoA（Structure of Arrays）構造

```rust
struct EnemyWorld {
    positions_x: Vec<f32>,    // 全敵の X 座標
    positions_y: Vec<f32>,    // 全敵の Y 座標
    velocities:  Vec<[f32; 2]>,
    hp:          Vec<f32>,
    alive:       Vec<bool>,
    kind_ids:    Vec<u8>,
    free_list:   Vec<usize>,  // O(1) スポーン/キル
}
```

#### `FrameEvent` — フレームイベント

```rust
enum FrameEvent {
    /// 敵が撃破された。x/y はアイテムドロップ位置として Elixir 側で使用する。
    EnemyKilled { enemy_kind: u8, x: f32, y: f32 },
    PlayerDamaged { damage: f32 },
    ItemPickup { item_kind: u8 },
    /// 特殊エンティティ（ボス等）が撃破された。
    /// ボス種別は Elixir 側 Component state で管理するため entity_kind フィールドなし。
    SpecialEntityDefeated { x: f32, y: f32 },
    /// 特殊エンティティが出現した。Elixir 側で HP 初期化に使用する。
    SpecialEntitySpawned { entity_kind: u8 },
    /// 特殊エンティティがダメージを受けた。Elixir 側で HP 減算に使用する。
    SpecialEntityDamaged { damage: f32 },
}
```

> **注意**: 旧設計の `EntityRemoved`, `LevelUp`, `BossDefeated` バリアントは廃止済み。
> レベルアップは Elixir 側 `LevelComponent` が EXP 積算で判定する。

### `game_logic/` — 物理・AI・システム

#### `physics_step.rs` — 1 フレーム物理ステップ

```mermaid
flowchart TD
    START[physics_step 開始]
    T[経過時間更新]
    PM[プレイヤー移動\n入力ベクトル × 速度 × dt]
    OB[障害物押し出し\nobstacle_resolve]
    AI[Chase AI\n敵がプレイヤーを追跡]
    SEP[敵分離\nseparation]
    COL[敵 vs プレイヤー衝突]
    WEP[武器攻撃\n各武器クールダウン管理]
    PAR[パーティクル更新]
    ITEM[アイテム更新\n磁石・自動収集]
    BUL[弾丸更新\n移動・衝突・ドロップ]
    BOSS[ボス更新\n物理のみ（AI は Elixir 側）]
    END[physics_step 終了]

    START --> T --> PM --> OB --> AI --> SEP --> COL --> WEP --> PAR --> ITEM --> BUL --> BOSS --> END
```

#### `chase_ai.rs` — 敵追跡 AI（プラットフォーム別最適化）

```mermaid
graph LR
    AI[chase_ai]
    SIMD["x86_64\nSSE2 SIMD\n4体並列処理\n_mm_load_ps / _mm_sub_ps / _mm_mul_ps"]
    PAR["その他\nrayon 並列処理\npar_iter_mut"]

    AI -->|cfg target_arch = x86_64| SIMD
    AI -->|cfg not x86_64| PAR
```

#### `systems/` — ゲームシステム群

```mermaid
graph TD
    SYS[systems/]
    WEP[weapons.rs<br/>武器発射ロジック<br/>FirePattern 対応]
    PRJ[projectiles.rs<br/>弾丸移動・衝突・ドロップ]
    BOSS[boss.rs<br/>ボス物理のみ<br/>AI は Elixir 側]
    EFF[effects.rs<br/>パーティクル更新]
    ITEM[items.rs<br/>アイテム収集]
    COL[collision.rs<br/>敵 vs 障害物押し出し]
    SPW[spawn.rs<br/>スポーン位置生成]

    SYS --> WEP
    SYS --> PRJ
    SYS --> BOSS
    SYS --> EFF
    SYS --> ITEM
    SYS --> COL
    SYS --> SPW
```

> `leveling.rs`（武器選択肢生成）は廃止済み。武器選択肢の生成は Elixir 側 `LevelSystem` が担当する。

**武器発射パターン（`FirePattern` 対応）:**

| FirePattern | 武器例 | 発射パターン |
|:---|:---|:---|
| `Aimed` | MagicWand | 最近傍の敵に向けて扇状発射 |
| `FixedUp` | Axe | 上方向固定、放物線軌道 |
| `Radial` | Cross | 全方向（4/8方向）同時発射 |
| `Whip` | Whip | 扇形直接判定（弾丸なし） |
| `Piercing` | Fireball | 最近傍の敵に向けて貫通弾 |
| `Chain` | Lightning | 最近傍の敵に連鎖電撃 |
| `Aura` | Garlic | プレイヤー周囲継続ダメージ |

**ボス物理（`boss.rs`）:**

Rust はボスの物理的存在（位置・HP・当たり判定・弾丸 vs ボス衝突）のみ管理する。
- **移動**: Elixir が `set_boss_velocity` NIF で注入した速度ベクトルで移動
- **特殊行動**: Elixir の `BossComponent.on_physics_process/1` が NIF 経由で制御
- **撃破判定**: Rust が判定し `SpecialEntityDefeated` イベントを発行

---

## `game_nif` — NIF インターフェース・ゲームループ

### `lib.rs` — エントリポイント

```rust
rustler::atoms! {
    ok, error, nil,
    enemy_killed, player_damaged, item_pickup,
    special_entity_spawned, special_entity_damaged, special_entity_defeated,
    // ... ゲームアトム
}

#[cfg(feature = "umbrella")]
rustler::init!("Elixir.GameEngine.NifBridge", load = nif::load);
```

### `nif/` — NIF 関数群

```mermaid
graph TD
    NIF[nif/]
    LOAD[load.rs<br/>パニックフック<br/>リソース登録]
    WORLD[world_nif.rs<br/>ワールド生成・入力・スポーン]
    ACTION[action_nif.rs<br/>武器スロット・ボス操作]
    READ[read_nif.rs<br/>状態読み取り 軽量]
    LOOP[game_loop_nif.rs<br/>ゲームループ制御]
    PUSH[push_tick_nif.rs<br/>Elixir プッシュ型同期]
    RENDER[render_nif.rs<br/>レンダースレッド起動]
    SAVE[save_nif.rs<br/>セーブ/ロード]
    EVENTS[events.rs<br/>FrameEvent → Elixir アトム変換]

    NIF --> LOAD
    NIF --> WORLD
    NIF --> ACTION
    NIF --> READ
    NIF --> LOOP
    NIF --> PUSH
    NIF --> RENDER
    NIF --> SAVE
    NIF --> EVENTS
```

#### NIF 関数一覧

**`world_nif.rs`（ワールド生成・入力・スポーン・パラメータ注入）:**

| NIF 関数 | 説明 |
|:---|:---|
| `create_world()` | `GameWorld` リソースを生成して返す |
| `set_player_input(world, dx, dy)` | 移動ベクトルを設定 |
| `spawn_enemies(world, kind_id, count)` | 敵をスポーン |
| `spawn_enemies_at(world, kind_id, positions)` | 指定座標リストに敵をスポーン |
| `set_map_obstacles(world, obstacles)` | 障害物リストを設定 |
| `set_entity_params(world, enemies, weapons, bosses)` | エンティティパラメータを注入 |
| `set_world_size(world, width, height)` | マップサイズを設定 |
| `set_player_hp(world, hp)` | プレイヤー HP を注入 |
| `set_elapsed_seconds(world, elapsed)` | 経過時間を注入 |
| `set_boss_hp(world, hp)` | ボス HP を注入 |
| `set_hud_state(world, score, kill_count)` | HUD スコア・キル数を注入 |
| `set_hud_level_state(world, level, exp, ...)` | HUD レベル・EXP 状態を注入（描画専用） |

**`action_nif.rs`（武器・ボス操作）:**

| NIF 関数 | 説明 |
|:---|:---|
| `set_weapon_slots(world, slots)` | 武器スロット全体を注入（I-2: 毎フレーム差分注入） |
| `spawn_boss(world, boss_id)` | ボスをスポーン |
| `spawn_elite_enemy(world, kind_id, count, hp_mult)` | エリート敵をスポーン |
| `spawn_item(world, x, y, kind, value)` | アイテムをスポーン |
| `set_boss_velocity(world, vx, vy)` | ボス速度を注入（AI） |
| `set_boss_invincible(world, invincible)` | ボス無敵状態を設定（AI） |
| `set_boss_phase_timer(world, timer)` | ボス特殊行動タイマーを設定（AI） |
| `fire_boss_projectile(world, dx, dy, speed, dmg, lifetime)` | ボス弾を発射（AI） |
| `get_boss_state(world)` | ボス状態を取得（AI 用） |
| `add_score_popup(world, x, y, value)` | スコアポップアップを描画バッファに追加 |

> **注意**: 旧設計の `add_weapon(world, weapon_id)` NIF は廃止済み。
> 武器管理は `set_weapon_slots` で毎フレーム Elixir 側から全スロットを注入する設計（I-2）に変更された。

**`read_nif.rs`（軽量・毎フレーム利用可）:**

| NIF 関数 | 説明 |
|:---|:---|
| `get_player_pos(world)` | プレイヤー座標 `{x, y}` |
| `get_player_hp(world)` | プレイヤー HP |
| `get_enemy_count(world)` | 生存敵数 |
| `get_hud_data(world)` | HUD 表示データ全体 |
| `get_frame_metadata(world)` | フレームメタデータ |
| `get_weapon_levels(world)` | 全武器レベル（`%{kind_id => level}`） |
| `is_player_dead(world)` | 死亡判定 |

**`game_loop_nif.rs`:**

| NIF 関数 | 説明 |
|:---|:---|
| `physics_step(world, dt)` | 1 フレーム物理ステップ（DirtyCpu） |
| `drain_frame_events(world)` | フレームイベントを取り出す |
| `create_game_loop_control()` | `GameLoopControl` リソース生成 |
| `start_rust_game_loop(world, control, pid)` | 別スレッドで 60Hz 固定ループ開始 |
| `pause_physics(control)` | 物理演算を一時停止 |
| `resume_physics(control)` | 物理演算を再開 |

---

### `render_bridge.rs` — RenderBridge 実装

ロック競合を最小化するため、ロック内でのデータコピーを最小限に抑えます。

```mermaid
sequenceDiagram
    participant RT as レンダースレッド
    participant RB as RenderBridge
    participant GW as GameWorld RwLock

    RT->>RB: next_frame()
    RB->>GW: read lock 取得
    GW-->>RB: 最小データをコピー
    RB->>GW: read lock 解放（即座）
    RB->>RB: 補間計算（ロック外）<br/>lerp(prev_pos, curr_pos, alpha)
    RB-->>RT: RenderFrame
```

### `lock_metrics.rs` — RwLock 待機時間メトリクス

| 閾値 | アクション |
|:---|:---|
| read lock > 300μs | `log::warn!` |
| write lock > 500μs | `log::warn!` |
| 5 秒ごと | 平均待機時間をレポート |

---

## `game_audio` — rodio オーディオ管理

### `audio.rs`

```mermaid
graph LR
    AC[AudioCommand enum<br/>PlayBgm / PlaySfx<br/>StopBgm / SetVolume]
    ACS[AudioCommandSender]
    AT[オーディオスレッド<br/>コマンドループ]
    AM[AudioManager<br/>bgm_sink + OutputStream]

    ACS -->|send| AT
    AT --> AM
    AC -->|経由| ACS
```

### `asset/mod.rs` — アセット管理

```mermaid
flowchart LR
    REQ[アセット要求]
    P1["1. ゲーム別パス\nassets/{game_name}/..."]
    P2["2. ベースパス\nassets/..."]
    P3["3. カレントディレクトリ"]
    P4["4. コンパイル時埋め込み\ninclude_bytes!"]
    RES[アセット返却]

    REQ --> P1
    P1 -->|見つからない| P2
    P2 -->|見つからない| P3
    P3 -->|見つからない| P4
    P1 & P2 & P3 & P4 -->|見つかった| RES
```

---

## `game_render` — wgpu 描画パイプライン・ウィンドウ管理

### `window.rs` — winit ウィンドウ管理

winit ウィンドウのイベントループと `RenderBridge` トレイトを定義します。

#### キー入力マッピング

| キー | 動作 |
|:---|:---|
| W / ↑ | 上移動 |
| S / ↓ | 下移動 |
| A / ← | 左移動 |
| D / → | 右移動 |
| 斜め入力 | 正規化（速度一定） |

#### フレームループ

```mermaid
flowchart TD
    RR[RedrawRequested]
    NF["bridge.next_frame()\n→ RenderFrame"]
    UI["renderer.update_instances(frame)"]
    REN[renderer.render]
    ACT["bridge.on_ui_action(pending_action)"]

    RR --> NF --> UI --> REN --> ACT --> RR
```

### `headless.rs` — ヘッドレスモード

CI / テスト環境向けのヘッドレス実装。`[features] headless = []` で有効化。
winit ウィンドウを開かずに物理演算のみ実行できる。

### `renderer/mod.rs` — 描画パス

```mermaid
sequenceDiagram
    participant R as Renderer
    participant GPU as wgpu GPU
    participant E as egui

    R->>R: update_instances(RenderFrame)
    Note over R: SpriteInstance 配列を構築<br/>最大 14,502 エントリ
    R->>GPU: インスタンスバッファ更新
    R->>GPU: スプライトパス（render pass）
    R->>E: egui HUD 描画
    E->>GPU: egui パス
```

**スプライトアトラスレイアウト（1600×64px）:**

| オフセット | 内容 |
|:---|:---|
| 0〜255 | プレイヤー 4 フレームアニメ |
| 256〜511 | 敵アニメ（Slime/Bat/Golem） |
| 512〜767 | 静止スプライト（アイテム等） |
| 768〜1023 | ボス（SlimeKing/BatLord/StoneGolem） |

### `renderer/ui.rs` — egui HUD

| 画面 | 内容 |
|:---|:---|
| タイトル | START ボタン |
| ゲームオーバー | 生存時間・スコア・撃破数・RETRY ボタン |
| プレイ中 | HP バー・EXP バー・スコア・タイマー・武器スロット・Save/Load |
| ボス戦 | 画面上部中央にボス HP バー |
| レベルアップ | 武器カード×3、Esc/1/2/3 キー対応、3 秒自動選択 |

---

## ビルド設定（`Cargo.toml`）

```toml
[profile.dev]
opt-level = 1      # デバッグビルドでも最低限の最適化

[profile.release]
opt-level = 3
lto = true         # リンク時最適化
codegen-units = 1  # 最大最適化（ビルド時間増加）
```

---

## 関連ドキュメント

- [アーキテクチャ概要](./architecture-overview.md)
- [Elixir レイヤー詳細](./elixir-layer.md)
- [データフロー・通信](./data-flow.md)
- [ゲームコンテンツ詳細](./game-content.md)
