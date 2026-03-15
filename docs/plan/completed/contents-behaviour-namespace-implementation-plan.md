# Contents.Behaviour 名前空間 実施計画書（実施済み）

> 作成日: 2026-03-15  
> 完了日: 2026-03-15  
> 参照: [fix_contents.md](../../architecture/fix_contents.md), [scene-and-object.md](../../architecture/scene-and-object.md)  
> 目的: `apps/contents/lib` に **Behaviour** 名前空間を追加し、Content / Scene / Object / Component / Node の 5 種類の契約を `Contents.Behaviour.*` に集約する。コンテンツ作成時は Behaviour の修正は不要で、既存契約の実装のみ行う。

---

## 1. 概要

### 1.1 背景・方針

- **現状**: 各層の契約が `Contents.Scenes.Core.Behaviour` / `Contents.Nodes.Core.Behaviour` / `Contents.Objects.Core.Behaviour` / `Contents.Components.Core.Behaviour` および `Contents.Core.Behaviour`（憲法）として、層ごとのディレクトリに分散している。
- **目標**: 契約を「Contents が持つ 5 種類の Behaviour」として一つの名前空間に集約し、発見しやすく拡張パターンを揃える。
- **対象**: Content, Scene, Object, Component, Node の 5 種類のみ。これ以外の Behaviour は追加しない前提とする。
- **Content の契約**: `Core.ContentBehaviour` を **Contents.Behaviour.Content** として contents 側に移し、契約の「所有者」を Contents に統一する。core は**コンパイル時には contents に依存しない**。core は**実行時に** `Core.Config.current/0` で得た content モジュール（`Content.FormulaTest` 等。いずれも `Contents.Behaviour.Content` を実装）の関数（`initial_scenes/0`, `playing_scene/0` 等）を呼び出す。契約の定義は contents にあり、core は「その契約を実装したモジュール」を参照して使う、という関係になる。これにより **contents → core** の一方向依存を維持し、循環依存を避ける。core 内の `content_behaviour.ex` は削除する。

### 1.2 実施順序サマリ

1. **Phase 1**: `behaviour/` 配下に 6 モジュール（Contents.Behaviour, .Content, .Scenes, .Objects, .Nodes, .Components）を新規作成。.Content は `Core.ContentBehaviour` から移す。他は既存の各 `*/.Core.Behaviour` から移す。
2. **Phase 2**: `Contents.SceneBehaviour` の `use` 先を `Contents.Behaviour.Scenes` に変更。実装側の `@behaviour` / `@impl` を一括で新名前に更新。各 Content モジュール（Content.FormulaTest 等）の `@behaviour` を `Contents.Behaviour.Content` に変更。**core**: `apps/core/lib/core/content_behaviour.ex` を削除し、README 等の参照を更新。
3. **Phase 3**: ドキュメント・コメント内の参照を更新。旧ファイルを削除（一括切り替えの場合）。

### 1.3 目標構成

#### ディレクトリ構造（移行後）

```
apps/contents/lib/
  behaviour/                    # 新規追加
    behaviour.ex                # Contents.Behaviour（土台・憲法。型定義等）
    content.ex                  # Contents.Behaviour.Content（旧 Core.ContentBehaviour）
    scenes.ex                   # Contents.Behaviour.Scenes
    objects.ex                  # Contents.Behaviour.Objects
    nodes.ex                    # Contents.Behaviour.Nodes
    components.ex               # Contents.Behaviour.Components
  core/
    behaviour.ex                # 削除または Contents.Behaviour へ移行後に削除
  scenes/
    core/
      behaviour.ex              # 削除または後方互換エイリアスに
  nodes/
    core/
      behaviour.ex              # 削除または後方互換エイリアスに
  objects/
    core/
      behaviour.ex              # 削除または後方互換エイリアスに
  components/
    core/
      behaviour.ex              # 削除または後方互換エイリアスに
  contents/
    scene_behaviour.ex          # Contents.SceneBehaviour → use Contents.Behaviour.Scenes に変更
```

#### モジュール対応

