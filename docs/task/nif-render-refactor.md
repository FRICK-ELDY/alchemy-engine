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

### Phase R-6: シンプルな3Dゲームコンテンツの追加 ✅

**影響アプリ**: `game_content`

**実装内容:**

1. `apps/game_content/lib/game_content/simple_box_3d.ex` を作成
   - `components/0`・`initial_scenes/0`・`physics_scenes/0` 等のコンテンツ定義
   - `title/0` = `"Simple Box 3D"`、`assets_path/0` = `nil`（アトラス不要）
   - `wave_label/1` を実装（`Diagnostics` ログ用）
2. `apps/game_content/lib/game_content/simple_box_3d/scenes/playing.ex` を作成
   - Elixir 側でプレイヤー・敵の3D座標（x, y, z）を `state` として管理
   - `state.move_input` から WASD 入力を取得してプレイヤー移動（`InputComponent` 経由）
   - 敵はプレイヤーを追跡（速度 2.5 単位/秒）
   - 衝突判定でゲームオーバー遷移
3. `apps/game_content/lib/game_content/simple_box_3d/scenes/game_over.ex` を作成
   - `state.retry` フラグを検知して `{:transition, {:replace, Playing, %{}}}` でリスタート
4. `apps/game_content/lib/game_content/simple_box_3d/render_component.ex` を作成
   - `on_nif_sync/1` でシーン state から DrawCommand リストを組み立て
   - `{:skybox, top_color, bottom_color}` — 空色グラデーション
   - `{:grid_plane, size, divisions, color}` — XZ 平面グリッド地面（20×20）
   - `{:box_3d, x, y, z, hw, hh, {hd, r, g, b, a}}` — プレイヤー（青）・敵（赤）
   - `{:camera_3d, eye, target, up, {fov, near, far}}` — 斜め上から俯瞰カメラ
   - `SceneManager.current()` で現在シーンを判定して HUD `phase` を正しく設定
   - `push_render_frame/4` で RenderFrameBuffer に書き込み
5. `apps/game_content/lib/game_content/simple_box_3d/spawn_component.ex` を作成
   - `on_ready/1` で `set_world_size(world_ref, 2048.0, 2048.0)` を呼び出し
   - Rust 物理エンジンは使用しないが `map_size - PLAYER_SIZE` が負にならないよう十分大きな値が必要
6. `apps/game_content/lib/game_content/simple_box_3d/input_component.ex` を作成
   - `on_event({:move_input, dx, dy})` で `Playing` シーン state に `move_input` を書き込む
   - `on_event({:ui_action, "__retry__"})` で `GameOver` シーン state に `retry: true` を書き込む
7. `config/config.exs` に `GameContent.SimpleBox3D` のコメントを追加
   - `config :game_server, :current, GameContent.SimpleBox3D` に変更することで起動可能

**エンジン側の修正（副産物）:**

- `apps/game_engine/lib/game_engine/game_events.ex`
  - `handle_info({:move_input, dx, dy})` に `dispatch_event_to_components` を追加（入力をコンポーネントの `on_event` にも配信）
  - `handle_info({:ui_action, "__retry__"})` / `"__start__"` の専用節を削除し `_` 節に統合（`dispatch_event_to_components` が呼ばれるよう修正）
- `apps/game_engine/lib/game_engine/save_manager.ex`
  - `load_high_scores/0` のパターンマッチを `%{"state" => %{"scores" => scores}}` に修正（エンベロープ構造を正しく剥がす）

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

### Phase R-3: コンテンツ固有NIFをElixir側に吸収する ✅

### Phase R-5: 3Dレンダリングパイプラインの追加 ✅

**実装内容:**

1. `native/game_render/src/lib.rs` に3D用 `DrawCommand` バリアントを追加
   - `Box3D { x, y, z, half_w, half_h, half_d, color }` — 軸平行ボックス描画
   - `GridPlane { size, divisions, color }` — XZ 平面グリッドライン描画
   - `Skybox { top_color, bottom_color }` — 単色グラデーションスカイボックス描画
   - `CameraParams::Camera3D { eye, target, up, fov_deg, near, far }` — 3D カメラパラメータ
