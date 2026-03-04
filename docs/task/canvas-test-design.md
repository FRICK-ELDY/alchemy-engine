# canvas_test コンテンツ設計書 — CanvasUI デバッグコンテンツ

> 作成日: 2026-03-02  
> 目的: CanvasUI（HUD・ワールドCanvas）の動作検証を目的としたデバッグ用3Dコンテンツを実装する。1人称視点の自由移動・ESCキーによるHUD開閉・ワールド空間内のCanvasパネルを通じて、UIシステムの各機能を網羅的に確認できる環境を構築する。

---

## 概要

| 項目 | 内容 |
|:---|:---|
| コンテンツ名 | `canvas_test` |
| モジュール名前空間 | `GameContent.CanvasTest` |
| 目的 | CanvasUI（HUD・ワールドCanvas）の動作確認 |
| 視点 | 1人称（FPS）カメラ |
| 物理エンジン | 使用しない（Elixir側で座標管理） |
| シーン構成 | `Playing` のみ（ゲームオーバーなし） |

---

## 背景と設計方針

### 検証したいCanvasUI機能

| 機能 | 検証内容 |
|:---|:---|
| HUD Canvas（スクリーン空間） | ESCキーで表示/非表示を切り替え |
| HUD内ボタン | ボタン押下でウィンドウを閉じる（`__quit__` アクション） |
| ワールドCanvas（3D空間内） | 3D座標に固定されたテキストパネルを複数配置 |
| レイアウト | `vertical_layout` / `horizontal_layout` / `rect` の組み合わせ |

### アーキテクチャ方針

- **Elixir = SSoT**：カメラ姿勢（位置・Yaw・Pitch）・HUD表示フラグをElixir側で管理する
- **Rust = 演算層**：描画・入力受信のみ担当。カメラ計算はElixir側で行う
- `simple_box_3d` および `bullet_hell_3d` の実装パターンを踏襲する
- 物理エンジン（physics）は使用しない

---

## ファイル構成

```
apps/contents/lib/contents/canvas_test/
├── canvas_test.ex              ← ContentBehaviour 実装（エントリポイント）
├── input_component.ex          ← 入力イベント処理（移動・マウス・ESC・UIアクション）
├── render_component.ex         ← DrawCommand・Camera・UiCanvas 組み立て
└── scenes/
    └── playing.ex              ← Playing シーン（ゲームロジック・状態管理）
```

---

## シーン設計

### Playing シーン（`GameContent.CanvasTest.Scenes.Playing`）

#### 状態（state）

| フィールド | 型 | 初期値 | 説明 |
|:---|:---|:---|:---|
| `pos` | `{float, float, float}` | `{0.0, 1.7, 0.0}` | カメラ位置（目線の高さ1.7） |
| `yaw` | `float` | `0.0` | 水平方向の視点角度（ラジアン） |
| `pitch` | `float` | `0.0` | 垂直方向の視点角度（ラジアン、±80°にクランプ） |
| `move_input` | `{float, float}` | `{0.0, 0.0}` | WASDの移動入力ベクトル（dx, dz） |
| `mouse_delta` | `{float, float}` | `{0.0, 0.0}` | 1フレームのマウス移動量（dx, dy） |
| `sprint` | `bool` | `false` | 左Shiftキー押下状態 |
| `hud_visible` | `bool` | `false` | HUD Canvasの表示フラグ |

#### 毎フレーム更新ロジック（`update/2`）

1. `mouse_delta` から `yaw` / `pitch` を更新する
2. `move_input` と `yaw` から移動方向ベクトルを計算し `pos` を更新する
3. `sprint` が `true` の場合は移動速度を2倍にする
4. `mouse_delta` を `{0.0, 0.0}` にリセットする（1フレーム消費）

#### 移動パラメータ

| パラメータ | 値 |
|:---|:---|
| 通常移動速度 | `5.0` 単位/秒 |
| スプリント速度 | `10.0` 単位/秒 |
| マウス感度 | `0.002` ラジアン/px |
| Pitchクランプ | `±(80° → 1.396 rad)` |
| フレームレート | `1/60` 秒 |

---

## 入力設計

### InputComponent（`GameContent.CanvasTest.InputComponent`）

Rustウィンドウから届くイベントをシーン state に反映する。

| イベント | 処理内容 |
|:---|:---|
| `{:move_input, dx, dz}` | `state.move_input` を更新（WASDの正規化ベクトル） |
| `{:mouse_delta, dx, dy}` | `state.mouse_delta` を更新（マウス移動量） |
| `{:sprint, true/false}` | `state.sprint` を更新（左Shiftキー） |
| `{:key_pressed, :escape}` | `state.hud_visible` をトグル |
| `{:ui_action, "__quit__"}` | `GameEngine.NifBridge` 経由でウィンドウを閉じる（`System.stop/0`） |

