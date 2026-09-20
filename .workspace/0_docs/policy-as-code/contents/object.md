# Policy: Contents — 層の責務（Structs / Node / Component / Object）

[← index](../index.md)

> **設計方針**: Schema を廃止し、Structs に統合する。データの形は Structs、変換・処理のロジックは Node が担う。戦略・戦術は Node 層に集約する。

---

## 1. 層の責務一覧


| 層             | 問い         | 責務        | 表現                   |
| ------------- | ---------- | --------- | -------------------- |
| **Structs**   | 「これは何か」    | データの形の定義  | `defstruct`, `@type` |
| **Node**      | 「これをどうするか」 | 変換・処理ロジック | pins, callbacks, グラフ |
| **Component** | 「どこで動くか」   | ノード束ね・状態  | ノードグラフのコンテナ          |
| **Object**    | 「何に属するか」   | 空間上の実体    | コンポーネント・子の親          |


---

## 2. 各層の詳細

### Structs（旧 Schema を統合）

- **役割**: データの「形」。何であるか。静的な定義。
- **内容**: `defstruct` + `@type`（複合型）、または `@type` のみ（プリミティブ・タプル）
- **戦略・戦術**: 持たない。純粋に「形」の契約のみ。

### Node

- **役割**: データの「扱い方」。変換・処理のロジック。戦略・戦術を体現。
- **内容**: Action/Logic pins、`handle_pulse`、`handle_sample`、入出力型契約
- **戦略**: 各ノードの振る舞い（add は足す、write は書く）
- **戦術**: 接続グラフ（どのノードをどう繋ぐか）

### Component

- **役割**: ノードを束ね、特定の機能を提供。状態を保持する。
- **内容**: ノードグラフのコンテナ。GenServer で動作。

### Object

- **役割**: 空間上の実体（Entity）。コンポーネントと子オブジェクトの親。
- **内容**: コンポーネント・子の管理。GenServer で動作。

---

## 3. 依存の方向

```
Structs → Node → Component → Object
```

- Structs は最下位。他層から参照されるのみ。逆参照しない。
- Node は Struct にのみ依存。
- Component は Struct、Node に依存。
- Object は Struct、Node、Component に依存。

---

*このポリシーは [fix_contents.md](../../architecture/fix_contents.md) および [fix-contents-implementation-procedure.md](../../plan/completed/fix-contents-implementation-procedure.md) と整合する。*
