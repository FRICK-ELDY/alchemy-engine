# 現行プラン・手順書の実装順序

> 作成日: 2026-03-15  
> 目的: contents-behaviour、formula-test-scene、scene-abstraction、scene-type-as-atom の 4 ドキュメントを、どの順番で実装するかを示す。

---

## 1. 全体の順序

| 順番 | ドキュメント | 種別 | 説明 |
|------|--------------|------|------|
| **0** | [scene-abstraction-and-engines.md](./scene-abstraction-and-engines.md) | 参照 | 実装手順ではなく**設計の参照**。案B と他エンジン比較。実装前に読んで方針を決める用。 |
| **1** | [contents-behaviour-namespace-implementation-plan.md](./contents-behaviour-namespace-implementation-plan.md) | 実施計画 | **最初に実施する**。Contents.Behaviour.* の土台（Content, Scenes, Objects, Nodes, Components）を整え、Core.ContentBehaviour を Contents.Behaviour.Content に移す。以降の手順はすべてこの後の状態を前提にする。 |
| **2** | どちらか一方（下記 2-A / 2-B） | 実施手順 | シーンまわりは「現方式のまま整理」か「案B に切り替え」の**どちらか**を選ぶ。 |

---

## 2. シーンまわりの二択（2 のあと）

### 2-A: 現方式のまま「シーンを scenes 配下に集約」する場合

- **実施する**: [formula-test-scene-migration-procedure.md](./formula-test-scene-migration-procedure.md)
- **結果**: `Content.FormulaTest.Scenes.Playing` が `Contents.Scenes.FormulaTest.Playing` に移り、`apps/contents/lib/scenes` に配置される。SceneStack は従来どおり「シーンモジュール」をキーに動く。
- **向き**: まずは影響範囲を小さくしつつ、シーン配置だけ新方式に揃えたいとき。

### 2-B: 案B（シーン種別＝atom・実装＝コンテンツ）に切り替える場合

- **実施する**: [scene-type-as-atom-implementation-procedure.md](./scene-type-as-atom-implementation-procedure.md)
- **結果**: シーンは `:playing` 等の atom になり、各 Content が `scene_init/2`, `scene_update/3`, `scene_render_type/1` を実装する。`Contents.Scenes.FormulaTest.Playing` のようなモジュールは作らず、FormulaTest は `Contents.Behaviour.Content` の scene_* で `:playing` を実装する。
- **向き**: 「Contents.Scenes.Playing を Content.VampireSurvivor で使う」ような抽象化をしたいとき。
- **注意**: 2-A を先にやってから 2-B にすると、一度作った `Contents.Scenes.FormulaTest.Playing` を廃止し、Content.FormulaTest の scene_* に寄せる作業が発生する。最初から案B で行くなら 2-A は実施しない。

---

## 3. 依存関係の整理

```
scene-abstraction-and-engines.md  …… 参照（いつでも読む）
                │
                ▼
contents-behaviour-namespace-implementation-plan  …… 1. 必ず最初に実施
                │
                ├──► formula-test-scene-migration-procedure  …… 2-A. 現方式でシーン配置だけ整理
                │
                └──► scene-type-as-atom-implementation-procedure  …… 2-B. 案B に切り替え（2-A と排他）
```

- **Behaviour 計画**が終わっていないと、formula-test-scene 手順で参照する `Contents.SceneBehaviour`（や `Contents.Behaviour.Scenes`）がまだない、または Content がまだ `Core.ContentBehaviour` のままになる。
- **案B 手順**では、ContentBehaviour に scene_* を追加する。Behaviour 計画のあとであれば、追加先は `Contents.Behaviour.Content` で統一できる（計画書中の「Core.ContentBehaviour」は、実施後は Contents.Behaviour.Content に読み替える）。

---

## 4. 推奨の進め方

1. **scene-abstraction-and-engines.md** を読んで、2-A と 2-B のどちらにするか決める。
2. **contents-behaviour-namespace-implementation-plan.md** を実施する。
3. **2-A か 2-B のどちらか**を実施する。  
   - まず影響を小さくしたい → 2-A（formula-test-scene-migration）。  
   - 最初から案B にしたい → 2-B（scene-type-as-atom）のみ実施し、2-A は行わない。