| 移行元 | 移行先 |
|--------|--------|
| `Contents.Core.Behaviour` | `Contents.Behaviour` |
| `Contents.Scenes.Core.Behaviour` | `Contents.Behaviour.Scenes` |
| `Contents.SceneBehaviour` | 実装は変更せず、`use Contents.Behaviour.Scenes` に差し替え |
| `Contents.Objects.Core.Behaviour` | `Contents.Behaviour.Objects` |
| `Contents.Nodes.Core.Behaviour` | `Contents.Behaviour.Nodes` |
| `Contents.Components.Core.Behaviour` | `Contents.Behaviour.Components` |
| `Core.ContentBehaviour` | `Contents.Behaviour.Content`（契約を contents に移し、core は実行時に content モジュールを参照して呼び出す。core の `content_behaviour.ex` は削除） |

---

## 2. 実施手順

### Phase 1: 新ディレクトリとモジュールの作成

#### Step 1-1: ディレクトリ作成

```bash
mkdir -p apps/contents/lib/behaviour
```

#### Step 1-2: Contents.Behaviour（土台）の作成

- **新規ファイル**: `apps/contents/lib/behaviour/behaviour.ex`
- **モジュール名**: `Contents.Behaviour`
- **内容**: 現在の `Contents.Core.Behaviour` の内容を移す。  
  - 型定義（`@type process_id`, `world_ref`, `context`, `event`）  
  - `@moduledoc` で「憲法。全層が従う土台。Content / Scene / Object / Component / Node の契約は Contents.Behaviour.Scenes 等を参照」と記載。  
- **参照の更新**: 本文中で「各層の Behaviour（nodes/core, ...）」と書いている箇所を「Contents.Behaviour.Scenes, .Objects, .Nodes, .Components」に変更。

#### Step 1-2b: Contents.Behaviour.Content の作成（core から移行）

- **新規ファイル**: `apps/contents/lib/behaviour/content.ex`
- **モジュール名**: `Contents.Behaviour.Content`
- **内容**: 現在の `Core.ContentBehaviour`（`apps/core/lib/core/content_behaviour.ex`）の内容をそのままコピーする。
  - `@moduledoc` に「コンテンツモジュールが実装すべきビヘイビア。core は実行時に Config で渡された content モジュール（本 Behaviour を実装したモジュール）を参照して呼び出す。契約の定義は Contents が保持する。」と追記する。
  - `@callback` および `@optional_callbacks`、`@type` は変更しない。
- **core との関係**: core は本モジュールにコンパイル時依存しない。core の `Config.current/0` は `module()` を返し、GameEvents 等はそのモジュールの関数（`initial_scenes/0` 等）を呼び出す。実装側（Content.FormulaTest 等）は `@behaviour Contents.Behaviour.Content` とする。

#### Step 1-3: Contents.Behaviour.Scenes の作成

- **新規ファイル**: `apps/contents/lib/behaviour/scenes.ex`
- **モジュール名**: `Contents.Behaviour.Scenes`
- **内容**: 現在の `Contents.Scenes.Core.Behaviour` の内容をコピー。  
  - `@moduledoc` の「参照: scene-and-object.md」はそのまま。  
  - `defmacro __using__(_opts)` および `@callback init/1`, `update/2`, `render_type/0` は変更しない。  
- コールバックの `{:push, module(), ...}` / `{:replace, module(), ...}` は現仕様のまま（案B 移行時には scene_type に変更する想定）。

#### Step 1-4: Contents.Behaviour.Objects の作成

- **新規ファイル**: `apps/contents/lib/behaviour/objects.ex`
- **モジュール名**: `Contents.Behaviour.Objects`
- **内容**: 現在の `Contents.Objects.Core.Behaviour` の内容をコピー。  
  - `@moduledoc` 内の「`Contents.Core.Behaviour` の制約に従う」→「`Contents.Behaviour` の制約に従う」に変更。

#### Step 1-5: Contents.Behaviour.Nodes の作成

- **新規ファイル**: `apps/contents/lib/behaviour/nodes.ex`
- **モジュール名**: `Contents.Behaviour.Nodes`
- **内容**: 現在の `Contents.Nodes.Core.Behaviour` の内容をコピー。  
  - コールバック（`handle_pulse/2`, `handle_sample/2`）と `@optional_callbacks` はそのまま。

#### Step 1-6: Contents.Behaviour.Components の作成

