# 描画スレッドオフロード計画

> `RedrawRequested` 処理中に入力の応答が鈍る問題への対応として、
> 描画処理を winit スレッドから分離する段階的な計画。

## 背景

現状、`native/input` の `desktop_loop` は winit イベントループ上で以下を同期的に実行している：

1. `bridge.next_frame()` … RenderFrame 取得・プレイヤー補間（GameWorld read）
2. `renderer.update_instances()` … CPU: DrawCommand → 頂点/インスタンス変換
3. `renderer.render()` … GPU: エンコード・submit・present
4. `window.request_redraw()`

この間、winit スレッドがブロックされるため、描画が重いと入力イベントの処理が遅れる。

**方針**: 専用スレッド（非同期ではない）で描画をオフロードし、winit スレッドはイベント処理と軽い送信に専念させる。

---

## フェーズ 1: 計測

### 目的

ボトルネックが `update_instances` か `render`（GPU）かを特定する。

### 作業

| 項目 | 内容 |
|:---|:---|
| **計測対象** | `update_instances` と `render` の各々の所要時間 |
| **計測方法** | `std::time::Instant` でラップし、ログ出力または内部カウンタで記録 |
| **出力先** | `log::debug!` または `lock_metrics` に準じる仕組み |
| **判定基準** | 片方が 1ms 超を安定して記録するか |

### 完了条件

- 各処理の 1 フレームあたりの所要時間が把握できている
- 主要ボトルネック（CPU vs GPU）が判明している

---

## フェーズ 2: update_instances のみオフロード

### 目的

負荷の多くが CPU 側なら、`update_instances` だけを worker スレッドに移して部分的な改善を得る。

### 設計

```
┌─────────────────────┐     channel      ┌──────────────────────┐
│  Winit スレッド     │ ────────────────→ │  Worker スレッド      │
│                     │   RenderFrame    │  (update_instances)   │
│  RedrawRequested    │ ←──────────────  │                      │
│  → フレーム送信     │   変換結果       │  変換後のデータを     │
│  → recv で受け取り  │                  │  メインへ返却         │
│  → render + present │                  │                      │
└─────────────────────┘                  └──────────────────────┘
```

### 作業

| 項目 | 内容 |
|:---|:---|
| **Worker スレッド** | `update_instances` 相当の処理を実行し、結果を channel で返す |
| **Winit スレッド** | フレーム送信 → `recv` で結果を受け取り → `render` + present を従来通り実行 |
| **注意点** | `Renderer` の状態（`&mut self`）はメインスレッドに残す。Worker は変換ロジックのみ、または一時バッファを返す |

### 利点・制約

- **利点**: 変更範囲が狭く、`Renderer` と Surface の所有関係を変えずに済む
- **制約**: GPU がボトルネックの場合は効果が小さい。`recv` でメインスレッドがブロックするため、Worker が遅いと結局ブロックする

### 完了条件

- `update_instances` 相当の処理が Worker スレッドで実行されている
- CPU ボトルネックが主な場合、入力応答の改善が観測できる

---

## フェーズ 3: 描画を完全に別スレッドへオフロード

### 目的

`update_instances` と `render`（GPU）の両方を winit スレッドから切り離し、イベントループをブロックしない。

### 設計

```
┌─────────────────────┐     channel      ┌──────────────────────┐
│  Winit スレッド     │ ────────────────→ │  描画スレッド         │
│  (input / UI)       │   RenderFrame    │  (update_instances +  │
│                     │ ←──────────────  │   render + present)   │
│  RedrawRequested    │ EventLoopProxy   │                      │
│  → フレーム送信のみ │  で「描画完了」  │  完了時に main へ     │
│  → ブロックしない   │  を通知         │  通知                 │
└─────────────────────┘                  └──────────────────────┘
```

### フロー

1. **Winit スレッド**（RedrawRequested）
   - `bridge.next_frame()` で RenderFrame 取得
   - RenderFrame を channel に送信
   - 即座に return（ブロックしない）

2. **描画スレッド**
   - channel から RenderFrame を受け取る
   - `update_instances` → `render` → present を実行
   - 終了時に `EventLoopProxy` でメインへ「描画完了」を送信

3. **Winit スレッド**（描画完了イベント受信）
   - `window.request_redraw()` を呼び、次フレームをスケジュール

### 技術的考慮

| 項目 | 内容 |
|:---|:---|
| **wgpu** | `Device` と `Queue` は Send。描画スレッドに移動可能。 |
| **Surface** | 描画スレッドに持たせる場合、プラットフォームによっては Surface 作成を描画スレッドで行う必要がある場合あり。 |
| **Window** | `!Send`。`request_redraw()` はメインスレッドから呼ぶ必要があるため、EventLoopProxy で描画完了を通知する。 |
| **フレームスキップ** | 描画が重いとき、未処理のフレームは「最新のみ残す」か FPS キャップで制御する。 |

