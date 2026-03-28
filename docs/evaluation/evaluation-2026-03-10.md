# AlchemyEngine — 総合評価レポート（2026-03-10）

> 評価日: 2026年3月10日  
> 評価対象: HEAD（main ブランチ相当）  
> 評価者: Cursor AI Agent  
> 評価ルール: `evaluation.mdc` に基づく

---

## エグゼクティブサマリー

AlchemyEngine は「Elixir（OTP）でゲームロジックを制御し、Rust（SoA/SIMD/wgpu）で演算・描画を処理する」というアーキテクチャを採用した個人製ゲームエンジンである。

**総合スコア: +161 / -82 = +79点**

全 8 クレート（shared, network, nif, render, audio, window, xr, app）のソースコードを直接読み、コードベースに基づく評価を行った。`native-restructure-migration-plan.md` 準拠の現行構成（physics は nif 内モジュール、desktop_render → render、desktop_input → window へリネーム済み）を反映している。

**mix alchemy.ci** はエラーゼロで通過することを確認済み。一方で、**shared の predict/store スケルトン**・**xr の OpenXR 未実装**・**network→render・render→nif のアーキテクチャ違反**・**nif の shared 非依存**が、native 層の設計上の課題として残っている。

---

## 検証実施状況

| 項目 | 結果 |
|:---|:---|
| `mix alchemy.ci` 全体 | **ALL PASSED**（exit 0） |
| コード直接確認 | **全 8 クレートのソースコードを読了**（下記参照） |

### コード直接確認の範囲

- **native/shared**: lib.rs, types.rs, interp.rs, predict.rs, store.rs
- **native/network**: lib.rs, common.rs, msgpack_decode.rs, network_render_bridge.rs, platform/desktop.rs, platform/web.rs, platform/mod.rs
- **native/nif**: lib.rs, load.rs, lock_metrics.rs, nif/mod.rs, physics/mod.rs, physics/constants.rs, physics/world/enemy.rs, physics/game_logic/chase_ai.rs, world_nif.rs 等
- **native/render**: lib.rs, headless.rs, renderer/mod.rs, window.rs, platform/mod.rs
- **native/audio**: lib.rs, audio.rs, asset/mod.rs, platform/mod.rs
- **native/window**: lib.rs, desktop_loop.rs, common.rs, platform/desktop.rs
- **native/xr**: lib.rs, common.rs, platform/desktop.rs
- **native/app**: lib.rs, main.rs, android.rs, ios.rs

---

## スコアサマリ

| カテゴリ | プラス | マイナス | 小計 |
|:---|:---:|:---:|:---:|
| **apps/core** | +18 | -8 | +10 |
| **apps/contents** | +18 | -11 | +7 |
| **apps/network** | +12 | -3 | +9 |
| **apps/server** | +3 | 0 | +3 |
| **native/shared** | +2 | -2 | 0 |
| **native/network** | +8 | -6 | +2 |
| **native/nif** | +35 | -2 | +33 |
| **native/render** | +11 | -10 | +1 |
| **native/audio** | +7 | 0 | +7 |
| **native/window** | +3 | -1 | +2 |
| **native/xr** | +1 | -3 | -2 |
| **native/app** | +4 | -2 | +2 |
| **横断（テスト・DX・可観測性・セキュリティ）** | +39 | -34 | +5 |
| **合計** | **+161** | **-82** | **+79** |

---

## native 各クレート評価

### native/shared

**責務**: Elixir との契約・型・補間・予測（The Mirror）

| 観点 | 評価 |
|:---|:---|
| **実装状況** | types（Vec2, ClientInfo, SnapshotHeader）、interp（lerp, lerp_vec2）は実装済み。predict・store はスケルトン |
| **プラス** | `#[repr(C)]` + Pod/Zeroable による Zero-Copy 設計。ClientInfo.current() による環境情報取得。interp の責務が明確 |
| **マイナス** | predict_input は入力をそのまま返すだけ。Store は `_placeholder` のみで未実装。nif が shared に依存しておらず、型の共有が未活用 |

### native/network

**責務**: Zenoh による Pub/Sub トランスポート（The Pipe）

| 観点 | 評価 |
|:---|:---|
| **実装状況** | desktop: ClientSession（Zenoh）、msgpack_decode（RenderFrame 等）、NetworkRenderBridge は完成。web: スケルトン（未実装エラー返却） |
| **プラス** | フレーム protobuf デコードが網羅的（DrawCommand, CameraParams, UiCanvas, MeshDef 等）。put_drop で CongestionControl::Drop。ClientInfo の発行 |
| **マイナス** | **render への依存**（目標: NETWORK → SHARED のみ）。RenderFrame/DrawCommand 等が render 由来で、ネットワーク層が描画層に結合されている |

### native/nif

**責務**: Elixir×Rust NIF ブリッジ・physics 統合