2. `native/game_render/src/renderer/shaders/mesh.wgsl` を新規作成 — MVP 行列 Uniform + 頂点カラーシェーダー
3. `native/game_render/src/renderer/pipeline_3d.rs` を新規作成
   - `Pipeline3D` 構造体：メッシュ・グリッド・スカイボックスの3パイプラインと深度テクスチャを保持
   - `MvpUniform`：ビュー行列・透視投影行列の合成（行列演算は外部クレート不使用）
   - `box_mesh()`：8頂点 × 6面 = 36インデックスのボックスメッシュ生成
   - `grid_lines()`：XZ 平面グリッドラインのラインリスト生成
   - `skybox_verts()`：クリップ空間直接指定のグラデーション矩形生成
   - `Pipeline3D::render()`：スカイボックス → グリッド → ボックスの順で描画
4. `native/game_render/src/renderer/mod.rs` を更新
   - `Renderer` の `device` / `queue` を `Arc` でラップ（`Pipeline3D` との共有のため）
   - `Renderer` に `pipeline_3d: Pipeline3D` フィールドを追加
   - `Renderer::resize()` で `pipeline_3d.resize()` を呼び出し深度テクスチャを再生成
   - `Renderer::render()` に `commands: &[DrawCommand]` 引数を追加し、`Camera3D` 時に3Dパスを実行
   - `sprite_instance_from_command()` に `Box3D / GridPlane / Skybox → None` アームを追加
5. `native/game_render/src/window.rs` を更新 — `render()` 呼び出しに `&frame.commands` を追加
6. `native/game_nif/src/nif/render_frame_nif.rs` を更新
   - `decode_command()` に `box_3d` / `grid_plane` / `skybox` タグのデコードを追加
   - `decode_camera()` に `camera_3d` タグのデコードを追加（`{:camera_3d, {ex,ey,ez}, {tx,ty,tz}, {ux,uy,uz}, {fov,near,far}}` 形式）
   - `decode_command()` に `grid_plane` の `color` フィールドを追加（`{:grid_plane, size, divisions, {r,g,b,a}}` 形式）

---

### Phase R-4: `render_bridge.rs` のゲーム固有設定を外部化する ✅

**実装内容:**

1. `native/game_nif/src/nif/render_nif.rs` の `start_render_thread` NIF に `title: String` / `atlas_path: String` 引数を追加
2. `native/game_nif/src/render_bridge.rs` の `run_render_thread` に同引数を追加し、`"AlchemyEngine - Vampire Survivor"` ハードコードを削除
   - アトラスのロードは `load_atlas_png(path)` 関数で行う（ファイル不在時は `AssetLoader` 埋め込みフォールバック）
   - Elixir 側はパス文字列のみを渡し、ファイルの実態（バイナリ）は持たない
3. `apps/game_engine/lib/game_engine/game_events.ex` に `build_window_title/1` / `resolve_atlas_path/1` ヘルパーを追加
   - `content.title/0` からウィンドウタイトルを組み立てる（`title/0` 未実装時は `"AlchemyEngine"` のみ）
   - `content.assets_path/0`（ゲーム別サブディレクトリ名）と `GAME_ASSETS_PATH` 環境変数からパスを解決する
4. `apps/game_engine/lib/game_engine/nif_bridge.ex` / `nif_bridge_behaviour.ex` / `game_engine.ex` のシグネチャを更新（引数 3→5）

**実装内容:**

1. `native/game_nif/src/nif/action_nif.rs` に汎用NIF追加:
   - `set_entity_velocity(world, entity_id, vx, vy)` — `:boss` エンティティの速度設定
   - `set_entity_flag(world, entity_id, flag, value)` — `:boss` の `:invincible` フラグ設定
   - `set_entity_hp(world, entity_id, hp)` — `:boss` または `{:enemy, index}` のHP設定
   - `spawn_projectile(world, x, y, vx, vy, damage, lifetime, kind)` — 汎用弾丸スポーン
2. `spawn_boss` → `spawn_special_entity` にリネーム（ボスという概念をNIF層から排除）
3. `spawn_elite_enemy` → `spawn_enemies_with_hp_multiplier` にリネーム（エリートという概念をNIF層から排除）
4. `set_boss_velocity` / `set_boss_invincible` / `set_boss_phase_timer` / `fire_boss_projectile` を廃止
5. `set_hud_state` / `set_hud_level_state` / `set_boss_hp` を廃止（`push_render_frame` のHudDataに統合済み）
6. `native/game_nif/src/lib.rs` に `:boss`, `:enemy`, `:invincible` アトムを追加
7. `native/game_nif/src/nif/read_nif.rs` の `get_render_entities` 戻り値に `magnet_timer`, `invincible_timer` を追加
8. `apps/game_content/lib/game_content/vampire_survivor/boss_component.ex` を汎用NIFを使うよう書き換え
   - `phase_timer` をElixir側プロセス辞書で管理（Rust NIF なし）
   - `fire_boss_projectile` → `spawn_projectile` に変更
