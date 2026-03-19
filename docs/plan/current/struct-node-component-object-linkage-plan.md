# Struct → Node → Component → Object 紐づきの実施計画

> 作成日: 2026-03-19  
> 参照: [scene-and-object.md](../../architecture/scene-and-object.md), [fix_contents.md](../../architecture/fix_contents.md)  
> 目的: 設計上の階層「Object → Components → Nodes → Structs」を、**contents 層のみの拡張**で実装する。エンジン（core）は変更せず、Object が Component リストを持ち、その Component が Node（および Struct）を使う紐づきを確立する。

---

## 1. 背景と方針

### 1.1 設計上の階層（scene-and-object.md）

```
Contents（体験）
    └── Scenes（時間軸）
            └── Objects（空間軸）
                    └── Components
                            └── Nodes
                                    └── Structs
```

- **Struct**: データ型（Transform, Color, Value.Float 等）。既存の `Structs.Category.*` で定義済み。
- **Node**: 論理の原子。Struct を扱う。`Contents.Behaviour.Nodes` に従ったモジュールが既存。
- **Component**: Node を束ねて特定の機能を提供。現状は **コンテンツ単位**（`Content.components/0`）でエンジンから呼ばれる `Core.Component` のみ。Object に紐づく Component は未実装。
- **Object**: 空間上の実体。`Contents.Objects.Core.Struct` で name, parent, transform 等を保持。**Component のリストは「将来実装」のまま**。

### 1.2 現状

| 層 | 状態 |
|----|------|
| Struct | 型・データは揃っている。 |
| Node | `Contents.Behaviour.Nodes` 準拠のモジュールが存在し、Struct を扱っている。 |
| Component | `Core.Component` はコンテンツ単位でエンジンが呼び出す。Object を参照しない。 |
| Object | `Contents.Objects.Core.Struct` に `components` フィールドはない。 |

エンジン（core）は `Content.components/0` でモジュールリストを取得し、各モジュールの `on_nif_sync/1` 等を呼ぶのみで、**Object の概念は知らない**。

### 1.3 方針

- **エンジンは変更しない**。contents アプリ内だけで「Object が Component リストを持ち、その Component が Node（と Struct）を使う」紐づきを実装する。
- Object に属する Component の**実行**は、既に Object や state を触っている **build_frame / update / ヘルパー**から行う。エンジンが「Object の Component を呼ぶ」必要はない。
- Object に紐づく Component は、`Core.Component` とは別の契約（例: `Contents.Behaviour.ObjectComponent`）とする。中で既存の Node と Struct を利用する。

### 1.4 用語

- **ObjectComponent（Object に紐づく Component）**: 本計画で新設する契約。Object に属し、Node（および Struct）を用いて処理する。エンジンからは呼ばれず、contents 層の build_frame / update 等から呼ばれる。
- **Core.Component**: 既存のコンテンツ単位コンポーネント。エンジンが `on_nif_sync/1` 等で呼び出す。本計画では変更しない。

---

## 2. 実施手順

### Phase 1: Object に components フィールドを追加する

| タスク | 内容 |
|--------|------|
| **Contents.Objects.Core.Struct** | `defstruct` に `components: []` を追加する。型は `[module()]` または `[term()]`（将来のインスタンス参照に備えて `term()` でも可）。 |
| **@type の更新** | `t/0` に `components: [module()]` を追加する。 |
| **new/0, new/1** | 既存のまま。opts で `components: [Mod1, Mod2]` を渡せるようにする（`struct!/2` で既に可）。 |
| **後方互換** | 既存の Object 生成箇所は `components` を渡さないため、デフォルト `[]` で従来通り動作する。 |

**成果物**: `apps/contents/lib/objects/core/struct.ex` の変更。既存の CreateEmptyChild 等は変更不要（子も親も components 未指定でよい）。

---

### Phase 2: ObjectComponent 契約（Behaviour）を定義する

| タスク | 内容 |
|--------|------|
| **新規 Behaviour** | `Contents.Behaviour.ObjectComponent` を新設する。ファイル: `apps/contents/lib/behaviour/object_component.ex`（または既存の behaviour 名前空間に合わせる）。 |
| **コールバック** | 少なくとも 1 つ定義する。例: `@callback run(object :: Contents.Objects.Core.Struct.t(), context :: map()) :: term()`。Object と context を受け取り、Node を呼び出して Struct を扱う。 |
| **@optional_callbacks** | 将来 `contribute_to_frame/2` 等を増やす場合は optional にしてもよい。初回は `run/2` のみでよい。 |
| **doc** | 「Object に紐づく Component。contents 層の build_frame / update 等から呼ばれる。Node と Struct を利用する。」旨を @moduledoc に記載する。 |

**成果物**: `Contents.Behaviour.ObjectComponent` の定義。実装モジュールは Phase 3 以降でよい。

---

### Phase 3: Object の Component を実行する入口を用意する

