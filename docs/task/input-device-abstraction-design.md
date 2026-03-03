# デバイス入力抽象化設計書 — Elixir 主導の入力レイヤー

> 作成日: 2026-03-03  
> 目的: デバイス入力を game_render から分離し、Elixir を SSoT として意味論的イベントを扱う設計を定義する。VR・トラッカー等の特殊デバイスも同一の抽象で扱えるようにする。

---

## 概要

| 項目 | 内容 |
|:---|:---|
| 設計対象 | デバイス入力（キーボード・マウス・VR・トラッカー） |
| 方針 | 抽象イベントとして Elixir で扱う |
| 責務分離 | Rust = 生イベント取得・転送 / Elixir = 意味づけ・状態更新 |

---

## 背景と課題

### 現状の問題

- `game_render`（`window.rs`）がキーマッピング（WASD→move_input、Shift→sprint 等）を担っている
- 実装ルール上、`game_render` の責務は「描画パイプライン・HUD」であり、ゲームロジックを持たない
- キー→意味のマッピングはゲーム的意味づけであり、Elixir 側が持つべき知識

### 設計原則（implementation.mdc より）

- **Elixir = SSoT**：ゲームロジックの制御フロー・シーン管理・パラメータは Elixir 側で持つ
- **Rust = 演算層**：物理演算・描画・オーディオは Rust 側で処理

---

## 設計方針

### 基本方針：意味論的イベントとして扱う

Elixir は「どのデバイスか」ではなく「何のデータか」を把握する。デバイス種別（ローカルキーボード、ネットワーク、VR 等）はタグとして付与し、コンテンツが必要なものだけを選択して処理する。

### 責務の切り分け

| 責務 | 配置 | 内容 |
|:---|:---|:---|
| OS イベント受信 | Rust（薄い NIF 層） | winit / OpenXR 等から生イベント取得 |
| 生イベント転送 | Rust → Elixir | `{:raw_key, ...}` や `{:head_pose, ...}` を送信 |
| キー→意味のマッピング | Elixir | WASD→move_input、Shift→sprint 等 |
| 移動ベクトル計算 | Elixir | 押下状態から (dx, dy) を算出 |
| 状態更新・ディスパッチ | Elixir | GameEvents → コンポーネント |

---

## イベント形式

### デスクトップ入力（現行との互換）

| イベント | ペイロード | 説明 |
|:---|:---|:---|
| `{:move_input, dx, dy}` | `{float, float}` | 移動入力ベクトル（WASD 等から算出） |
| `{:mouse_delta, dx, dy}` | `{float, float}` | マウス移動量 |
| `{:sprint, pressed}` | `boolean` | スプリント押下状態 |
| `{:key_pressed, key}` | `atom` | 特定キー押下（ESC 等） |

### 生イベント転送（将来の Elixir 主導マッピング用）

| イベント | ペイロード | 説明 |
|:---|:---|:---|
| `{:raw_key, key, state}` | `{atom, :pressed \| :released}` | キー押下/解放 |
| `{:raw_mouse_motion, dx, dy}` | `{float, float}` | マウス移動量（生） |

### VR デバイス

| イベント | ペイロード | 説明 |
|:---|:---|:---|
| `{:head_pose, data}` | `%{position: {x,y,z}, orientation: {qx,qy,qz,qw}, timestamp: us}` | ヘッドセットの位置・姿勢 |
| `{:controller_pose, data}` | `%{hand: :left \| :right, position: {...}, orientation: {...}, timestamp: us}` | コントローラーの位置・姿勢 |
| `{:controller_button, data}` | `%{hand: :left \| :right, button: atom, pressed: boolean}` | コントローラーボタン |
| `{:hand_pose, data}` | `%{hand: :left \| :right, joints: [...], ...}` | ハンドトラッキング（オプション） |

### トラッカー

| イベント | ペイロード | 説明 |
|:---|:---|:---|
| `{:tracker_pose, data}` | `%{tracker_id: non_neg_integer, position: {...}, orientation: {...}, velocity: {...}, timestamp: us}` | トラッカーの位置・姿勢 |

### デバイス種別タグ（オプション）

複数デバイスを混在させる場合、タグで区別する。

```elixir
{:input, :desktop, {:move_input, dx, dy}}
{:input, :vr_head, {:head_pose, %{...}}}
{:input, :vr_controller, {:controller_pose, %{hand: :left, ...}}}
{:input, :tracker, {:tracker_pose, %{tracker_id: 0, ...}}}
{:input, :network, {:move_input, dx, dy}}
```

---

