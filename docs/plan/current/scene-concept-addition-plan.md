# Scene 概念の追加プラン

> 作成日: 2026-03-12  
> 更新日: 2026-03-15（実施方針・維持方針の決定事項を追記）  
> 参照: [fix_contents.md](../../architecture/fix_contents.md), [formula-test-phase1-architecture.md](../../architecture/formula-test-phase1-architecture.md)  
> 目的: Scene を第一級の概念としてアーキテクチャに追加し、時間軸（Scene）と空間軸（Object）を明確に分離する。
>
> **背景**: Resonite/VRChat には Object ツリーのみ存在する。AlchemyEngine は Scene（時間軸）を追加することで体験の「段階」を明示的に扱う差別化を行う。

---

## 1. 概要

### 1.1 Scene の定義

| 項目 | 内容 |
|------|------|
| **軸** | 時間軸。いまどの段階か、次にどこへ遷移するか |
| **責務** | 遷移管理、Object ツリーのルート参照、時間に依存する状態 |
| **位置** | Object の上位。Content の下位 |

### 1.2 階層の変化

**現状（Five Pillars）**

```
Contents → Objects → Components → Nodes → Structs
```

**目標（Scene 追加後）**

```
Contents（体験）
    └── Scenes（時間軸）  ← 追加
            └── Objects（空間軸）
                    └── Components
                            └── Nodes
                                    └── Structs
```

### 1.3 責務の切り分け

| 層 | 責務 |
|----|------|
| **Scene** | 時間の区切り、遷移（push/pop/replace）、Object ツリーのルート参照、遷移トリガー判定 |
| **Object** | 空間の構造、Transform、親子関係、Component のアタッチ |

---

## 2. 現状の整理

### 2.1 既存の Scene 関連

| モジュール | 役割 | 本プランでの扱い |
|------------|------|------------------|
| `Contents.SceneStack` | シーンのスタック管理（push/pop/replace） | そのまま利用。Scene 概念のインフラとして位置づけ |
| `Contents.SceneBehaviour` | init, update, render_type の契約 | 拡張。新規・将来コンテンツでは state に `root_object` を持つことを必須とする |
| 各コンテンツの `Scenes.Playing` 等 | シーン実装 | Scene として扱う。state に Object ツリーのルートを持つ |

### 2.2 維持方針と抽象化の余地

以下は破壊的変更を避けるが、**抽象化の進化の余地はある**。新設にあわせて API や仕組みが変わっていく可能性がある。

| 対象 | 方針 |
|------|------|
| SceneStack の API | 現状の push, pop, replace, update_current 等を尊重。抽象化に伴う変更の余地あり |
| GameEvents と SceneStack の連携 | 連携は維持。イベントの種類や伝搬の形が変わる余地あり |
| initial_scenes / playing_scene / game_over_scene | 仕組みは維持。**コンテンツ製作者がシーンを追加・削除できることが設計の前提**。現行の 3 種固定ではなく、柔軟に定義できる形へ進化させる余地あり |

### 2.3 変更・追加する部分

- アーキテクチャドキュメント（fix_contents.md）に Scene を明示
- Scene の state 構造の規約（**root_object は新規・将来コンテンツで必須**）
- scenes 層の Behaviour / ガイドライン追加

### 2.4 実施方針（決定事項）

| 項目 | 決定内容 |
|------|----------|
| **SceneBehaviour との関係** | 拡張。既存 `Contents.SceneBehaviour` は新 `Contents.Scenes.Core.Behaviour` を継承する |
| **root_object** | 必須化。新規・将来コンテンツでは state に `root_object` を持つことを必須とする |
| **scenes/core の配置** | `apps/contents/lib/scenes/core/` を新設する |
| **既存コンテンツ** | 移行対象外。参照用として残し、新規・将来コンテンツのみ新規約に従う。現コンテンツはほとんど動作確認用のため、旧コンテンツは参照程度とする |

---

## 3. 実施手順

### Phase 1: アーキテクチャ文書の更新