| タスク | 内容 |
|--------|------|
| **ヘルパー** | Object ツリーを走査し、各 Object の `object.components` に列挙されたモジュールの `run(object, context)` を呼ぶヘルパーを用意する。例: `Contents.Objects.Components.run_components(object, context)` または `Contents.Scenes.Helpers.run_object_components(state, context)`。再帰は「子 Object も走査する」か「トップレベルのみ」を doc で明示する。 |
| **呼び出し元** | 既存の **build_frame(state, context)** または **update(context, state)** のいずれか（または両方）から、上記ヘルパーを呼ぶ。例: build_frame の先頭で `state.children` を走査し、各 Object の components を実行して結果をマージする。結果の使われ方は「フレーム組み立てに使う」「state 更新に使う」等、初回は最小限（例: 副作用のみで戻り値は無視）でもよい。 |
| **context** | 既存の build_frame や update に渡っている context をそのまま ObjectComponent に渡す。必要なら `context` に `state` や `origin` を追加して渡す。 |

**成果物**: Object の components を実行するヘルパーと、build_frame / update からの呼び出し。これにより「Struct → Node → Component → Object」の**データ・制御の流れ**が contents 層で繋がる。

---

### Phase 4: サンプル ObjectComponent を 1 つ実装する（任意）

| タスク | 内容 |
|--------|------|
| **実装例** | `Contents.Behaviour.ObjectComponent` を実装するモジュールを 1 つ用意する。例: FormulaTest 用に「Object に紐づき、既存の Nodes.Test.Formula の結果を参照する」だけの軽い Component。または「Value Node を handle_sample して transform に反映する」等。 |
| **Object への付与** | FormulaTest.Playing の init で、作成する Object のいずれかに `components: [そのモジュール]` を渡す。 |
| **検証** | 起動し、run_components が呼ばれていること（ログや戻り値の利用で確認）を確認する。 |

**成果物**: ObjectComponent の実装例と、Object に components を付与する例。必須ではなく、Phase 1〜3 で紐づきの仕組みが動作すれば Phase 4 は後回しでもよい。

---

### Phase 5: ドキュメントの更新

| タスク | 内容 |
|--------|------|
| **scene-and-object.md** | 「Component のリスト」を「将来実装」から「Object は components フィールドで Component モジュールのリストを持つ。実行は contents 層の build_frame / update 等から行う」旨に更新する。 |
| **fix_contents.md** | Object と Component の関係に、ObjectComponent と contents 層での実行の記載を追加する（必要に応じて）。 |
| **本計画書** | 完了条件をチェックリストで明示する。 |

**成果物**: アーキテクチャ文書と本計画書の整合。

---

## 3. 将来やるべきこと（本計画では実施しない）

以下は紐づきの**最小実装には不要**であり、将来の計画で実施する。

| 項目 | 内容 |
|------|------|
| **core の変更** | エンジンが `Core.Config` / `Core.Component` の呼び出しループに Object を渡す必要はない。Object の Component 実行は contents 層に閉じる。 |
| **Object の GenServer 化** | fix_contents.md では「Object は GenServer で動作」とあるが、紐づきのためには Object は構造体のままでよい。GenServer 化は別計画で実施する。 |
| **Component の GenServer 化** | ObjectComponent は「モジュール + コールバック」の convention で足りる。GenServer 化は別計画で実施する。 |
| **既存 Core.Component の変更** | Render 等の既存コンポーネントはそのまま。Object に紐づく Component は別契約（ObjectComponent）として追加する。 |
| **Object ツリーの正規化** | 子孫の再帰走査や、親子関係の一貫性保証は、必要に応じて別タスクで拡張する。 |
| **ObjectComponent のライフサイクル** | 現状は `run/2` の都度呼び出しのみ。on_attach / on_detach 等は将来検討する。 |

---

## 4. 参照一覧

| ドキュメント | 役割 |
|--------------|------|
| [scene-and-object.md](../../architecture/scene-and-object.md) | Scene と Object の責務。階層「Object → Components → Nodes → Structs」の記載。 |
| [fix_contents.md](../../architecture/fix_contents.md) | structs / nodes / components / objects の構成と依存方向。 |
| [scene-origin-landing-implementation-plan.md](./scene-origin-landing-implementation-plan.md) | Scene state の origin / landing_object / children。Object の扱いと整合する。 |

---

## 5. 完了条件

- [ ] `Contents.Objects.Core.Struct` に `components` フィールドが追加されている
- [ ] `Contents.Behaviour.ObjectComponent` が定義され、`run/2` がコールバックとして宣言されている
- [ ] Object の components を実行するヘルパーが用意され、build_frame または update から呼ばれている
- [ ] （任意）サンプル ObjectComponent が 1 つ実装され、Object に付与する例がある
- [ ] scene-and-object.md の「Component のリスト」が本実装に合わせて更新されている
- [ ] 本計画書の「将来やるべきこと」が doc または backlog に反映されている（必要に応じて）