- **新規ファイル**: `apps/contents/lib/behaviour/components.ex`
- **モジュール名**: `Contents.Behaviour.Components`
- **内容**: 現在の `Contents.Components.Core.Behaviour` の内容をコピー。  
  - `@moduledoc` 内の「`Contents.Core.Behaviour` の制約に従う」→「`Contents.Behaviour` の制約に従う」に変更。

---

### Phase 2: 後方互換エイリアスと SceneBehaviour の切替

#### Step 2-1: 後方互換の取り方（二択）

Elixir の `@behaviour` は「そのモジュールが定義する `@callback`」を実装側が満たすため、**旧モジュールを「新モジュールの use」だけに置き換えると、旧モジュールが @callback を何も持たず @impl が壊れる**。したがって次のいずれかとする。

- **A) 一括切り替え**: 旧モジュールファイルは削除せず、中身を「新モジュールを use するだけ」にはせず、**参照側を一括で新名前に更新**する（Phase 3 で全ファイルの `@behaviour` / `@impl` を `Contents.Behaviour.*` に変更）。その後、旧ファイルを削除する。
- **B) 段階移行**: 旧モジュールは**そのまま残す**（同じ @callback 定義を維持）。新モジュール（Contents.Behaviour.*）を追加し、新規コードとドキュメントでは新名前を参照する。旧名前は `@moduledoc` に「非推奨。代わりに `Contents.Behaviour.Scenes` を使用。」と記載。実装側の参照は後から順次 `Contents.Behaviour.*` に寄せ、参照がゼロになったら旧ファイルを削除する。

本計画では **A) 一括切り替え** を推奨とする（参照箇所は Phase 3 で一覧化して一括置換可能）。

#### Step 2-2: Contents.SceneBehaviour の切替

- **ファイル**: `apps/contents/lib/contents/scene_behaviour.ex`
- **変更**: `use Contents.Scenes.Core.Behaviour` を `use Contents.Behaviour.Scenes` に変更する。
- **前提**: Phase 1 で `Contents.Behaviour.Scenes` が同じ `__using__` と `@callback` を提供していること。これにより、既存の `@behaviour Contents.SceneBehaviour` をしているシーンはそのままで動作する。

#### Step 2-3: 実装側の @behaviour / @impl 参照を新名前に更新（一括）

- **Content**: 各コンテンツモジュール（`Content.FormulaTest`, `Content.VampireSurvivor`, `Content.CanvasTest` 等）の `@behaviour Core.ContentBehaviour` を `@behaviour Contents.Behaviour.Content` に一括置換。`@impl Core.ContentBehaviour` があれば `@impl Contents.Behaviour.Content` に。
- **Scenes**: `@behaviour Contents.SceneBehaviour` のままなら変更不要（SceneBehaviour が `Contents.Behaviour.Scenes` を use するため）。  
  `@behaviour Contents.Behaviour.Scenes` に統一する場合は、全シーンファイルの `@behaviour` / `@impl` を `Contents.Behaviour.Scenes` に変更。
- **Nodes**: ノード実装の `@behaviour Contents.Nodes.Core.Behaviour` → `@behaviour Contents.Behaviour.Nodes`、`@impl Contents.Nodes.Core.Behaviour` → `@impl Contents.Behaviour.Nodes` に一括置換。
- **Components**: UI 等の `@behaviour Contents.Components.Core.Behaviour` → `@behaviour Contents.Behaviour.Components`、同様に `@impl` を更新。
- **Objects**: `@behaviour Contents.Objects.Core.Behaviour` を実装しているモジュールがあれば、同様に `Contents.Behaviour.Objects` に更新。

参照箇所の一覧は Phase 3 で grep 等で確認する。

#### Step 2-4: core からの Content 契約の削除と参照の更新

- **削除**: `apps/core/lib/core/content_behaviour.ex` を削除する。
- **core 内の参照**: `Core.ContentBehaviour` を参照している箇所（README、コメント等）を更新する。
  - `apps/core/README.md`: 「ContentBehaviour」の説明を「コンテンツは `Contents.Behaviour.Content`（contents アプリで定義）を実装する。core は実行時に Config で渡された content モジュールを参照して呼び出す。」に変更。
