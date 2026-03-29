# Contents.Scenes ファサード化 実施計画書

> 作成日: 2026-03-16  
> 更新日: 2026-03-16（方針変更: scene_key 廃止、init_arg で定義を保持するデータ方式に統一）  
> 完了日: 2026-03-16（Phase 1〜2 実施・起動確認済み）  
> 目的: Content の `scene_init` / `scene_update` から、シーンモジュール直呼び出し（`Contents.Scenes.FormulaTest.Playing.init/1` 等）をやめ、**Contents.Scenes を入口とする呼び出し**に統一する。**「どのシーンか」の定義は Scenes は持たず、Content が init_arg（データ）で渡す。**

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

**「すべて Contents.Scenes を入口にし、シーン定義は Scenes が持たず、Content が init_arg で渡す」形にしたい。**

設計方針:

- **scene_key（atom）は使わない**。シーン識別子は廃止する。
- **init_arg が定義を持つ**。init_arg に `module` と `payload` を入れ、Content が「どのシーンか」をデータで指定する。Scenes は定義（登録マップ）を知らない。
- **データ方式**。プロトコル／Behaviour で型を縛らず、`%{module: mod, payload: ...}` の形で自由度を保つ。
- イメージ: 「Contents.Scenes.init するけど、コンテンツさん何か処理しますか？」→ Content が init_arg に module と payload を入れて渡すことで「このシーンで」と答える。

**目標 API:**

```elixir
# Content が init_arg を組み立てる（定義は Content 側）
def scene_init(:playing, raw_init_arg) do
  init_arg = %{
    module: Content.FormulaTest.Playing,
    payload: raw_init_arg
  }
  Contents.Scenes.init(init_arg)
end

def scene_update(:playing, context, state) do
  Contents.Scenes.update(context, state)
end
```

- 入口は常に `Contents.Scenes`。
- **init**: 引数は `init_arg` のみ。`init_arg` は `%{module: mod, payload: payload}` の形。Scenes は `mod.init(payload)` を呼び、返り値の state を `%{scene_module: mod, inner_state: state}` に包んで返す（update で同じモジュールに委譲するため）。
- **update**: 引数は `context` と `state` のみ。`state` に `scene_module` と `inner_state` が入っているので、Scenes は `state.scene_module.update(context, state.inner_state)` を呼び、返り値を同様に包んで返す。
- **render_type**: `state` から `scene_module` を取り、`state.scene_module.render_type()` を返す。API は `Contents.Scenes.render_type(state)` とする。

Scenes はシーン登録マップを持たず、atom による解決も行わない。定義はすべて呼び出し元（Content）が init_arg および state の形で持つ。

---

## 2. 変更範囲

| 項目 | 内容 |
|------|------|
| **新規** | `Contents.Scenes` モジュール（ファサード）。`init(init_arg)` / `update(context, state)` / `render_type(state)` を提供。init_arg から `module` と `payload` を取り `module.init(payload)` に委譲し、返り state を `%{scene_module: mod, inner_state: state}` で包む。update は state の `scene_module` と `inner_state` を使って委譲し、返りも同様に包む。**ファイル**: `apps/contents/lib/scenes.ex`（または `scenes/contents_scenes.ex`）に `defmodule Contents.Scenes` を置き、**`apps/contents/lib/scenes/init.ex`**（`init/1`）、**`apps/contents/lib/scenes/update.ex`**（`update/2`）、必要なら **`render_type.ex`** または init.ex に `render_type/1` を追加。 |
| **変更** | 各 Content の `scene_init` / `scene_update`（および `scene_render_type` を委譲している箇所）で、シーン直呼び出しをやめ、init_arg を `%{module: mod, payload: ...}` で組み立てて `Contents.Scenes.init(init_arg)` を呼ぶ。update は `Contents.Scenes.update(context, state)`。render_type は `Contents.Scenes.render_type(state)` に委譲する形にし、state を渡す。 |
| **不変** | 既存のシーンモジュール（`Content.FormulaTest.Playing` 等。Content 配下に配置）の `init/1` / `update/2` / `render_type/0` のシグネチャと Behaviour 契約。 |

---

## 3. 実施手順

### Phase 1: Contents.Scenes ファサードの追加

#### Step 1-1: モジュールの配置とファイル作成