### 作業

| 項目 | 内容 |
|:---|:---|
| **Renderer の所在** | 描画スレッドへ移動。Surface・Device・Queue は描画スレッドが所有。 |
| **Window の所在** | メインスレッドが保持。`request_redraw()` はメインから実行。 |
| **EventLoopProxy** | winit の `event_loop.create_proxy()` で取得し、描画スレッドに渡す。 |
| **bridge.next_frame()** | メインスレッドで呼び、RenderFrame を channel で描画スレッドへ渡す。 |

### 完了条件

- RedrawRequested ハンドラがフレーム送信のみ行い、描画完了までブロックしない
- 描画スレッドが update_instances → render → present を実行し、完了時に EventLoopProxy でメインへ通知する
- 入力応答の改善が観測できる

---

## マルチプラットフォーム展開（最終目標）

フェーズ 3 で確立する「RenderFrame を channel で渡す」境界は、Web / iOS / Android 対応の抽象化ポイントと一致する。各プラットフォームは同じ RenderFrame を受け取り、自身のループ駆動・入力・描画 API で表示する。

### アーキテクチャ概要

```
┌─────────────────────────────────────────────────────────────┐
│  共通コア（全プラットフォーム共通）                           │
│  - Physics スレッド (60Hz ゲームループ)                       │
│  - RenderFrame の生成 (Elixir ↔ NIF ↔ RenderFrameBuffer)     │
│  - DrawCommand / UiCanvas / CameraParams のデータ構造         │
└────────────────────────────┬────────────────────────────────┘
                             │ RenderFrame (channel / コールバック)
                             ▼
┌─────────────────────────────────────────────────────────────┐
│  プラットフォーム層（差し替え可能）                           │
│  ウィンドウ・入力取得・描画・present を実装                    │
└─────────────────────────────────────────────────────────────┘
```

### プラットフォーム別の担当

| プラットフォーム | ウィンドウ | 入力 | ループ駆動 | 描画 API |
|:---|:---|:---|:---|:---|
| Desktop | winit | キーボード・マウス | winit `run_app()` | wgpu (Vulkan/Metal/DX12) |
| Web | Canvas | DOM / Pointer / Gamepad | `requestAnimationFrame` | WebGL / WebGPU |
| iOS | UIView / Metal Layer | タッチ | CADisplayLink / RunLoop | Metal |
| Android | SurfaceView | タッチ・バックキー | Choreographer | Vulkan / OpenGL ES |

### 技術的注意点

- **描画 API**: wgpu は Web/ Metal / Vulkan をサポート。共通ロジックの多くを流用可能。
- **入力抽象化**: 各プラットフォームで取得した入力を共通の `InputEvent` に変換するレイヤーが必要。
- **Elixir/BEAM**: Web/iOS/Android 上での実行は Lumen 等の別途の検討事項。

---

## プラットフォーム層の配置

プラットフォーム層の crate 配置には次の2案がある。

### 案 A: native 配下に配置

```
native/
  desktop/    # 現状の input + render を統合
  web/
  ios/
  android/
  physics/    # 共通
  audio/      # 共通
  nif/        # 共通
```

- **利点**: 既存の `native/` 以下に揃えられる
- **懸念**: `native/` が肥大化する

### 案 B: platform 配下に分離（推奨）

```
platform/
  desktop/
  web/
  ios/
  android/

native/       # 共通コア
  physics/
  audio/
  nif/
  render/     # 共通の DrawCommand / RenderFrame / 描画パイプラインロジック
```

- **利点**: `native` は共通コアに、`platform` は各 OS 固有のウィンドウ・入力・present に専念し、責務が明確
- **利点**: `native/` の肥大化を抑えられる

### 方針

**案 B（`platform/` 配下）を採用する**。現状の `native/render` と `native/input` のデスクトップ部分は `platform/desktop` へ移行し、共通の描画ロジック（DrawCommand 変換など）は `native/render` に残すか `platform` 共通トレイトとして切り出す。

---

## まとめ

| フェーズ | 内容 | リスク |
|:---|:---|:---|
| 1 | 計測 | 低 |
| 2 | update_instances のみオフロード | 低〜中（Renderer の API 分割が必要な場合あり） |
| 3 | 描画完全オフロード | 中（Surface/Window のスレッド分離・プラットフォーム差異） |
| （将来） | platform/ 配下で Web/iOS/Android を追加 | 中（各プラットフォームの API 習熟） |

フェーズ 1 の結果を踏まえて、フェーズ 2 を実施するか、フェーズ 3 に直接進むかを判断する。フェーズ 3 完了後、`platform/desktop` への移行と `platform/web`, `platform/ios`, `platform/android` の追加を検討する。