> **注意**: `{:mouse_delta, dx, dy}` および `{:sprint, bool}` イベントがRust側から届かない場合、Rust側への追加実装が必要になる可能性がある。既存イベントで代替できるか実装時に確認すること。

---

## 描画設計

### RenderComponent（`GameContent.CanvasTest.RenderComponent`）

毎フレーム `on_nif_sync/1` で以下を組み立てて `push_render_frame` に送る。

#### DrawCommand リスト

| コマンド | 内容 |
|:---|:---|
| `{:skybox, sky_top, sky_bottom}` | 空色グラデーション背景 |
| `{:grid_plane, 40.0, 40, grid_color}` | XZ平面グリッド（40×40、40分割） |
| `{:box_3d, ...}` × 数個 | ワールド内に配置した目印ボックス（白・灰色） |

#### カメラ（Camera3D）

1人称カメラをElixir側で計算して渡す。

```
eye    = state.pos
target = eye + forward_vec(yaw, pitch)
up     = {0.0, 1.0, 0.0}
fov    = 75.0°
near   = 0.1
far    = 200.0
```

`forward_vec(yaw, pitch)` の計算：

```
fx = cos(pitch) * sin(yaw)
fy = sin(pitch)
fz = cos(pitch) * (-cos(yaw))
```

#### UiCanvas

##### HUD Canvas（スクリーン空間）

`hud_visible` が `false` の場合は `{:canvas, []}` を送る。

`hud_visible` が `true` の場合：

```
画面中央に半透明パネル
├── タイトルテキスト: "DEBUG MENU"
├── セパレータ
├── 操作説明テキスト（WASD / Mouse / Shift / ESC）
├── セパレータ
└── [終了] ボタン（action: "__quit__"）
```

##### ワールドCanvas（3D空間内固定パネル）

`{:world_text, ...}` コンポーネントを使い、3D空間の複数座標にテキストを表示する。

| 座標（x, y, z） | 表示テキスト |
|:---|:---|
| `{5.0, 1.5, -5.0}` | `"Hello, World Canvas!"` |
| `{-5.0, 1.5, -5.0}` | `"CanvasUI Debug Panel\nThis is a world-space canvas."` |
| `{0.0, 1.5, -10.0}` | `"Alchemy Engine\nCanvas Test v0.1"` |
| `{8.0, 1.5, 0.0}` | `"[INFO]\nFPS: 60\nPos: (x, y, z)"` ※実際の座標を表示 |

> `world_text` は `lifetime` / `max_lifetime` を持つポップアップ型のため、毎フレーム再送することで常時表示を実現する。`lifetime` = `max_lifetime` = `9999` を指定する。

---

## コンテンツエントリポイント

### `GameContent.CanvasTest`（`ContentBehaviour` 実装）

```elixir
defmodule GameContent.CanvasTest do
  @behaviour GameEngine.ContentBehaviour

  def components, do: [
    GameContent.CanvasTest.InputComponent,
    GameContent.CanvasTest.RenderComponent,
  ]

  def initial_scenes, do: [
    {GameContent.CanvasTest.Scenes.Playing, %{}}
  ]

  def playing_scene,   do: GameContent.CanvasTest.Scenes.Playing
  def game_over_scene, do: Content.CanvasTest.Scenes.Playing  # ゲームオーバーなし
end
```

---

## 実装タスク一覧

| # | タスク | ファイル |
|:---|:---|:---|
| 1 | `Playing` シーン実装（状態管理・移動計算） | `scenes/playing.ex` |
| 2 | `InputComponent` 実装（イベント受信・state更新） | `input_component.ex` |
| 3 | `RenderComponent` 実装（DrawCommand・Camera・UI組み立て） | `render_component.ex` |
| 4 | `CanvasTest` エントリポイント実装 | `canvas_test.ex` |
| 5 | `Core.Config` へのコンテンツ登録確認 | `core/config.ex` |
| 6 | Rust側に `mouse_delta` / `sprint` イベントが未実装の場合は追加 | `native/render/` |

---

## 未解決事項・確認ポイント

| 項目 | 内容 |
|:---|:---|
| マウスデルタイベント | Rust側から `{:mouse_delta, dx, dy}` が既に送出されているか確認が必要 |
| スプリントイベント | `{:sprint, bool}` または左Shiftキーの検出方法をRust側で確認が必要 |
| `world_text` の常時表示 | `lifetime` / `max_lifetime` の大値指定で常時表示できるか動作確認が必要 |
| ウィンドウ終了 | `__quit__` アクション受信時の `System.stop/0` 呼び出しが正しく機能するか確認が必要 |
| カメラ計算 | Elixir側での三角関数計算（`:math.sin/cos`）のパフォーマンスは問題ないと想定するが、実装後に確認する |