- **Contents.Scenes** は同一モジュールを複数ファイルに分けて定義する。以下のファイルを用意する。
  - **トップ**: 既存の `scenes/` 配下の構成に合わせ、`apps/contents/lib/scenes.ex` に `defmodule Contents.Scenes` を置くか、`apps/contents/lib/scenes/contents_scenes.ex` のように名前空間トップ用の 1 ファイルを置く。**シーン登録マップは持たない。**
  - **init 用**: **新規作成** `apps/contents/lib/scenes/init.ex` — `defmodule Contents.Scenes` の続きとして `init(init_arg)` を定義する。
  - **update 用**: **新規作成** `apps/contents/lib/scenes/update.ex` — `defmodule Contents.Scenes` の続きとして `update(context, state)` を定義する。
  - **render_type**: `init.ex` にまとめてよい。`render_type(state)` を定義する。
- 既存の `Contents.Scenes.Stack`（`scenes/stack.ex`）はそのまま。シーン実装（例: Playing）は **Content 配下に置く**方針とする: `scenes/formula_test/playing.ex` を `contents/formula_test/playing.ex` に移し、モジュール名を `Content.FormulaTest.Playing` にリネームする。
- **目標ディレクトリ構造（追加・移行後）:**

```
apps/contents/lib/
  scenes.ex                    # または contents_scenes.ex。登録マップはなし
  scenes/
    init.ex                    # 新規。Contents.Scenes.init/1, render_type/1
    update.ex                  # 新規。Contents.Scenes.update/2
    core/
      behaviour.ex             # 既存
    stack.ex                   # 既存
  contents/
    formula_test.ex            # 既存。Content.FormulaTest
    formula_test/
      playing.ex               # 移行。Content.FormulaTest.Playing（旧 Contents.Scenes.FormulaTest.Playing）
```

#### Step 1-2: init_arg の契約（データ形）

- **init_arg** は次の形を前提とする（データで持つ方式。プロトコルは使わない）。
  - `%{module: mod, payload: payload}` または `%{module: mod, payload: payload, ...}`
  - `mod`: シーンモジュール（`Contents.SceneBehaviour` を実装していること）。
  - `payload`: そのシーンの `init/1` に渡す引数。
- Scenes は「init_arg から module と payload を取り、module.init(payload) を呼ぶ」だけとする。未定義のキーや不正な形は実行時エラーまたはガードで弾く方針を決める。

#### Step 1-3: ファサード関数の定義

- **`apps/contents/lib/scenes/init.ex`** に定義:
  - `init(init_arg)`
    - `mod = init_arg.module`, `payload = init_arg.payload` を取り、`mod.init(payload)` を呼ぶ。
    - 返りが `{:ok, state}` のとき、`{:ok, %{scene_module: mod, inner_state: state}}` を返す。それ以外（例: `{:error, _}`）はそのまま返す。
  - `render_type(state)`
    - `state` が `%{scene_module: mod, inner_state: _}` の形であることを前提に、`mod.render_type()` を返す。
- **`apps/contents/lib/scenes/update.ex`** に定義:
  - `update(context, state)`
    - `state` を `%{scene_module: mod, inner_state: inner}` とみなし、`mod.update(context, inner)` を呼ぶ。
    - 返りが `{:continue, new_inner}` のとき、`{:continue, %{scene_module: mod, inner_state: new_inner}}` を返す。その他（例: `{:push, _, _}` 等）も同様に `inner_state` 部分だけ差し替えて包み直して返す。

各関数では、`module` が `Contents.SceneBehaviour` を実装していることを前提とする。

#### Step 1-4: テスト・コンパイル

- `mix compile --warnings-as-errors` が通ること。
- 既存の FormulaTest 起動にまだ影響しない（呼び出し元はまだ直叩きのまま）。

---

### Phase 2: Content の呼び出しをファサード経由に変更

#### Step 2-1: Content.FormulaTest の変更

**ファイル:** `apps/contents/lib/contents/formula_test.ex`

