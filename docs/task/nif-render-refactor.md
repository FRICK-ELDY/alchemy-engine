# NIF・レンダー層リファクタリング計画

> 作成日: 2026-03-01  
> 目的: NIF層のコンテンツ固有知識を排除し、2D/3D両対応の汎用描画パイプラインを実現する

---

## 背景

現状の `game_nif` / `game_render` 層は Vampire Survivor 専用の知識が染み出しており、
新しいゲームコンテンツ（特に3Dゲーム）を追加する際の障壁になっている。

本ドキュメントでは問題を整理し、汎用化のロードマップを定義する。
完了後に `game_content` へシンプルな3Dゲームを追加することが最終目標。

---

## 現状の問題

### 問題1: `render_snapshot.rs` がコンテンツ固有ロジックを持つ

`native/game_nif/src/render_snapshot.rs` は `GameWorldInner` の全フィールドを直接参照して
`RenderFrame` を組み立てる。武器スロット・ボス・スコアポップアップ・HUD等、
Vampire Survivor 固有の概念が `game_nif` 層に埋まっている。

```
# 現状の依存関係（問題）
GameWorldInner（Vampire Survivor専用）
  → render_snapshot.rs（game_nif層）
    → RenderFrame（Vampire Survivor専用フィールド）
      → game_render
```

### 問題2: NIF関数にコンテンツ固有の概念が露出している

以下のNIFはVampire Survivorのゲームルールを直接扱っており、汎用ブリッジとして機能していない。

| NIF関数 | 問題点 |
|:---|:---|
| `spawn_boss` | ボスという概念がNIF層に露出 |
| `set_boss_velocity` | ボスAI制御がNIF層に分散 |
| `set_boss_invincible` | 同上 |
| `set_boss_phase_timer` | 同上 |
| `fire_boss_projectile` | `BULLET_KIND_ROCK` がNIF層にハードコード |
| `set_hud_level_state` | レベルアップUIという概念がNIF層に |
| `set_hud_state` | score / kill_count という概念がNIF層に |
| `spawn_elite_enemy` | エリート敵という概念がNIF層に |

### 問題3: `RenderFrame` がコンテンツ固有の型になっている

```rust
// 現状: Vampire Survivor専用フィールドが並ぶ
pub struct RenderFrame {
    pub render_data: Vec<(f32, f32, u8, u8)>,                    // スプライト専用
    pub particle_data: Vec<(f32, f32, f32, f32, f32, f32, f32)>, // パーティクル専用
    pub item_data: Vec<(f32, f32, u8)>,                          // アイテム専用
    pub obstacle_data: Vec<(f32, f32, f32, u8)>,                 // 障害物専用
    pub camera_offset: (f32, f32),                               // 2Dオフセットのみ
    pub player_pos: (f32, f32),
    pub hud: HudData,
}
```

3Dゲームを追加しようとすると、このフレーム型に3D用フィールドを追加するか
別の型を作るかの二択になり、どちらも設計が崩れる。

### 問題4: `render_bridge.rs` にゲーム名・アセットがハードコード

```rust
// ウィンドウタイトルとアトラスが固定
title: "AlchemyEngine - Vampire Survivor".to_string(),
atlas_png: loader.load_sprite_atlas(),
```

---

## 目標アーキテクチャ

```
# 目標の依存関係
Elixir (game_content)
  → game_nif（薄いブリッジ: 汎用コマンドのみ）
  → DrawCommand列（2D/3D非依存の描画命令）
  → game_render（コマンドを解釈して描画）
```

`RenderFrame` を **DrawCommand の列**として再定義することが核心。
Elixir側（`game_content`）が描画命令を組み立てる責務を持ち、
`game_nif` はその命令を Rust に橋渡しするだけになる。

---

## 実装ロードマップ

### Phase R-1: `RenderFrame` を描画命令ベースに変える

**影響クレート**: `game_render`, `game_nif`

`RenderFrame` を `DrawCommand` の列として再定義する。

