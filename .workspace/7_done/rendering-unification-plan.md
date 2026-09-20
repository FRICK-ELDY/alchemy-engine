# 描画コンポーネント共通化 実施計画書

> 作成日: 2026-03-17  
> 目的: Rendering.Render と Rendering.FormulaRender を単一の「実行」コンポーネントに統合し、**定義は contents**・**実行は components/category/rendering** に分離する。

---

## 1. 概要

### 1.1 現状の課題

| ファイル | 役割 | 問題 |
|:---|:---|:---|
| `components/category/rendering/render.ex` | CanvasTest 用。Playing の render_defaults を参照し、コマンド・カメラ・UI を組み立てて送信 | コンテンツごとにレンダーが増えると重複・分散する |
| `components/category/rendering/formula_render.ex` | FormulaTest 用。上記と同様に FormulaTest.Playing を参照 | 上記とほぼ同じ「取得→組み立て→エンコード→送信」の流れが二重化している |

レンダーが二つあると、実行パスが分かれ保守性が下がる。**「何を描くか」の定義**と**「フレーム取得・エンコード・送信」の実行**を分離し、実行は単一コンポーネントにまとめる。

### 1.2 方針

| 役割 | 配置 | 責務 |
|:---|:---|:---|
| **定義** | `apps/contents/lib/contents` | 現在の Content の playing state と context から **commands / camera / ui** を組み立てる。各コンテンツ（またはその Playing）が「何を描くか」を決める。 |
| **実行** | `apps/contents/lib/components/category/rendering` | **単一モジュール**が、現在 Content から frame データを取得し、protobuf エンコード（`FrameEncoder`）・FrameBroadcaster 送信・cursor_grab リセットまでを行う。 |

- **定義**: 各 Content がオプショナルコールバック `build_frame(playing_state, context)` を実装し、`{commands, camera, ui}` を返す。実装は Content モジュールにまとめてもよいし、Playing に `build_frame/2` を置き Content が委譲してもよい。
- **実行**: `Contents.Components.Category.Rendering.Render` のみ残す。`on_nif_sync` で playing_state を取得 → `content.build_frame(state, context)` を呼ぶ → 返り値を `encode_frame` して `FrameBroadcaster.put` → cursor_grab のリセット処理。`build_frame` 未実装の Content の場合は描画しない（no-op またはスキップ）。

---

## 2. 設計

### 2.1 Content 側（定義）

- **オプショナルコールバック**: `build_frame(playing_state, context) :: {commands, camera, ui}`
  - `playing_state`: 現在の playing シーンの state（`Contents.Scenes.Stack.get_scene_state` の返り値）
  - `context`: `on_nif_sync` に渡される context（`room_id`, `tick_ms` 等）
  - 戻り値: `{commands, camera, ui}` — いずれも `Content.FrameEncoder.encode_frame/5` に渡す形式

- **実装場所**
  - **Content.CanvasTest**: `build_frame/2` を実装。内部で `Content.CanvasTest.Playing.render_defaults/0` を参照し、現行 `Rendering.Render` の `build_commands` / `build_camera` / `build_ui` に相当する処理を行う。実装は `Content.CanvasTest` に持つか、`Content.CanvasTest.Playing.build_frame/2` に持って Content が委譲するかは任意。
  - **Content.FormulaTest**: 同様に `build_frame/2` を実装。`Content.FormulaTest.Playing.render_defaults/0` と現行 `Rendering.FormulaRender` の組み立てロジックを contents 側に移す。

- **cursor_grab_request**: state に含まれる。リセット処理は**実行**側（Rendering.Render）で従来どおり行う（送信後に `update_by_scene_type` で `:no_change` に戻す）。

### 2.2 Rendering 側（実行）

- **単一モジュール**: `Contents.Components.Category.Rendering.Render`
  - `on_nif_sync(context)` の流れ:
    1. `content = Core.Config.current()`
    2. `runner = content.flow_runner(:main)`
    3. `playing_state = get_scene_state(runner, content.playing_scene())`（無い場合は `%{}`）
    4. `function_exported?(content, :build_frame, 2)` が false なら `:ok` で終了（描画スキップ）
    5. `{commands, camera, ui} = content.build_frame(playing_state, context)`
    6. `frame_binary = Content.FrameEncoder.encode_frame(commands, camera, ui, mesh_definitions, cursor_grab)`
    7. `Contents.FrameBroadcaster.put(context.room_id, frame_binary)`
    8. `cursor_grab_request` が `:no_change` でなければ、従来どおり state を更新してリセット

- **削除**: `Contents.Components.Category.Rendering.FormulaRender` モジュールおよび `formula_render.ex` ファイル。FormulaTest の描画は Content.FormulaTest（または Playing）の `build_frame/2` に集約する。

---

## 3. 実施手順

### Phase 1: Content ビヘイビアと定義の追加

