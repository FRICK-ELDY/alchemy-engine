# Scene の origin・着地点・トップレベル子の実装計画

> 作成日: 2026-03-16  
> 参照: [scene-origin-and-landing-reference-plan.md](../2_todo/scene-origin-and-landing-reference-plan.md), [scene-and-object.md](../../docs/architecture/scene-and-object.md)  
> 目的: Scene の state 型と Stack で origin / 着地点参照 / トップレベル Object を扱えるようにし、FormulaTest.Playing を root_object から origin + landing_object + children に移行する。

---

## 1. 背景とスコープ

### 1.1 前提

- [scene-origin-and-landing-reference-plan.md](../2_todo/scene-origin-and-landing-reference-plan.md) の Phase 1〜3 は完了済み。ドキュメント上は「origin を Scene が持ち、着地点は参照のみ」に統一されている。
- 本計画は同計画書の **Phase 4（将来のコード変更）** を実施するための実施計画である。

### 1.2 スコープ

| 項目 | 内容 |
|------|------|
| **Scene state の型・規約** | origin（Transform）、任意の landing_object 参照、任意のトップレベル Object リスト（children）を state で扱えるようにする。推奨形を型またはモジュールで定義する。 |
| **Stack** | 現状は `%{scene_type, state: term()}` のまま。必要に応じて「現在シーンの origin / landing_object を取得する」ヘルパーを追加する。Stack 自体が state の形を強制しない方針は維持。 |
| **FormulaTest.Playing** | state から `root_object` / `child_object` を廃止し、`origin` + `landing_object` + トップレベル子のリスト（`children`）に置き換える。 |

### 1.3 用語（再掲）

- **origin**: Scene が持つ空間の原点（`Structs.Category.Space.Transform.t()`）。シーン座標系の基準。
- **landing_object**: ユーザーがシーンに降り立つ際のフォーカス対象となる Object への参照（`Contents.Objects.Core.Struct.t()` 等）。任意。
- **children（トップレベル Object リスト）**: Scene 直下の Object のリスト。親なし（`parent: nil`）の Object を Scene がリストで保持する形。「Scene ┣ user ┣ …」のようにインスペクターで直下に並べる想定。

---

## 2. 実施手順

### Phase 1: Scene state の推奨型・ヘルパーの整備

| タスク | 内容 |
|--------|------|
| **推奨 state の型定義** | `Contents.Scenes` または新規モジュール（例: `Contents.Scenes.State`）に、推奨される Scene state の形を `@type` で定義する。例: `@type recommended_state :: %{optional(:origin) => Transform.t(), optional(:landing_object) => Object.t(), optional(:children) => [Object.t()], ...}`。`term()` のままでも可で、ドキュメントと `@type` で「origin / landing_object / children を推奨」と明文化する。 |
| **origin デフォルト** | Scene で origin を持たない既存コンテンツとの互換のため、origin が未設定の場合は `Transform.new()` とみなす旨を doc に記載する。必要なら `Contents.Scenes` に `origin_from_state(state) :: Transform.t()` のようなヘルパーを追加する。 |

**成果物**: Scene state の推奨型（または doc のみ）、および必要に応じた `origin_from_state/1` 等のヘルパー。

---

### Phase 2: Stack の拡張（必要に応じて）

| タスク | 内容 |
|--------|------|
| **現状確認** | Stack は `scene_type` と `state`（term）のみ保持。state の構造は Content に委ねている。 |
| **変更方針** | Stack の既存 API（`get_scene_state/2`, `update_current/1` 等）はそのまま維持する。必要であれば、現在トップのシーン state から origin や landing_object を取得する API を追加する（例: `get_current_origin(server)` は `current(server)` で取得した state から `origin_from_state(state)` を返す）。必須ではなく、呼び出し元が `get_scene_state` で state を取得し自前で origin を参照してもよい。 |
| **実装** | 「Stack が origin / children を直接扱う」必要がなければ、Phase 2 は「Stack の @moduledoc に、scene state に origin / landing_object / children を持つ規約への参照を追記する」程度に留める。 |

**成果物**: Stack の doc 更新。必要に応じて `get_current_origin/1` 等の API 追加。

---

### Phase 3: FormulaTest.Playing の移行