```rust
// game_render/src/lib.rs（案）
pub enum DrawCommand {
    // 2D系（既存機能の移植）
    Sprite { x: f32, y: f32, kind_id: u8, frame: u8 },
    Particle { x: f32, y: f32, r: f32, g: f32, b: f32, alpha: f32, size: f32 },
    Item { x: f32, y: f32, kind: u8 },
    Obstacle { x: f32, y: f32, radius: f32, kind: u8 },
    ScorePopup { x: f32, y: f32, value: u32 },
    // 3D系（将来追加）
    Box3D { x: f32, y: f32, z: f32, color: [f32; 4] },
    GridPlane { size: f32, divisions: u32 },
    Skybox { top_color: [f32; 4], bottom_color: [f32; 4] },
}

pub enum CameraParams {
    Camera2D { offset_x: f32, offset_y: f32 },
    Camera3D { eye: [f32; 3], target: [f32; 3], up: [f32; 3], fov_deg: f32 },
}

pub struct RenderFrame {
    pub commands: Vec<DrawCommand>,
    pub camera: CameraParams,
    pub hud: HudData,
}
```

**作業ステップ:**
1. `game_render/src/lib.rs` に `DrawCommand` / `CameraParams` enumを定義する
2. `Renderer::update_instances` が `Vec<DrawCommand>` を受け取るよう変更する
3. `game_nif/src/render_snapshot.rs` を `DrawCommand` を生成するよう書き換える
4. ヘッドレスレンダラー（`headless.rs`）も同様に対応する

---

### Phase R-2: `render_snapshot.rs` を `game_content` 側に移す

**影響クレート**: `game_nif`, `game_render`, `game_engine`

`GameWorldInner` → `RenderFrame` の変換ロジックはコンテンツ固有の知識であるため、
`game_nif` の外に出す。

新しいフロー:

```
Elixir (game_content)
  → push_render_frame NIF（DrawCommandリストを渡す）
    → RenderFrameBuffer（Rustスレッドセーフなバッファ）
      → RenderBridge::next_frame() がバッファから取得
        → game_render が描画
```

**作業ステップ:**
1. `game_nif` に `RenderFrameBuffer`（`Arc<RwLock<RenderFrame>>`）を追加する
2. `push_render_frame` NIFを追加し、Elixir側からDrawCommandリストを受け取れるようにする
3. `RenderBridge::next_frame()` が `GameWorldInner` を直接読む代わりに `RenderFrameBuffer` を参照するよう変更する
4. `render_snapshot.rs` を削除する
5. `game_engine` の `NifBridge` に `push_render_frame/1` コールバックを追加する
6. `game_content/vampire_survivor` がフレームごとに `DrawCommand` リストを組み立てて送るよう変更する

---

### Phase R-3: コンテンツ固有NIFをElixir側に吸収する

**影響クレート**: `game_nif`, `game_content`

以下のNIFを廃止し、汎用NIFまたはElixir側ロジックに置き換える。

| 廃止するNIF | 代替方針 |
|:---|:---|
| `spawn_boss` | `spawn_enemies_at` + Elixir側でボス管理 |
| `set_boss_velocity` | `set_entity_velocity(id, vx, vy)` に汎用化 |
| `set_boss_invincible` | `set_entity_flag(id, flag, value)` に汎用化 |
| `set_boss_phase_timer` | Elixir側タイマーで管理（NIFなし） |
| `fire_boss_projectile` | `spawn_projectile(x, y, vx, vy, damage, lifetime, kind)` に汎用化 |
| `set_hud_level_state` | `push_render_frame` のHudDataに統合 |
| `set_hud_state` | 同上 |
| `spawn_elite_enemy` | `spawn_enemies_at` + Elixir側でHP倍率適用後に `set_entity_hp` |

**作業ステップ:**
1. 汎用NIF（`set_entity_velocity`, `set_entity_flag`, `spawn_projectile`, `set_entity_hp`）を追加する
2. `game_content/vampire_survivor` の各コンポーネントを汎用NIFを使うよう書き換える
3. 廃止対象のNIFを削除する
4. `game_engine/nif_bridge.ex` の公開APIを整理する

---

### Phase R-4: `render_bridge.rs` のゲーム固有設定を外部化する

**影響クレート**: `game_nif`

`start_render_thread` NIFがウィンドウタイトルとアトラスPNGを引数として受け取れるようにする。

```rust
// 変更後
pub fn start_render_thread(
    world: ResourceArc<GameWorld>,
    pid: LocalPid,
    title: String,
    atlas_png: Vec<u8>,
) -> NifResult<Atom>
```

Elixir側（`game_content`）がアトラスパスとタイトルを指定する責務を持つ。