| 箇所 | 変更前 | 変更後 |
|------|--------|--------|
| `scene_init(:playing, init_arg)` の本体 | `Content.FormulaTest.Playing.init(init_arg)`（移行後） | `init_arg` を `%{module: Content.FormulaTest.Playing, payload: init_arg}` に組み立て、`Contents.Scenes.init(init_arg)` を呼ぶ（変数名の衝突に注意。例: `scene_init_arg = %{module: ..., payload: init_arg}; Contents.Scenes.init(scene_init_arg)`）。 |
| `scene_update(:playing, context, state)` の本体 | `Content.FormulaTest.Playing.update(context, state)`（移行後） | `Contents.Scenes.update(context, state)` |
| `scene_render_type(:playing)` | `Content.FormulaTest.Playing.render_type()`（移行後） | 呼び出し元が **state を保持している**前提で、`Contents.Scenes.render_type(state)` に委譲する。Stack 等で state を渡せるようにする必要があれば、その呼び出し箇所もあわせて変更する。 |

`scene_render_type` について: 現在はシーン種別（`:playing`）だけを引数にしているため、**render_type を取得する側が「現在の state」を渡せる**形にしないといけない。Stack や Game ループが state を持っているなら、`Contents.Scenes.render_type(state)` を呼ぶようにする。呼び出し元が state を持っていない場合は、設計上のすり合わせ（例: 現在シーンの state をどこで保持するか）が必要。

**render_type の入口統一（方針）**: 現時点では Stack が state を渡さないため、FormulaTest は `scene_render_type(:playing)` で `Content.FormulaTest.Playing.render_type()` を直接呼ぶ形とした（init/update はファサード経由・render_type は非ファサード）。**いずれ Stack が state を渡す API に変えたら、Content は `Contents.Scenes.render_type(state)` に委譲する形に寄せる想定**。それまでは「render_type は Content 経由のまま、Scenes ファサードは init/update のみ」で進める。

#### Step 2-2: 他コンテンツの確認

- 他の Content で `Contents.Scenes.*` の `init` / `update` / `render_type` を直接呼んでいる箇所があれば、同様に init_arg を `%{module: mod, payload: ...}` で組み立てて `Contents.Scenes.init/1` を呼ぶ形、および `Contents.Scenes.update/2` / `Contents.Scenes.render_type/1` に置き換える。

#### Step 2-3: 検証

- `mix compile --warnings-as-errors`
- FormulaTest の起動・動作確認（HUD 表示、ESC / Quit）
- 他に変更した Content があれば同様に起動確認

---

### Phase 3: ドキュメント・コメントの更新（任意）

- `workspace/7_done/formula-test-phase1-architecture.md` や、シーン呼び出し方針を説明しているドキュメントに、「シーン呼び出しは Contents.Scenes ファサード経由とし、シーン定義は Content が init_arg（module + payload）で渡す」旨を追記する。
- 本計画書を `workspace/7_done/` へ移動するタイミングは、上記 Phase 1〜2 の完了後とする。

---

## 4. 補足

### 4.1 init_arg の形と自由度

- シーン識別子（atom）は使わない。**定義は init_arg のデータ**（`module` と `payload`）で行う。
- Content が「どのシーンか」を自由に決められる。新規コンテンツ・新規シーン追加時も、Scenes の登録マップをいじる必要はなく、Content 側で init_arg を組み立てるだけでよい。

### 4.2 state のラップ（scene_module / inner_state）

- init の返り state を `%{scene_module: mod, inner_state: state}` で包む理由は、**update 時に同じモジュールに委譲するため**。Scenes は「どのシーンか」の定義を持たないので、state に `scene_module` を持たせて update で使う。
- 既存シーンモジュールの `init/1` / `update/2` の返り値はそのまま。ラップ／アンラップは Scenes ファサード内だけで行う。

### 4.3 案B（シーン種別＝atom）との関係

- 本計画は「現方式（シーン＝モジュール）」のまま、**呼び出し入口を Contents.Scenes に集約し、定義は init_arg で渡す**形にする。
- 案B（scene_type が atom、実装は Content の scene_*）を採用する場合は、Content が `content.scene_init(:playing, init_arg)` を実装するため、本ファサードの役割は変わる。その場合の整理は [scene-type-as-atom-implementation-procedure.md](./scene-type-as-atom-implementation-procedure.md) を参照。

---

## 5. 参照

- [formula-test-scene-migration-procedure.md](./formula-test-scene-migration-procedure.md) — シーンを `scenes/formula_test/playing.ex` に移行した手順
- [Contents.SceneBehaviour](../../../apps/contents/lib/contents/scene_behaviour.ex) — シーン契約（init / update / render_type）
- [scene-type-as-atom-implementation-procedure.md](./scene-type-as-atom-implementation-procedure.md) — 案B の場合の手順
