# Scene の原点と着地点参照の実施計画

> 作成日: 2026-03-16  
> 参照: [scene-and-object.md](../../architecture/scene-and-object.md), [scene-concept-addition-plan.md](../completed/scene-concept-addition-plan.md)  
> 目的: Scene が空間の原点（origin）を持ち、着地点は Object への参照のみとする設計に移行する。root_object 必須を廃止し、シーンインスペクター等で「Scene ┣ user」のようにトップレベル Object を直下に扱えるようにする。

---

## 1. 背景と方針

### 1.1 現状

- Scene の state に `root_object`（Object ツリーのルート＝着地点）を**必須**で持つ規約がある。
- root_object は transform を持つため「空間の原点」としても使われがちだが、本来**原点は時間軸の単位である Scene に属する**のが自然。
- 着地点は「このシーンでフォーカスする Object」の**参照**で足りる。専用のルート Object を必須にすると、インスペクターが「root → user」となり、ダミーの root が増える。

### 1.2 目標

| 項目 | 現状 | 目標 |
|------|------|------|
| **空間の原点** | root_object の transform に委ねがち | **Scene** が `origin`（transform）を持つ |
| **着地点** | root_object（必須）＝ ツリーの根かつ着地点 | **参照のみ**（例: `landing_object`）。どの Object を入口とするかはコンテンツ製作者が選択 |
| **ツリーの根** | 専用の root Object | **Scene がツリーの根**。トップレベル Object は Scene の子として扱う（または親なしのリストを Scene が保持） |
| **シーンインスペクター** | root ┣ user ┣ … | Scene ┣ user ┣ …（root ノードなし） |

### 1.3 用語

- **origin**: Scene が持つ空間の原点（Transform）。シーン座標系の基準。
- **landing_object（着地点参照）**: ユーザーがシーンに降り立つ際のフォーカス対象となる Object への参照。必須ではなく、必要に応じて state に持つ。
- **root_object**: 旧規約の「必須のルート Object」。本計画実施後は**推奨しない**。既存コンテンツは移行対象外のため、root_object を残したままでも許容する。

---

## 2. 実施手順

### Phase 1: アーキテクチャ文書の更新

| タスク | 内容 |
|--------|------|
| scene-and-object.md | Scene の責務に **origin**（空間の原点）を追加。**root_object 必須**を廃止し、**着地点は参照（landing_object 等）** とする旨に変更。Scene state の規約（§8）を「origin 必須・landing は任意参照」に更新。 |
| fix_contents.md | Scene の説明から root_object 必須を削除し、origin と着地点参照の記載に合わせる。 |

### Phase 2: Behaviour と SceneBehaviour の doc 更新

| タスク | 内容 |
|--------|------|
| `Contents.Behaviour.Scenes` | モジュール doc および `init/1` の @doc から「root_object 必須」を削除。新規・将来コンテンツでは state に **origin**（任意で **landing_object** 参照）を持つことを推奨する旨に変更。 |
| `Contents.SceneBehaviour` | 現状の方針（origin は Scene、着地点は参照）を反映した文言に更新。実施計画書への参照を追加。 |

### Phase 3: 既存コンテンツ・migration-plan の扱い

| タスク | 内容 |
|--------|------|
| 既存コンテンツ | 移行対象外。FormulaTest 等で root_object を残したままでも許容。参照用として残す。 |
| contents-migration-plan.md | 「Scene の root_object 必須」を「Scene の origin と着地点参照」に更新。scene-and-object.md への参照を維持。 |

### Phase 4: コード実装（別計画で実施）

- Scene の state 型や Stack が origin / children（トップレベル Object リスト）を扱う実装、および FormulaTest.Playing の root_object 置き換えは、実施計画書に委譲する。
- 実施計画: [scene-origin-landing-implementation-plan.md](./scene-origin-landing-implementation-plan.md) に委譲（コード実装は同実施計画書に従う）。

---

## 3. 参照一覧

| ドキュメント | 役割 |
|--------------|------|
| [scene-and-object.md](../../architecture/scene-and-object.md) | Scene と Object の責務。実施後は origin / 着地点参照の規約を記載。 |
| [scene-concept-addition-plan.md](../completed/scene-concept-addition-plan.md) | Scene 概念追加時の決定（root_object 必須化）。本計画で方針を発展させる。 |
| [contents-migration-plan.md](./contents-migration-plan.md) | 新規コンテンツの共通パターン。root_object 必須 → origin + 着地点参照に更新。 |

---

## 4. 完了条件

- [x] docs/architecture/scene-and-object.md が origin と着地点参照の規約に更新されている
- [x] docs/architecture/fix_contents.md の Scene 記述が更新されている
- [x] Contents.Behaviour.Scenes の @moduledoc / init の @doc が新方針に更新されている
- [x] Contents.SceneBehaviour の @moduledoc が現状の方針に更新されている
- [x] docs/plan/current/contents-migration-plan.md の該当箇所が更新されている
