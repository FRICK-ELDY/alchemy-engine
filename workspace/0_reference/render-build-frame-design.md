# 描画フレーム組み立ての設計（Render / build_frame）

> 作成日: 2026-03-17  
> 目的: 「何を描くか」の定義と「実行」の責務分離、および Content.build_frame による描画統一の設計を参照用に残す。今後のスリム化（Playing 側ロジックの抽出・共通化など）の際の参照とする。

---

## 1. 現状の責務分離


| 責務            | 担当                | 説明                                                                                                                                          |
| ------------- | ----------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| **何を描くか（定義）** | Content / Playing | `Content.build_frame(playing_state, context)` で `{commands, camera, ui}` を組み立てる。値（カメラ・色・グリッド・HUD 等）の定義は contents 側（各 Content / Playing）に集約。 |
| **実行**        | Rendering.Render  | Content から `build_frame` で受け取ったタプルをエンコード・送信し、cursor_grab のリセットを行う。描画内容の知識は持たない。                                                             |


- **Content の build_frame**: `Contents.Behaviour.Content` のオプショナルコールバック。実装する Content（CanvasTest, FormulaTest）は `Playing.build_frame(playing_state, context)` に委譲する形。
- **Rendering.Render**: `function_exported?(content, :build_frame, 2)` で実装の有無を確認し、未実装の Content では描画をスキップする。

---

## 2. もともとの前提（スリム化前の整理用）

- 「描画に必要な値の定義は **Playing 側で行う**」前提で設計されていた（CanvasTest/FormulaTest の Playing に `@render_`* 定数と `render_defaults/0`、`build_frame/2` および `build_frame_*` 私有関数が集約）。
- 共有コンポーネント（Rendering.Render）が特定コンテンツを参照しないよう、**Content.build_frame** を介することで「定義は contents、実行は Render」の分離を実現した。

---

## 3. 今後のスリム化の際の参照

- **Playing 側**: `build_frame_commands` / `build_frame_camera` / `build_frame_ui` 等のロジックが CanvasTest.Playing と FormulaTest.Playing で重複しうる。スリム化時は共通部分の抽出（ヘルパー・ビヘイビア・共有モジュール）を検討する。
- **Content.build_frame**: 現状は「Content → Playing.build_frame に委譲」の 1 形。別コンテンツで「Content が直接組み立てる」「別モジュールに委譲する」などに拡張する場合は、本設計を前提にインターフェースを揃える。
- **Rendering.Render**: 役割は「build_frame の取得・エンコード・送信・cursor_grab リセット」に限定。スリム化で「何を描くか」の知識を Render に戻すことはしない（定義 vs 実行の分離を維持する）。

---

## 4. 関連

- 実装ルール: 定義 vs 実行の分離（Elixir = 定義、Rust = 定義に基づく実行）。Render は「実行」のみ。
- 計画: `workspace/7_done/rendering-unification-plan.md`（描画統一）と整合させる。