#### Step 1-1: オプショナルコールバックの追加

- **ファイル**: `apps/contents/lib/behaviour/content.ex`
- **追加**: オプショナルコールバック `build_frame(playing_state, context) :: {commands, camera, ui}` の @doc と @callback、および `@optional_callbacks` に `build_frame: 2` を追加。
- **意味**: 本コンポーネントで描画を行う Content が実装する。未実装の Content では Render が描画をスキップする。

#### Step 1-2: CanvasTest に build_frame/2 を実装（定義を contents に移す）

- **ファイル**: `apps/contents/lib/contents/canvas_test.ex` または `apps/contents/lib/contents/canvas_test/playing.ex`
- **方針**: 現在 `Rendering.Render` が持つ `build_commands` / `build_camera` / `build_ui` / `hud_layout_nodes` 等のロジックを、**contents 側**に移す。
  - 案 A: `Content.CanvasTest.Playing` に `build_frame(state, context)` を追加し、`Content.CanvasTest.build_frame(state, context)` は `Content.CanvasTest.Playing.build_frame(state, context)` を呼ぶ。
  - 案 B: `Content.CanvasTest` に `build_frame(state, context)` とそのための private 関数をまとめて実装し、`Playing.render_defaults/0` はそのまま参照する。
- **戻り値**: `{commands, camera, ui}`。形式は現行 `Render` の `build_commands` / `build_camera` / `build_ui` の返り値と同じにする。

#### Step 1-3: FormulaTest に build_frame/2 を実装（定義を contents に移す）

- **ファイル**: `apps/contents/lib/contents/formula_test.ex` または `apps/contents/lib/contents/formula_test/playing.ex`
- **方針**: 現在 `Rendering.FormulaRender` が持つ `build_commands` / `build_camera` / `build_ui` / `format_results` 等のロジックを、**contents 側**に移す。
- **戻り値**: 同様に `{commands, camera, ui}`。

---

### Phase 2: 実行側の単一コンポーネント化

#### Step 2-1: Rendering.Render の書き換え

- **ファイル**: `apps/contents/lib/components/category/rendering/render.ex`
- **変更内容**:
  - `on_nif_sync(context)` を「content の `build_frame(state, context)` を呼び、その返り値を encode → put する」形に変更する。
  - コンテンツ固有の `build_commands` / `build_camera` / `build_ui` / `hud_*` 等は**すべて削除**する。
  - cursor_grab のリセット処理は残す（playing_state から `cursor_grab_request` を読み、送信後に `update_by_scene_type` で `:no_change` に戻す）。
- **依存**: Content が `build_frame/2` を実装している前提。未実装の場合は `function_exported?` で分岐し、何も送信せず `:ok` で返す。

#### Step 2-2: FormulaRender の削除と components の統一

- **削除**: `apps/contents/lib/components/category/rendering/formula_render.ex`
- **Content.CanvasTest.components/0**: 現状のまま `Contents.Components.Category.Rendering.Render` を含める。
- **Content.FormulaTest.components/0**: `Contents.Components.Category.Rendering.FormulaRender` を外し、`Contents.Components.Category.Rendering.Render` に差し替える。

---

## 4. 移行後の構成

```
apps/contents/lib/
  contents/
    canvas_test.ex              # build_frame/2 で CanvasTest 用 frame を定義（または Playing に委譲）
    canvas_test/
      playing.ex                 # render_defaults/0。必要なら build_frame/2。
    formula_test.ex              # build_frame/2 で FormulaTest 用 frame を定義（または Playing に委譲）
    formula_test/
      playing.ex                 # render_defaults/0。必要なら build_frame/2。
  components/
    category/
      rendering/
        render.ex                # 単一の「実行」コンポーネント。build_frame 取得 → encode → put → cursor_grab リセット
      device/
        ...
      procedural/
        ...
      shader/
        ...
```

- **定義**: 各 Content（または Playing）の `build_frame(playing_state, context)` が「何を描くか」を決める。
- **実行**: `Rendering.Render` が「取得・エンコード・送信・cursor_grab リセット」のみを担当する。

---

## 5. 検証

- `mix compile` が通ること。
- `config :server, :current, Content.CanvasTest` で起動し、従来どおり描画・HUD・Quit が動作すること。
- `config :server, :current, Content.FormulaTest` で起動し、従来どおり公式検証結果の HUD・Quit が動作すること。
- 両コンテンツで同一の `Contents.Components.Category.Rendering.Render` が使われていることを確認すること。

---

## 6. 参照

- [canvas-test-playing-and-components-relocation-plan.md](./canvas-test-playing-and-components-relocation-plan.md) — 定義を Playing に集約する方針
- [contents-components-reorganization-procedure.md](../2_todo/contents-components-reorganization-procedure.md) — コンポーネント再配置の手順
