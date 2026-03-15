# Contents.Scenes ファサード化 実施計画書

> 作成日: 2026-03-16  
> 目的: Content の `scene_init` / `scene_update` から、シーンモジュール直呼び出し（`Contents.Scenes.FormulaTest.Playing.init/1` 等）をやめ、**Contents.Scenes を入口とする呼び出し**に統一する。

---

## 1. 背景と目標

### 1.1 現状

`Content.FormulaTest` では、シーン処理を次のようにシーンモジュールへ直接委譲している。

```elixir
def scene_init(:playing, init_arg) do
  Contents.Scenes.FormulaTest.Playing.init(init_arg)
end

def scene_update(:playing, context, state) do
  Contents.Scenes.FormulaTest.Playing.update(context, state)
end
```

- 呼び出し元（Content）が `Contents.Scenes.*` の各モジュールを直接知っている。
- シーン追加・名前変更時に、そのシーンを参照する全 Content の修正が必要になる。

### 1.2 目標

**「すべて Contents.Scenes を入口にし、どのシーンかを atom で指定する」形にしたい。**

希望イメージ（意訳）:

- 現状: `Contents.Scenes.FormulaTest.Playing.init(init_arg)` / `Contents.Scenes.FormulaTest.Playing.update(context, state)`
- 目標: `Contents.Scenes` 経由で init/update を呼び、対象を **atom**（例: `:formula_test_playing`）で渡す。モジュール名への解決は `Contents.Scenes` 内のレジストリ（マップ）で行う。

**目標 API:**

```elixir
def scene_init(:playing, init_arg) do
  Contents.Scenes.init(:formula_test_playing, init_arg)
end

def scene_update(:playing, context, state) do
  Contents.Scenes.update(:formula_test_playing, context, state)
end
```

- 入口は常に `Contents.Scenes`。
- どのシーンかは第1引数（**シーン識別子 atom**）で指定する。
- `Contents.Scenes` 内に **シーン登録マップ**（atom → シーンモジュール）を持ち、`init` / `update` / `render_type` で atom をモジュールに解決してから既存の `init/1` / `update/2` 等に委譲する。

---

## 2. 変更範囲

| 項目 | 内容 |
|------|------|
| **新規** | `Contents.Scenes` モジュール（ファサード）。**シーン登録マップ**（atom → シーンモジュール）と、`init(scene_key, init_arg)` / `update(scene_key, context, state)` / 必要なら `render_type(scene_key)` を提供。内部で scene_key をモジュールに解決して委譲する。**ファイル**: 登録マップ用の1ファイル（例: `scenes.ex` または `scenes/contents_scenes.ex`）に加え、**`apps/contents/lib/scenes/init.ex`**（`init/2` 等）、**`apps/contents/lib/scenes/update.ex`**（`update/3`）を新規作成する。 |
| **変更** | 各 Content の `scene_init` / `scene_update`（および `scene_render_type` を委譲している箇所）で、シーン直呼び出しをやめ、`Contents.Scenes.init(atom, ...)` / `update(atom, ...)` 等を呼ぶ |
| **不変** | 既存のシーンモジュール（`Contents.Scenes.FormulaTest.Playing` 等）の `init/1` / `update/2` / `render_type/0` のシグネチャと Behaviour 契約 |

---

## 3. 実施手順

### Phase 1: Contents.Scenes ファサードの追加

#### Step 1-1: モジュールの配置とファイル作成

- **Contents.Scenes** は同一モジュールを複数ファイルに分けて定義する。以下のファイルを用意する。
  - **シーン登録マップ・解決用**: 既存の `scenes/` 配下の構成に合わせ、`apps/contents/lib/scenes.ex` に `defmodule Contents.Scenes` を置くか、`apps/contents/lib/scenes/contents_scenes.ex` のように「名前空間のトップ」用の1ファイルを置く。ここにシーン登録マップと `scene_module_for/1` を定義する。
  - **init 用**: **新規作成** `apps/contents/lib/scenes/init.ex` — `defmodule Contents.Scenes` の続きとして `init(scene_key, init_arg)` を定義する。
  - **update 用**: **新規作成** `apps/contents/lib/scenes/update.ex` — `defmodule Contents.Scenes` の続きとして `update(scene_key, context, state)` を定義する。
- 既存の `Contents.Scenes.Stack`（`scenes/stack.ex`）や `scenes/formula_test/playing.ex` 等はそのままサブモジュールとして残す。
- **目標ディレクトリ構造（追加分）:**

```
apps/contents/lib/
  scenes.ex                    # または contents_scenes.ex 等。登録マップ + scene_module_for
  scenes/
    init.ex                    # 新規。Contents.Scenes.init/2
    update.ex                  # 新規。Contents.Scenes.update/3
    core/
      behaviour.ex             # 既存
    formula_test/
      playing.ex               # 既存
    stack.ex                   # 既存
```

#### Step 1-2: シーン登録マップの定義