9. `apps/game_content/lib/game_content/vampire_survivor/level_component.ex` から `set_hud_state` / `set_hud_level_state` の呼び出しを削除
10. `apps/game_content/lib/game_content/vampire_survivor/render_component.ex` を更新
    - `magnet_timer` / `invincible_timer` を `get_render_entities` から取得して `push_render_frame` に反映
    - `build_commands` の引数を9→4に削減（Credoの引数数制限に対応）
11. `apps/game_content/lib/game_content/vampire_survivor/scenes/boss_alert.ex` の `spawn_boss` → `spawn_special_entity` に変更
12. `apps/game_engine/lib/game_engine/game_events.ex` の `handle_info({:boss_dash_end, ...})` を汎用NIFに変更
13. `apps/game_engine/lib/game_engine/nif_bridge.ex` / `nif_bridge_behaviour.ex` の公開APIを整理

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

---

## 残課題

### 課題 E-1: `game_engine` 層への依存を排除する

Phase R-6 の実装中に、`game_content` だけでは完結できない問題が2件発生し、
暫定的に `game_engine` 層を修正した。これらは本来エンジンが汎用的に提供すべき
機能であり、設計として整理する必要がある。

#### E-1-1: `move_input` イベントがコンポーネントに届かない

**現状の問題:**

`GameEvents.handle_info({:move_input, dx, dy})` は Rust NIF を呼ぶだけで、
`dispatch_event_to_components` を呼んでいなかった。
Rust 物理エンジンを使わないコンテンツ（`SimpleBox3D`）では、
コンポーネントの `on_event` で移動入力を受け取る手段がなかった。

**暫定対処:**

`game_events.ex` の `handle_info({:move_input, dx, dy})` に
`dispatch_event_to_components({:move_input, dx, dy}, context)` を追加した。

**本来あるべき設計:**

`move_input` は Rust 物理エンジン専用の副作用（`set_player_input` NIF）と、
コンテンツへのイベント配信を分離すべき。
`on_event` への配信は常に行い、Rust NIF 呼び出しは `physics_scenes` に
いる場合のみ行う、という整理が望ましい。

#### E-1-2: `__retry__` / `__start__` UI アクションがコンポーネントに届かない

**現状の問題:**

`GameEvents.handle_info({:ui_action, action})` の `case` 文に
`"__retry__"` / `"__start__"` の専用節があり、`dispatch_event_to_components`
を呼ばずに `state` をそのまま返していた。
`VampireSurvivor` はこれらを `on_event` で処理していないため問題が顕在化して
いなかったが、`SimpleBox3D` の `InputComponent` が `__retry__` を受け取れなかった。

**暫定対処:**

`"__retry__"` / `"__start__"` の専用節を削除し、`_` 節（`dispatch_event_to_components`
を呼ぶ）に統合した。

**本来あるべき設計:**

UI アクションは原則すべてコンポーネントに配信すべき。
エンジンが特定のアクション文字列を知っている必要はなく、
`__save__` / `__load__` 等のエンジン固有アクションのみ専用節で処理し、
残りはすべて `dispatch_event_to_components` に渡す設計が正しい。

#### E-1-3: `SaveManager.load_high_scores/0` のバグ

**現状の問題:**

`load_high_scores/0` のパターンマッチが `%{"scores" => scores}` だったが、
`read_json` はエンベロープ全体 `%{"version" => ..., "state" => %{"scores" => ...}}`
を返すため、`CaseClauseError` でクラッシュしていた。
`VampireSurvivor` では `game_over` 遷移が発生しにくく顕在化していなかった。

**暫定対処:**

パターンマッチを `%{"state" => %{"scores" => scores}}` に修正した。

**本来あるべき設計:**

これは純粋なバグ修正であり、設計変更は不要。
ただし `save_manager.ex` のテストが存在しないため、
ハイスコアの保存・読み込みのユニットテストを追加することが望ましい。