---

## 5. ブランチ名・コミットメッセージの提案

### 5.0 現状の差分（計画ドキュメント追加分）用

今回追加した計画・手順書をまとめてコミットする場合の例です。

**ブランチ名**
```
docs/plan-contents-behaviour-and-scene
```

**コミットメッセージ**
```
docs(plan): Contents.Behaviour とシーン移行の計画・手順書を追加

- contents-behaviour-namespace-implementation-plan.md … Behaviour 名前空間と Content 契約の移行
- formula-test-scene-migration-procedure.md … FormulaTest Playing を scenes 配下へ移行する手順
- scene-abstraction-and-engines.md … シーン抽象化と Unity/UE/Godot 比較（案B の設計参照）
- scene-type-as-atom-implementation-procedure.md … 案B（シーン種別＝atom）の実施手順
- implementation-order-for-plans.md … 上記の実装順序とブランチ・コミットメッセージ案
```

---

### 5.1 実装時のブランチ名

| 作業 | ブランチ名案 |
|------|----------------|
| 1. Behaviour 名前空間 | `feat/contents-behaviour-namespace` |
| 2-A. FormulaTest シーン移行 | `feat/formula-test-scene-to-scenes` |
| 2-B. 案B（シーン種別＝atom） | `feat/scene-type-as-atom` |

- 1 だけやる場合: `feat/contents-behaviour-namespace` で作成・マージ。
- 1 → 2-A と続ける場合: 1 をマージしたあと `feat/formula-test-scene-to-scenes` を main から作成。または 1 のブランチの上に `feat/formula-test-scene-to-scenes` を積む（1 をマージせずに 2-A までまとめる場合は、同じブランチで 2-A までコミットを重ねてもよい）。
- 1 → 2-B と続ける場合: 同様に `feat/scene-type-as-atom` を 1 のあとに作成。

### 5.2 コミットメッセージ案

**1. Behaviour 名前空間（複数コミットに分ける場合の例）**

```
feat(contents): Contents.Behaviour 名前空間の追加と Content 契約の移行

- behaviour/ に Contents.Behaviour, .Content, .Scenes, .Objects, .Nodes, .Components を追加
- Core.ContentBehaviour を Contents.Behaviour.Content に移す（core は実行時に content を参照）
- 全 @behaviour / @impl を Contents.Behaviour.* に更新
- apps/core/lib/core/content_behaviour.ex を削除

Ref: docs/plan/current/contents-behaviour-namespace-implementation-plan.md
```

**2-A. FormulaTest シーン移行**

```
feat(contents): FormulaTest Playing を Contents.Scenes.FormulaTest.Playing に移行

- apps/contents/lib/scenes/formula_test/playing.ex を追加
- Content.FormulaTest, InputComponent, RenderComponent の参照を新モジュールに更新
- contents/formula_test/scenes/playing.ex を削除

Ref: docs/plan/current/formula-test-scene-migration-procedure.md
```

**2-B. 案B（シーン種別＝atom）**

```
feat(contents): シーン種別＝atom・実装＝コンテンツ（案B）へ移行

- Contents.Behaviour.Content に scene_init/2, scene_update/3, scene_render_type/1 を追加
- SceneStack を %{scene_type, state} に変更、get_scene_state / update_by_scene_type に変更
- GameEvents で content.scene_*(scene_type, ...) を呼ぶ形に変更
- FormulaTest（および必要に応じて他コンテンツ）を :playing の scene_* 実装に移行

Ref: docs/plan/current/scene-type-as-atom-implementation-procedure.md
```

**ドキュメント追加のみ（実装前に出した場合）**

```
docs(plan): 実装順序とブランチ・コミットメッセージ案を追加

- implementation-order-for-plans.md
- Behaviour / シーン移行 / 案B のブランチ名・コミットメッセージ例
```

---

## 6. 参照

- [contents-behaviour-namespace-implementation-plan.md](./contents-behaviour-namespace-implementation-plan.md)
- [formula-test-scene-migration-procedure.md](./formula-test-scene-migration-procedure.md)
- [scene-abstraction-and-engines.md](./scene-abstraction-and-engines.md)
- [scene-type-as-atom-implementation-procedure.md](./scene-type-as-atom-implementation-procedure.md)
