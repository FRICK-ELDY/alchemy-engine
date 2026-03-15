# Scene と Object の責務と境界

> 参照: [fix_contents.md](./fix_contents.md), [scene-concept-addition-plan.md](../plan/completed/scene-concept-addition-plan.md)

---

## 1. 概要

AlchemyEngine は **Scene（時間軸）** と **Object（空間軸）** を分離することで、Resonite/VRChat にはない「体験の段階」を明示的に扱う。

- **Scene**: いまどの段階か、次にどこへ遷移するか
- **Object**: 空間に何が存在するか、どこにどのように配置されているか

---

## 2. 階層上の位置づけ

```
Contents（体験）
    └── Scenes（時間軸）
            └── Objects（空間軸）
                    └── Components
                            └── Nodes
                                    └── Structs
```

- Scene は Contents の下位、Object の上位
- Scene が Object ツリーのルートを保持する
- Object は Scene に依存しない（単方向依存）

---

## 3. Scene の責務

### 3.1 Scene が持つもの

| 項目 | 内容 |
|------|------|
| **遷移状態** | スタック上で top かどうかは SceneStack が管理。Scene は自身の state を保持 |
| **root_object** | Object ツリーのルート参照。ユーザーが Scene に降り立つ着地点。どの Object をルートにするかはコンテンツ製作者が選択。新規・将来コンテンツでは必須 |
| **時間依存の state** | カウントダウン、経過時間、遷移条件に使うフラグ等 |
| **遷移判定ロジック** | update 内で `{:transition, ...}` を返す |

### 3.2 Scene の契約

- `Contents.SceneBehaviour`（`Contents.Behaviour.Scenes` を use）を実装
- `init/1`, `update/2`, `render_type/0` を提供
- state には `%{root_object: Object.t(), ...}` を持つ（新規コンテンツでは必須）。どの Object をルートにするかはコンテンツ製作者が選択

### 3.3 例：Scene の責務

- 「3秒経ったら次の Scene へ」→ Scene の責務
- 「プレイヤーがゴールに到達したらクリア Scene へ」→ Scene が遷移条件を判定
- 「現在の経過時間を HUD に表示する」→ Scene が time を state に持ち、RenderComponent に渡す

---

## 4. Object の責務

### 4.1 Object が持つもの

| 項目 | 内容 |
|------|------|
| **Transform** | 位置・回転・スケール |
| **親子関係** | parent, children |
| **Component のリスト** | 将来実装 |
| **空間属性** | name, tag, active |

### 4.2 例：Object の責務

- 「プレイヤーが (10, 0, 5) にいる」→ Object（Player）の責務
- 「このオブジェクトは非表示にする」→ Object の active フラグ
- 「子オブジェクトを 3 つ持つ」→ Object の親子関係

---

## 5. 境界の例

| 状況 | 責務 | 理由 |
|------|------|------|
| 3秒経ったら次の Scene へ | **Scene** | 時間に基づく遷移判定 |
| プレイヤーが (10, 0, 5) にいる | **Object** | 空間上の位置情報 |
| ボタンがクリックされた | **Object の Component** がイベント発火 → **Scene** が受け取って遷移を決める | Component は入力検知、Scene は遷移判定 |
| 敵が 10 体出現した | **Object** が子として生成。**Scene** がカウントを管理して「全滅で次へ」を判定 | 空間構造 vs 時間的条件 |
| HUD の表示/非表示トグル | **Scene** の state（hud_visible） | 体験の段階に紐づく UI 状態 |

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

- **Scenes** は **Objects** に依存する（root_object を保持）
- **Objects** は **Scenes** に依存しない
- **Contents** は **Scenes** を initial_scenes 等で定義する

---

## 7. 既存実装との関係

| モジュール | 本設計での扱い |
|------------|----------------|
| `Contents.SceneStack` | Scene 概念のインフラ。push/pop/replace を提供 |
| `Contents.SceneBehaviour` | 既存の Scene 契約。`Contents.Behaviour.Scenes` を use |
| 各コンテンツの `Scenes.Playing` 等 | Scene として扱う。state に root_object（着地点）を持つ（新規コンテンツでは必須） |

既存コンテンツ（FormulaTest 等）は移行対象外。参照用として残し、新規・将来コンテンツのみ新規約に従う。

---

## 8. Scene state の規約（新規・将来コンテンツ）

### 8.1 必須項目

Scene の state は `%{root_object: Object.t(), ...}` を持つことを**必須**とする。

- **root_object**: Object ツリーのルート参照。ユーザーが Scene に降り立つ着地点。
- **どの Object をルートにするかはコンテンツ製作者が選択**する（プレイヤー、ワールドルート、UI ルート等）。

### 8.2 既存コンテンツの扱い

| 対象 | 扱い |
|------|------|
| **既存コンテンツ** | 移行対象外。root_object なしでも許容。参照用として残す |
| **新規・将来コンテンツ** | 本規約に従い、state に root_object を必須で持つ |
