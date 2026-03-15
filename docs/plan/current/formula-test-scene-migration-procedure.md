# FormulaTest Playing シーン 新方式移行 実施手順書

> 作成日: 2026-03-15  
> 参照: [contents-migration-plan.md](./contents-migration-plan.md) Phase 1, [scene-and-object.md](../../architecture/scene-and-object.md), [scene-abstraction-and-engines.md](./scene-abstraction-and-engines.md)  
> 目的: `Content.FormulaTest.Scenes.Playing` を `apps/contents/lib/scenes` 配下の新方式（`Contents.Scenes.FormulaTest.Playing`）へ移行し、Phase 1 のシーン配置方針に合わせる。

---

## 案B（シーン種別＝atom）との関係

**本手順書は案Bには沿っていません。**

- **本手順の結果**: シーンは「**1コンテンツ1シーン種別 = 1モジュール**」（例: `Contents.Scenes.FormulaTest.Playing`）。SceneStack は従来どおり「シーンモジュール」をキーに init/update/render_type を呼ぶ。
- **案Bで実現したい形**: シーンは**種別（atom）**（`:playing`, `:title` 等）のみ。**実装はコンテンツ**が担い、`ContentBehaviour` に `scene_init(type, arg)` / `scene_update(type, ctx, state)` / `scene_render_type(type)` を追加。SceneStack は「(content, scene_type)」をキーに `content.scene_*(:playing, ...)` を呼ぶ。`Contents.Scenes.Playing` は概念（ラベル）としてのみ存在し、`Content.VampireSurvivor` が「:playing をこう実装する」を持つ。

案Bを採用する場合は、本手順の実施有無に関係なく、別途 **ContentBehaviour の拡張** と **SceneStack の変更** が必要です。案B向けの移行手順は [scene-type-as-atom-implementation-procedure.md](./scene-type-as-atom-implementation-procedure.md) を参照してください。本手順は「シーンを scenes 配下に集約する」現方式の整理であり、案B実施時には「既存のシーンモジュールをコンテンツの scene_* 実装へ委譲するラッパ」に変えるか、最初から案Bで FormulaTest を実装するかのどちらかになります。

---

## 1. 概要

### 1.1 背景

- **現状**: FormulaTest のプレイ中シーンは `apps/contents/lib/contents/formula_test/scenes/playing.ex` にあり、モジュール名は `Content.FormulaTest.Scenes.Playing`。
- **方針**: シーンは時間軸の契約として `apps/contents/lib/scenes` に集約する。コンテンツごとのシーンは `Contents.Scenes.<コンテンツ名>.<シーン名>` とする。
- **Phase 1 との関係**: contents-migration-plan の Phase 1（FormulaGraph → Contents.Nodes 置き換え）は既に playing.ex 内で完了済み。本手順は「シーンの配置先」を新方式に合わせる作業である。

### 1.2 移行の定義

| 項目 | 内容 |
|------|------|
| **移行元** | `Content.FormulaTest.Scenes.Playing`（`apps/contents/lib/contents/formula_test/scenes/playing.ex`） |
| **移行先** | `Contents.Scenes.FormulaTest.Playing`（`apps/contents/lib/scenes/formula_test/playing.ex`） |
| **Behaviour** | `Contents.SceneBehaviour` のまま（`Contents.Scenes.Core.Behaviour` を use した契約を維持） |
| **変更範囲** | ファイル配置・モジュール名・参照箇所の更新。ロジック（Nodes 実行・state 構造）は変更しない |

### 1.3 目標ディレクトリ構造（移行後）

```
apps/contents/lib/
  contents/
    formula_test/
      input_component.ex    # シーン参照を新モジュールに変更
      render_component.ex   # 同上
      formula_test.ex       # initial_scenes / playing_scene / game_over_scene を新モジュールに変更
      # scenes/ は削除（playing.ex を移出したため）
  scenes/
    core/
      behaviour.ex          # 既存
    formula_test/
      playing.ex            # Contents.Scenes.FormulaTest.Playing（新規・移行元から移動）
```

---

## 2. 実施手順

### Phase 1: 新シーンファイルの作成

#### Step 1-1: ディレクトリ作成

```bash
mkdir -p apps/contents/lib/scenes/formula_test
```

#### Step 1-2: 新シーンモジュールの作成

1. `apps/contents/lib/contents/formula_test/scenes/playing.ex` の内容をコピーする。
2. 新規作成: `apps/contents/lib/scenes/formula_test/playing.ex`
3. モジュール名を `Content.FormulaTest.Scenes.Playing` から `Contents.Scenes.FormulaTest.Playing` に変更する。
4. `@moduledoc` に「本シーンは `apps/contents/lib/scenes` 配下の新方式で配置されている」旨を追記（任意）。
5. `@behaviour Contents.SceneBehaviour` および `@impl Contents.SceneBehaviour` はそのまま維持（契約は同じ）。

**作成後のモジュール先頭の例:**