| タスク | 内容 |
|--------|------|
| **init/1 の変更** | `root_object` を廃止する。代わりに: (1) `origin = Structs.Category.Space.Transform.new()`（または必要なら名前付きで保持）、(2) トップレベル Object を 1 つ作成（例: 名前 "User" または "Main"）、(3) その Object を `landing_object` とし、同じ Object の子として既存の `CreateEmptyChild.create(..., name: "Child")` で Child を作成。(4) state を `%{origin: origin, landing_object: top_object, children: [top_object], formula_results: results, hud_visible: true, cursor_grab_request: :no_change}` の形にする。`child_object` は、必要なら `landing_object` の子として state に持つか、または children の子孫として参照する形で扱う（現状 FormulaTest は child_object を state に持つが、RenderComponent は参照していないため、子は landing_object の子として作成するだけでよい）。 |
| **後方互換** | 他コンテンツは `get_scene_state` で formula_results / hud_visible / cursor_grab_request のみ参照しているため、これらを維持すれば FormulaTest.RenderComponent は変更不要。 |
| **検証** | `config :server, :current, Content.FormulaTest` で起動し、HUD 表示・Quit が従来通り動作すること。 |

**成果物**: `Content.FormulaTest.Playing` の state が `origin` + `landing_object` + `children` を持つ実装。`root_object` / `child_object` の削除。

---

### Phase 4: ドキュメント・Behaviour の整合

| タスク | 内容 |
|--------|------|
| **Contents.Behaviour.Content** | `scene_init/2` の @doc で「返却 state に root_object を含めることを推奨」を削除し、「origin および必要に応じて landing_object・children を持つことを推奨」に更新する。 |
| **scene-origin-and-landing-reference-plan.md** | Phase 4 の「本計画では実施しない」を「実施計画: scene-origin-landing-implementation-plan.md に委譲」に変更し、本実施計画書への参照を追加する。 |

**成果物**: Content behaviour の doc 更新、参照計画書の追記。

---

## 3. 依存関係と順序

```
Phase 1（Scene state 型・ヘルパー）
    → Phase 2（Stack の doc / 任意 API）
    → Phase 3（FormulaTest.Playing 移行）
    → Phase 4（doc 整合）
```

- Phase 2 は Phase 1 の「origin の扱い」が決まったうえで行う。Phase 2 をスキップし、Phase 3 のみ実施することも可。
- Phase 4 は Phase 3 完了後でよい。

---

## 4. リスクと注意

| リスク | 対策 |
|--------|------|
| 他コンテンツが scene state の `root_object` を参照している | 現状 grep では FormulaTest.Playing 以外は `root_object` を state から読んでいない。他コンテンツは移行対象外のため、root_object を残したまま許容する。 |
| Stack の state がファサード経由でラップされている | ファサード利用時は `%{scene_module: mod, inner_state: inner}`。`get_scene_state` はすでに unwrap して inner を返しているため、Phase 3 で FormulaTest の state を変更しても取得される state は新しい形になる。 |

---

## 5. 完了条件

- [x] Scene state の推奨型（または doc）と、必要に応じたヘルパー（例: `origin_from_state/1`）が定義されている
- [x] Stack の @moduledoc が、scene state に origin / landing_object / children を持つ規約を参照している（および必要なら get_current_origin 等の API が追加されている）
- [x] FormulaTest.Playing の state が `origin` + `landing_object` + `children` に移行され、`root_object` / `child_object` が削除されている
- [x] FormulaTest の起動と HUD 表示・Quit が従来通り動作する
- [x] Contents.Behaviour.Content の scene_init @doc が origin / landing_object / children 推奨に更新されている
- [x] scene-origin-and-landing-reference-plan.md の Phase 4 に本実施計画書への参照が追加されている

---

## 6. 参照一覧

| ドキュメント | 役割 |
|--------------|------|
| [scene-origin-and-landing-reference-plan.md](../2_todo/scene-origin-and-landing-reference-plan.md) | 方針と用語。Phase 4 で本計画に委譲。 |
| [scene-and-object.md](../../docs/architecture/scene-and-object.md) | Scene の責務と state 規約（origin・着地点参照）。 |
| [contents-migration-plan.md](../1_backlog/contents-migration-plan.md) | 既存コンテンツ移行の共通パターン。 |