| タスク | 内容 |
|--------|------|
| fix_contents.md 更新 | Scene を Contents と Object の間に追加。時間軸・空間軸の分離を記載 |
| 新規ドキュメント | `docs/architecture/scene-and-object.md` を作成。Scene と Object の責務、境界、例を記載 |
| formula-test-phase1-architecture.md | Scene の位置づけを追記（既存図に Scene を明示） |

### Phase 2: scenes 層の骨格追加

| タスク | 内容 |
|--------|------|
| ディレクトリ作成 | `apps/contents/lib/scenes/core/` を新設 |
| Scene Behaviour | `Contents.Scenes.Core.Behaviour` を定義。init, update, render_type に加え、`root_object` 必須を doc で記載 |
| 既存 SceneBehaviour との関係 | `Contents.SceneBehaviour` は `Contents.Scenes.Core.Behaviour` を**拡張**する。既存コードとの互換性を保ちつつ統合 |

### Phase 3: Scene state の規約策定

| タスク | 内容 |
|--------|------|
| state 構造の規約 | Scene state は `%{root_object: Object.t(), ...}` を持つことを**必須**とする旨を文書化。新規・将来コンテンツで適用 |
| 既存コンテンツ | 移行対象外。旧コンテンツは参照用として残し、root_object なしでも許容。新規・将来コンテンツのみ新規約に従う |
| migration-plan 更新 | contents-migration-plan に「Scene の root_object を持つ」を新規コンテンツの共通パターン（必須）として追記 |

### Phase 4: 将来拡張の検討（本プランでは実施しない）

| 項目 | 内容 |
|------|------|
| Scene の VR 可視化 | 時間軸を UI で表現する際の検討 |
| Scene の定義形式 | デクリプタや YAML で定義するか |
| 複数 Object ツリー | 1 Scene が複数ルートを持つ構成の要否 |

---

## 4. ディレクトリ構成（目標）

```
apps/contents/lib/
├── contents/           # 既存
├── scenes/             # 新規（骨格）
│   └── core/
│       └── behaviour.ex
├── objects/
├── components/
├── nodes/
├── structs/
└── core/
```

**注記**: 各コンテンツの `Content.XXX.Scenes.Playing` 等は `contents/formula_test/scenes/` のまま。`scenes/` は共通の Behaviour 等を置く層。

---

## 5. Scene と Object の責務（再掲）

### Scene が持つもの

- 現在の遷移状態（スタック上で top かどうかは SceneStack が管理）
- Object ツリーのルート参照（`root_object`）
- 時間依存の state（カウントダウン、経過時間、遷移条件に使うフラグ等）
- 遷移判定ロジック（update 内で `{:transition, ...}` を返す）

### Object が持つもの

- Transform（位置・回転・スケール）
- 親子関係（parent, children）
- Component のリスト（将来）
- 空間に紐づく属性（name, tag, active）

### 境界の例

- 「3秒経ったら次の Scene へ」→ Scene の責務
- 「プレイヤーが (10, 0, 5) にいる」→ Object（Player）の責務
- 「ボタンがクリックされた」→ Object の Component がイベント発火。Scene が受け取って遷移を決める

---

## 6. 依存関係

```
Contents
    └── Scenes（時間軸）
            └── Objects（空間軸）
                    └── Components
                            └── Nodes
                                    └── Structs
```

- Scenes は Objects に依存する（root_object を保持）
- Objects は Scenes に依存しない
- Contents は Scenes を initial_scenes 等で定義する

---

## 7. 検証

- [ ] fix_contents.md に Scene が追記されている
- [ ] scene-and-object.md が作成されている
- [ ] scenes/core/behaviour.ex が存在する（または SceneBehaviour が scenes 概念を doc で参照している）
- [ ] 既存コンテンツ（FormulaTest 等）が引き続き動作する
- [ ] mix compile, mix test が通る

---

## 8. 参照

- [fix_contents.md](../../architecture/fix_contents.md)
- [formula-test-phase1-architecture.md](../../architecture/formula-test-phase1-architecture.md)
- [contents-migration-plan.md](./contents-migration-plan.md)
- [Contents.SceneStack](../../apps/contents/lib/contents/scene_stack.ex)
- [Contents.SceneBehaviour](../../apps/contents/lib/contents/scene_behaviour.ex)