- **シーン識別子（atom）→ シーンモジュール** のマップを `Contents.Scenes` 内に持つ。
  - 例: `@scene_registry %{formula_test_playing: Contents.Scenes.FormulaTest.Playing}` のようにモジュール属性または `def scene_registry(), do: %{...}` で定義。
  - 命名規則の例: コンテンツ名とシーン名を `_` でつなぐ（`:formula_test_playing` → `Contents.Scenes.FormulaTest.Playing`）。新規シーン追加時はこのマップにエントリを足す。
- `scene_module_for(scene_key)` のような内部関数で、atom からモジュールを取得する。未登録の key の場合は `raise` または `{:error, :unknown_scene}` で扱う方針を決める。

#### Step 1-3: ファサード関数の定義

`Contents.SceneBehaviour` に合わせ、次の関数を用意する。第1引数は **シーン識別子（atom）** とする。**配置は `init.ex` / `update.ex` に分ける。**

- **`apps/contents/lib/scenes/init.ex`** に定義:
  - `init(scene_key, init_arg)`  
    - 実装: `scene_key` を登録マップでモジュールに解決し、`module.init(init_arg)` を呼んでその結果を返す。
  - （Content が `scene_render_type` で委譲している場合のみ）`render_type(scene_key)`  
    - 実装: `scene_key` をモジュールに解決し、`module.render_type()` を呼んでその結果を返す。`init.ex` にまとめてよい。
- **`apps/contents/lib/scenes/update.ex`** に定義:
  - `update(scene_key, context, state)`  
    - 実装: `scene_key` をモジュールに解決し、`module.update(context, state)` を呼んでその結果を返す。

各関数では、解決されたモジュールが `Contents.SceneBehaviour` を実装していることを前提とする。

#### Step 1-4: テスト・コンパイル

- `mix compile --warnings-as-errors` が通ること。
- 既存の FormulaTest 起動にまだ影響しない（呼び出し元はまだ直叩きのまま）。

---

### Phase 2: Content の呼び出しをファサード経由に変更

#### Step 2-1: Content.FormulaTest の変更

**ファイル:** `apps/contents/lib/contents/formula_test.ex`

| 箇所 | 変更前 | 変更後 |
|------|--------|--------|
| `scene_init(:playing, init_arg)` の本体 | `Contents.Scenes.FormulaTest.Playing.init(init_arg)` | `Contents.Scenes.init(:formula_test_playing, init_arg)` |
| `scene_update(:playing, context, state)` の本体 | `Contents.Scenes.FormulaTest.Playing.update(context, state)` | `Contents.Scenes.update(:formula_test_playing, context, state)` |

`scene_render_type(:playing)` がシーンモジュールの `render_type/0` を直接参照している場合は、同様に:

- 変更後: `Contents.Scenes.render_type(:formula_test_playing)`

#### Step 2-2: 他コンテンツの確認

- 他の Content で `Contents.Scenes.*` の `init` / `update` / `render_type` を直接呼んでいる箇所があれば、対応するシーン識別子 atom を登録マップに追加し、呼び出しを `Contents.Scenes.init(atom, ...)` / `update(atom, ...)` / `render_type(atom)` に置き換える。

#### Step 2-3: 検証

- `mix compile --warnings-as-errors`
- FormulaTest の起動・動作確認（HUD 表示、ESC / Quit）
- 他に変更した Content があれば同様に起動確認

---

### Phase 3: ドキュメント・コメントの更新（任意）

- `docs/architecture/formula-test-phase1-architecture.md` や、シーン呼び出し方針を説明しているドキュメントに、「シーン呼び出しは Contents.Scenes ファサード経由とする」旨を追記する。
- 本計画書を `docs/plan/completed/` へ移動するタイミングは、上記 Phase 1〜2 の完了後とする。

---

## 4. 補足

### 4.1 シーン識別子の命名規則

- 本計画では **最初から** シーン識別子を atom で渡し、`Contents.Scenes` 内の登録マップでモジュールに解決する。
- 命名の例: `Contents.Scenes.FormulaTest.Playing` → `:formula_test_playing`（コンテンツ名とシーン名を `_` で連結）。他コンテンツのシーンを追加する場合も同様の規則で atom を決め、登録マップに追加する。

### 4.2 案B（シーン種別＝atom）との関係

- 本計画は「現方式（シーン＝モジュール）」のまま、**呼び出し入口を Contents.Scenes に集約する**だけである。
- 案B（scene_type が atom、実装は Content の scene_*）を採用する場合は、Content が `content.scene_init(:playing, init_arg)` を実装するため、本ファサードの役割は変わる。その場合の整理は [scene-type-as-atom-implementation-procedure.md](./scene-type-as-atom-implementation-procedure.md) を参照。

---

## 5. 参照

- [formula-test-scene-migration-procedure.md](../completed/formula-test-scene-migration-procedure.md) — シーンを `scenes/formula_test/playing.ex` に移行した手順
- [Contents.SceneBehaviour](../../../apps/contents/lib/contents/scene_behaviour.ex) — シーン契約（init / update / render_type）
- [scene-type-as-atom-implementation-procedure.md](./scene-type-as-atom-implementation-procedure.md) — 案B の場合の手順