- **型・spec**: core 内で `Core.ContentBehaviour` を型として使っている箇所があれば、`module()` または「content モジュール（Contents.Behaviour.Content を実装）」と doc で記載する。core は contents に依存しないため、型としては `module()` のままとする。

---

### Phase 3: 参照一覧の更新とドキュメント

#### Step 3-1: コード内参照の一括更新

- `Contents.Scenes.Core.Behaviour` → `Contents.Behaviour.Scenes`（または旧モジュールをエイリアスにした場合は変更不要）
- `Contents.Nodes.Core.Behaviour` → `Contents.Behaviour.Nodes`
- `Contents.Components.Core.Behaviour` → `Contents.Behaviour.Components`
- `Contents.Objects.Core.Behaviour` → `Contents.Behaviour.Objects`
- `Contents.Core.Behaviour` → `Contents.Behaviour`（doc 内や型参照のみの場合）

エイリアスを残す場合は、新規コードでは `Contents.Behaviour.*` を参照する方針とし、旧名は非推奨として doc に記載する。

#### Step 3-2: ドキュメントの更新

- `docs/architecture/fix_contents.md`  
  - `Contents.Scenes.Core.Behaviour` / `Contents.SceneBehaviour` の記述を `Contents.Behaviour.Scenes` に合わせる。  
- `docs/architecture/scene-and-object.md`  
  - 契約のモジュール名を `Contents.Behaviour.Scenes` に。  
- `docs/plan/completed/fix-contents-implementation-procedure.md`  
  - 参照用として「Behaviour は現在 Contents.Behaviour.* に集約済み」と追記。  
- その他、grep でヒットした `docs/` 内のファイルを必要に応じて更新。

#### Step 3-3: 旧ファイルの削除（任意・後日）

- 後方互換エイリアスを残す場合、`core/behaviour.ex` / `scenes/core/behaviour.ex` / `nodes/core/behaviour.ex` / `objects/core/behaviour.ex` / `components/core/behaviour.ex` は薄いラッパとして残す。
- すべての参照を `Contents.Behaviour.*` に移し終えたら、旧ファイルを削除し、旧モジュール名は `Contents.Behaviour` の doc に「旧名は XXX であった」と記載する。

---

## 3. 影響範囲の目安

- **新規作成**: 6 ファイル（`behaviour/behaviour.ex`, `content.ex`, `scenes.ex`, `objects.ex`, `nodes.ex`, `components.ex`）。
- **変更**: `contents/scene_behaviour.ex`（1 行）、旧 5 つの behaviour.ex（中身をエイリアスに変更または削除）、各 Content モジュール（FormulaTest, VampireSurvivor, CanvasTest 等）の `@behaviour` / `@impl`、ノード実装約 25 ファイル、コンポーネント実装約 15 ファイル、シーン実装約 20 ファイルの `@behaviour` / `@impl`、およびドキュメント複数。
- **core**: `apps/core/lib/core/content_behaviour.ex` を**削除**。`apps/core/README.md` 等の参照を更新。core は contents にコンパイル時依存を追加しない。
- **Core.Component**: 変更しない（エンジン↔コンポーネントの契約は core に残す）。

---

## 4. 検証

- `mix compile --warnings-as-errors` が通ること。
- 既存テストが通ること。
- 代表コンテンツ（FormulaTest, VampireSurvivor 等）の起動とシーン遷移が従来どおりであること。
- ノード・コンポーネントを利用している機能が従来どおり動作すること。

---

## 5. ロールバック

- 新規追加した `behaviour/*.ex` を削除し、旧 `*/core/behaviour.ex` および `scene_behaviour.ex` を元の内容に戻す。各 Content の `@behaviour` を `Core.ContentBehaviour` に戻す。**core**: `apps/core/lib/core/content_behaviour.ex` を復元する。参照を旧モジュール名に戻せばロールバック完了。

---

## 6. 参照

- [fix_contents.md](../../architecture/fix_contents.md) — アーキテクチャ概要
- [scene-and-object.md](../../architecture/scene-and-object.md) — Scene の責務
- [contents-migration-plan.md](../current/contents-migration-plan.md) — 既存コンテンツ移行
- [scene-type-as-atom-implementation-procedure.md](../current/scene-type-as-atom-implementation-procedure.md) — 案B 実施時は Contents.Behaviour.Scenes の利用を前提にできる