**作業ステップ:**
1. `start_render_thread` NIFのシグネチャを変更する
2. `render_bridge.rs` からハードコードされたタイトルとアトラスロードを削除する
3. `game_content/vampire_survivor.ex` でアトラスパスとタイトルを指定するよう変更する

---

### Phase R-5: 3Dレンダリングパイプラインの追加

**前提**: Phase R-1〜R-4 完了後に着手する

**影響クレート**: `game_render`

`DrawCommand::Box3D` / `GridPlane` / `Skybox` を実際に描画できるパイプラインを追加する。

必要な実装:
- 深度バッファ（`depth_stencil` 設定）
- 透視投影行列 + ビュー行列（`Camera3D` 対応）
- ボックスメッシュ（頂点バッファ: 8頂点 × 6面）
- グリッドライン描画パイプライン（ラインプリミティブ）
- スカイボックス（単色グラデーション or キューブマップ）
- 3D用シェーダー（`mesh.wgsl`）

**作業ステップ:**
1. `game_render` に `pipeline_3d` モジュールを追加する
2. 深度バッファ付きの `RenderPassDescriptor` を構成する
3. `mesh.wgsl` シェーダーを作成する（MVP行列 + 頂点カラー）
4. `Renderer::render` が `CameraParams::Camera3D` を受け取った場合に3Dパイプラインを使うよう分岐する
5. グリッドラインとスカイボックスのパイプラインを追加する

---

### Phase R-6: シンプルな3Dゲームコンテンツの追加

**前提**: Phase R-5 完了後に着手する

**影響アプリ**: `game_content`

`apps/game_content/lib/game_content/` に `SimpleBox3D` コンテンツを追加する。

仕様:
- 青いボックス = プレイヤー（WASD移動）
- 赤いボックス = 敵（プレイヤーを追跡）
- グリッド地面
- スカイボックス（空色グラデーション）
- 固定カメラ（斜め上から俯瞰）

**作業ステップ:**
1. `game_content/simple_box_3d.ex` を作成する（`WorldBehaviour` / `RuleBehaviour` 実装）
2. Elixir側で3D座標（x, y, z）を管理する `SimpleBox3DWorld` を定義する
3. フレームごとに `DrawCommand::Box3D` / `GridPlane` / `Skybox` を組み立てて `push_render_frame` に送る
4. `game_server` の設定から `SimpleBox3D` コンテンツを起動できるようにする

---

## 作業順序まとめ

```
R-1 RenderFrame を DrawCommand ベースに変える
  ↓
R-2 render_snapshot.rs を game_content 側に移す
  ↓
R-3 コンテンツ固有NIFをElixir側に吸収する
  ↓
R-4 render_bridge.rs のゲーム固有設定を外部化する
  ↓
R-5 3Dレンダリングパイプラインの追加
  ↓
R-6 シンプルな3Dゲームコンテンツの追加
```

R-1〜R-4 はリファクタリングであり、既存のVampire Survivorの動作を変えない。
R-5〜R-6 が新機能追加となる。

---

## 完了済みタスク

### Phase R-1: `RenderFrame` を描画命令ベースに変える ✅

### Phase R-2: `render_snapshot.rs` を `game_content` 側に移す ✅

**実装内容:**

1. `native/game_nif/src/render_frame_buffer.rs` を追加 — `Arc<RwLock<RenderFrame>>` を薄くラップした `RenderFrameBuffer` リソース
2. `native/game_nif/src/nif/render_frame_nif.rs` を追加 — `create_render_frame_buffer` / `push_render_frame` NIF
3. `native/game_nif/src/nif/read_nif.rs` に `get_render_entities` / `get_weapon_upgrade_descs` NIF を追加
4. `native/game_nif/src/render_bridge.rs` を変更 — `next_frame()` が `RenderFrameBuffer` を参照するよう変更。補間ロジックは `render_bridge.rs` 内に移動
5. `native/game_nif/src/render_snapshot.rs` を削除
6. `apps/game_engine/lib/game_engine/nif_bridge.ex` に新 NIF を追加
7. `apps/game_engine/lib/game_engine/game_events.ex` で `RenderFrameBuffer` を作成・保持し、`context.render_buf_ref` として各コンポーネントに渡す
8. `apps/game_content/lib/game_content/vampire_survivor/render_component.ex` を新規作成 — `on_nif_sync` で DrawCommand リストを組み立てて `push_render_frame` を呼ぶ
9. `VampireSurvivor.components/0` に `RenderComponent` を追加