| 観点 | 評価 |
|:---|:---|
| **実装状況** | NIF 全カテゴリ、physics（SoA, SIMD, free_list, 空間ハッシュ, LCG）は実装済み。nif は shared に非依存 |
| **プラス** | 7 カテゴリ分類、ResourceArc、lock_metrics、DirtyCpu、SoA・free_list O(1)、SIMD/rayon/スカラー 3 段階、空間ハッシュ、決定論的 LCG |
| **マイナス** | create_world が NifResult 未対応。nif が shared を使わず独自型を保持（目標アーキテクチャとの乖離） |

### native/render

**責務**: wgpu による共通レンダラー（The Eye）

| 観点 | 評価 |
|:---|:---|
| **実装状況** | RenderFrame, DrawCommand, UiCanvas, インスタンス描画、headless、3D パイプラインは実装済み |
| **プラス** | wgpu インスタンス描画、ヘッドレス、RenderBridge トレイトによる窓層との分離 |
| **マイナス** | **nif への依存**（BG_R/G/B 定数のみのため、shared へ移すべき）。build_instances と headless の重複。Vertex/VERTICES 重複。Skeleton/Ghost UV プレースホルダー |

### native/audio

**責務**: コマンド駆動オーディオスレッド（SuperCollider 風）

| 観点 | 評価 |
|:---|:---|
| **実装状況** | mpsc コマンド、AssetLoader、AssetId、BGM/SE 再生、デバイス不在時の Option 返却は実装済み |
| **プラス** | コマンドパターン、define_assets! SSoT、platform 切り替え（desktop）、フォールバック設計 |
| **マイナス** | 特筆すべき欠如なし（評価観点の空間オーディオ・ボイスリミットは将来拡張） |

### native/window

**責務**: 窓層・winit によるイベント管理（The Shell）

| 観点 | 評価 |
|:---|:---|
| **実装状況** | desktop_loop、ApplicationHandler、RenderBridge 呼び出し、カーソルグラブは実装済み。common はスケルトン |
| **プラス** | イベントループ所有権が window にあり render と分離。RenderBridge トレイトによる抽象化 |
| **マイナス** | common（入力正規化）が「将来拡張」のコメントのみで未実装 |

### native/xr

**責務**: OpenXR セッション・入力管理（The Shell for VR）

| 観点 | 評価 |
|:---|:---|
| **実装状況** | XrInputEvent 型、run_xr_input_loop の骨格、Hand/ControllerButton は定義済み。OpenXR 本体は未実装 |
| **プラス** | イベント型設計が明確。openxr は optional で feature 化。platform/desktop, android の骨格あり |
| **マイナス** | run_openxr_loop が `Err("OpenXR integration not yet implemented")` を返すのみ。VR 入力は動作しない |

### native/app

**責務**: 統合層・デスクトップエントリ（VRAlchemy exe）

| 観点 | 評価 |
|:---|:---|
| **実装状況** | main.rs で NetworkRenderBridge + run_desktop_loop は完成。android.rs / ios.rs は「将来実装」のみ |
| **プラス** | 引数解析、GAME_ASSETS_PATH、Zenoh 接続、WindowConfig の組み立てが整理されている |
| **マイナス** | app が nif に依存（SCREEN_WIDTH/HEIGHT 取得のため。shared 経由にすべき）。android/ios が未実装 |

---

## 主なプラス点（全体）

1. **Elixir = SSoT / Rust = 実行層** の設計思想が vision.md と実装で一貫
2. **nif/physics** — SoA・SIMD・free_list・空間ハッシュ・決定論的 LCG
3. **ContentBehaviour / Component** のオプショナルコールバック
4. **mix alchemy.ci** によるローカル CI 整備とエラーゼロ通過
5. **network** — protobuf デコードと NetworkRenderBridge の完成度
6. **audio** — コマンドパターンと define_assets! SSoT

---

## 主なマイナス点（全体）

1. **network → render、render → nif のアーキテクチャ違反** — 目標依存関係（NETWORK→SHARED, RENDER→SHARED, NIF→SHARED）との乖離
2. **shared の predict/store 未実装** — レイテンシ対策・スナップショット管理がスケルトン
3. **xr の OpenXR 未実装** — VR 入力が動作しない
4. **nif の shared 非依存** — 型・定数の共有が未活用
5. **build_instances / Vertex 等の重複** — render 層の DRY 違反
6. **SceneStack・GameEvents のテスト欠如**（apps 側）

---

## 提案（0点）

- shared の predict/store 実装、BG_R/G/B を shared へ移行
- network/render の shared 経由リファクタ（目標アーキテクチャ達成）
- xr の OpenXR 実装
- 詳細は [specific-proposals.md](./specific-proposals.md) を参照

---

## 総括

総合スコア **+79**。全 8 クレートを直接確認し、**あるもの・ないもの**をコードベースで評価した。

**native の強み**は nif/physics の SoA・SIMD 設計と、network の protobuf/NetworkRenderBridge、audio のコマンド駆動である。**弱点**は shared の未完成、xr の未実装、歴史的なクレート依存の整理余地である。

引き続き、`native-restructure-migration-plan.md` の目標依存関係達成と、shared の predict/store 実装を推奨する。