## データ形式の規約

### 位置・姿勢

| 項目 | 単位・形式 | 備考 |
|:---|:---|:---|
| `position` | `{x, y, z}` メートル | OpenXR 等で正規化 |
| `orientation` | `{qx, qy, qz, qw}` クォータニオン | 正規化済み |
| `velocity` | `{vx, vy, vz}` メートル/秒 | 利用可能な場合のみ |
| `timestamp` | マイクロ秒 | フレーム同期用 |

### Elixir が把握するもの / しないもの

| 把握する | 把握しない |
|:---|:---|
| 意味（ヘッドの向き、左手コントローラー等） | 具体的デバイス名（Quest 2、Index 等） |
| 正規化された単位・形式 | センサー方式・トラッキング技術 |
| 識別子（:left, :right, tracker_id） | OpenXR 内部 API |

---

## レイヤー構成

```
┌─────────────────────────────────────────────────────────────┐
│ Elixir                                                      │
│  GameEvents ← イベント受信・ディスパッチ                     │
│  InputHandler / コンポーネント ← キーマッピング・状態更新   │
└─────────────────────────────────────────────────────────────┘
                              ▲
                              │ NIF (send_and_clear)
                              │
┌─────────────────────────────────────────────────────────────┐
│ Rust                                                        │
│  game_input ← イベントループ・ウィンドウ・生イベント取得     │
│  game_nif   ← RenderBridge 実装・Elixir 送信                │
│  game_render ← 描画パイプライン・HUD（描画専用）             │
│  winit (デスクトップ) / OpenXR (VR)                         │
└─────────────────────────────────────────────────────────────┘
```

---

## 実装フェーズ案

### Phase 1: デスクトップ入力の責務分離

1. `window.rs` からキーマッピング・移動ベクトル計算を削除
2. 生イベント `{:raw_key, key, state}` を Elixir に転送
3. Elixir の `InputHandler` 等でキー→意味のマッピングを実装
4. `{:move_input}`, `{:mouse_delta}`, `{:sprint}` を Elixir 側で生成

### Phase 2: イベントループの分離

1. イベントループの所有権を `game_render` から `game_nif` または新規 `game_input` へ移行
2. `game_render` は描画専用に

### Phase 3: VR・トラッカー対応（将来）

1. OpenXR ブリッジを Rust に追加
2. `{:head_pose}`, `{:controller_pose}`, `{:tracker_pose}` を Elixir に送信
3. コンポーネントで VR 専用ロジックを実装

---

## 実装状況

| フェーズ | 状態 | 備考 |
|:---|:---|:---|
| Phase 1: デスクトップ入力の責務分離 | ✅ 完了 | window.rs からキーマッピング削除、raw_key 転送、InputHandler でマッピング |
| Phase 2: イベントループの分離 | ✅ 完了 | game_input にイベントループ移行、game_render は描画専用 |
| Phase 3: VR・トラッカー対応 | ✅ 基盤完了 | イベントフロー・Elixir 受信完了。OpenXR 実装は TODO |

### 実装ファイル

- `native/game_input/` — イベントループ・ウィンドウ・入力取得（winit）
- `native/game_render/src/window.rs` — RenderBridge トレイト・型定義のみ（描画専用）
- `native/game_nif/src/render_bridge.rs` — Elixir への raw_key 送信、game_input 経由で起動
- `native/game_nif/src/key_map.rs` — KeyCode → アトム名マッピング
- `native/game_nif/src/xr_bridge.rs` — XR イベントの Elixir エンコード・送信（`xr` フィーチャー時）
- `native/game_input_openxr/` — OpenXR 用クレート。`run_xr_input_loop` の骨格実装済み
- `apps/game_engine/lib/game_engine/game_events.ex` — raw / VR イベント受信・転送
- `apps/game_engine/lib/game_engine/input_handler.ex` — キー→意味のマッピング

### Phase 3 の有効化

VR 入力を有効にするには、game_nif を `--features xr` でビルドする:

```bash
cd native && cargo build -p game_nif --features xr
```

Elixir から `NifBridge.spawn_xr_input_thread(self())` を呼ぶと XR 入力スレッドが起動する。
OpenXR ランタイム（SteamVR 等）が未導入の場合はログ出力のみで即座に終了する。

---

## 関連ドキュメント

- [実装ルール](../../.cursor/rules/implementation.mdc) — レイヤー責務・アーキテクチャ原則
- [データフロー](../data-flow.md) — ユーザー入力フロー
- [canvas_test 設計](./canvas-test-design.md) — 入力コンポーネントの利用例