```elixir
defmodule Contents.Scenes.FormulaTest.Playing do
  @moduledoc """
  FormulaTest のプレイ中シーン。

  起動時に Contents.Nodes を用いて複数パターンの式を実行し、
  ノードアーキテクチャの動作を検証する。結果は state に格納し、RenderComponent で表示。

  Phase 1 移行: FormulaGraph を Contents.Nodes に置き換え。
  配置: apps/contents/lib/scenes（新方式）。
  """
  @behaviour Contents.SceneBehaviour
  # ... 以下、init/update/render_type および formula 検証は移行元と同一
```

---

### Phase 2: 参照の更新

#### Step 2-1: Content.FormulaTest の更新

**ファイル:** `apps/contents/lib/contents/formula_test.ex`

| 箇所 | 変更前 | 変更後 |
|------|--------|--------|
| `initial_scenes` の module | `Content.FormulaTest.Scenes.Playing` | `Contents.Scenes.FormulaTest.Playing` |
| `playing_scene/0` の返却値 | `Content.FormulaTest.Scenes.Playing` | `Contents.Scenes.FormulaTest.Playing` |
| `game_over_scene/0` の返却値 | `Content.FormulaTest.Scenes.Playing` | `Contents.Scenes.FormulaTest.Playing` |

#### Step 2-2: InputComponent の更新

**ファイル:** `apps/contents/lib/contents/formula_test/input_component.ex`

| 箇所 | 変更前 | 変更後 |
|------|--------|--------|
| `Contents.SceneStack.update_by_module` の第2引数 | `Content.FormulaTest.Scenes.Playing` | `Contents.Scenes.FormulaTest.Playing` |

#### Step 2-3: RenderComponent の更新

**ファイル:** `apps/contents/lib/contents/formula_test/render_component.ex`

| 箇所 | 変更前 | 変更後 |
|------|--------|--------|
| `Contents.SceneStack.get_scene_state(runner, content.playing_scene())` | （playing_scene の変更で自動的に新モジュールを参照） | 変更不要（content.playing_scene() をそのまま使用） |
| `Contents.SceneStack.update_by_module` の第2引数 | `Content.FormulaTest.Scenes.Playing` | `Contents.Scenes.FormulaTest.Playing` |

---

### Phase 3: 旧シーンの削除とクリーンアップ

#### Step 3-1: 旧ファイルの削除

- 削除: `apps/contents/lib/contents/formula_test/scenes/playing.ex`
- `apps/contents/lib/contents/formula_test/scenes/` に他ファイルが無ければ、ディレクトリ `scenes` も削除してよい（空の場合は `rmdir` または手動削除）。

#### Step 3-2: 他コンテンツ・ドキュメントでの言及確認（任意）

- コード内で `Content.FormulaTest.Scenes.Playing` を直接参照している箇所が他に無いことを確認する（本手順の Step 2 で一括更新済みの想定）。
- ドキュメント（`docs/architecture/formula-test-phase1-architecture.md` 等）でモジュール名を記載している場合は、`Contents.Scenes.FormulaTest.Playing` に合わせて更新する。

---

## 3. 検証

### 3.1 コンパイル

```bash
mix compile --warnings-as-errors
```

### 3.2 起動と動作確認

- `config :server, :current, Content.FormulaTest` で起動する。
- HUD に 5 パターン（add_inputs, constants, comparison, store シミュレート, multiple_outputs）の結果が表示されること。
- ESC で HUD 表示トグル、Quit で終了できること。

### 3.3 チェックリスト

- [ ] `mix compile --warnings-as-errors` が通る
- [ ] FormulaTest 起動で HUD が表示され、全パターン結果が表示される
- [ ] ESC / Quit が従来通り動作する
- [ ] 旧ファイル `contents/formula_test/scenes/playing.ex` が削除されている
- [ ] 依存方向: シーンは `Contents.Scenes.*` にあり、Content.FormulaTest はそのモジュールを参照するだけである

---

## 4. ロールバック

問題が発生した場合:

1. `apps/contents/lib/scenes/formula_test/playing.ex` を削除または無視する。
2. `apps/contents/lib/contents/formula_test/scenes/playing.ex` を復元する（モジュール名は `Content.FormulaTest.Scenes.Playing`）。
3. Phase 2 で変更した 3 ファイル（formula_test.ex, input_component.ex, render_component.ex）の参照を `Content.FormulaTest.Scenes.Playing` に戻す。

---

## 5. 参照

- [contents-migration-plan.md](./contents-migration-plan.md) — Phase 1 概要
- [scene-and-object.md](../../architecture/scene-and-object.md) — Scene の責務と root_object
- [scene-abstraction-and-engines.md](./scene-abstraction-and-engines.md) — 案B（シーン種別＝atom）の設計と他エンジン比較
- [Contents.SceneBehaviour](../../../apps/contents/lib/contents/scene_behaviour.ex) — シーン契約（Scenes.Core.Behaviour を use）
- [fix-contents-implementation-procedure.md](../completed/fix-contents-implementation-procedure.md) — 骨格実装手順
