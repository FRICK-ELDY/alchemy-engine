# Node DSL の見通し

> 作成日: 2026-03-12  
> 参照: [fix_contents.md](../../architecture/fix_contents.md)、[fix-contents-implementation-procedure.md](../completed/fix-contents-implementation-procedure.md)  
> 目的: Node 層の実装において、将来的に DSL（Domain Specific Language）を導入する意義と検討事項をまとめる。

---

## 1. 概要

fix_contents アーキテクチャでは、Nodes は「論理のピア」として Node-Port-Link モデルで定義される。ノードの種類が増えるにつれ、Port の宣言やコールバックの共通パターンが明確になるため、**Node 定義のための DSL を将来視野に入れておく**ことは妥当である。

本ドキュメントは、その背景・根拠・導入タイミング・注意点を記録する。

---

## 2. DSL を検討する理由

### 2.1 ノードの量とパターンの類似性

実装手順書で想定されているノード種別は多く、いずれも似た構造を持つ。

| カテゴリ | 例 |
|:---|:---|
| **operators** | add, sub, mul, div, equals など |
| **operators/boolean** | and, or, xor, nand, nor, xnor, shift, rotate |
| **operators/bool_vectors** | all, any, none, xor_elements |
| **actions** | write（action in + logic in → 処理 → action out） |
| **core/input** | call, value, display |
| **math** | sign, cos, tan など（将来） |

これらは「どの Port を持つか」「何を処理するか」の違いであり、Port の宣言や `handle_pulse` / `handle_sample` のフローは共通化しやすい。

### 2.2 Node-Port-Link モデルの明確さ

fix_contents の Node-Port-Link モデルは以下のように定義されており、DSL 化しやすい構造である。

- **Node**: 計算の原子単位。`outputs = f(inputs)` に対応
- **Port**: 入出力端子（action in/out, logic in/out）
- **Link**: Port 間の接続。グラフの保存・復元、型チェック、実行順序の決定の基盤

Port の「宣言」と、それに基づく処理の「実装」を分離できれば、DSL で宣言部分を抽象化できる。

### 2.3 グラフの保存・復元・型チェック

> Link を明示的な概念として持つことで、グラフの保存・復元、型チェック、実行順序の決定が明確になる。（fix_contents.md より）

DSL でノードを定義すると、その定義が「型付きグラフのスキーマ」となる。JSON 等へのシリアライズ、Executor のトラバース、型チェックのロジックが一貫した土台の上に構築しやすくなる。

### 2.4 定義と実行の分離（contents-defines-rust-executes）

[contents-defines-rust-executes.md](./contents-defines-rust-executes.md) の方針に沿うと：

- **Elixir 側**: ノードの「定義」（DSL で記述）
- **Rust 側**: 定義に基づく「実行」

DSL が「Elixir 非依存の定義フォーマット」を生成できれば、将来的な Rust Executor との連携が容易になる。

### 2.5 VR 体験との対応

> Action ports（時間）は「光る脈動」として、Logic ports（情報）は「静かな導管」として視覚化する。（fix_contents.md より）

DSL で Port の種類や型を宣言しておけば、VR 空間でのノード可視化や Resonite とのマッピングに必要なメタデータを揃えやすい。

---

## 3. 導入タイミング

| フェーズ | 内容 |
|:---|:---|
| **現状** | structs を基盤とする。Node の具体実装はこれから。 |
| **DSL 検討開始** | Node 実装が数個揃い、共通パターンが見えてきた段階（Phase 3 の途中〜後半） |
| **DSL 導入判断** | add / write / call などの代表ノード実装後、ボイラープレートの重複が明確になったタイミング |

**方針**: いきなり DSL を設計するのではなく、手順書どおりに Elixir の Behaviour とモジュールで Node を実装し、**反復しながら共通部分を洗い出す**。その結果を踏まえて DSL のスコープを決める。

---

## 4. 導入時の注意点

### 4.1 DSL のスコープを抑える

最初は以下に限定することを推奨する。

- Port の宣言（action in/out, logic in/out）
- 各 Port の型（structs の型参照）
- `handle_pulse` / `handle_sample` の雛形の自動生成

**ロジック本体**は従来どおり Elixir の関数として実装し、DSL は「インターフェース定義」に留める。Ecto.Schema のように宣言的でありつつ、柔軟性を保つ。

### 4.2 既存の Elixir マクロとの整合

Ecto.Schema、Phoenix.Router など、Elixir の DSL はマクロで `quote` / `unquote` を使うパターンが一般的。同じ方針で Node DSL を実装すれば、既存の慣習に沿った保守しやすいコードになる。

### 4.3 段階的導入

1. **Phase 1**: Port 宣言のみ DSL 化
2. **Phase 2**: コールバック雛形の自動生成
3. **Phase 3**: シリアライズ用スキーマの自動導出（必要に応じて）

---

## 5. まとめ

- Node の数・パターン・Node-Port-Link の構造を踏まえ、**Node DSL は将来の有力候補**として位置づける。
- 当面は structs → core/behaviour → nodes の順で実装を進め、Node 実装の具体例を蓄積する。
- パターンが固まり、ボイラープレートが顕在化したタイミングで、本ドキュメントを参照しつつ DSL の導入を検討する。

---

## 6. 関連ドキュメント

- [fix_contents.md](../../architecture/fix_contents.md) — アーキテクチャの全体像
- [fix-contents-implementation-procedure.md](../completed/fix-contents-implementation-procedure.md) — 実施手順
- [contents-defines-rust-executes.md](./contents-defines-rust-executes.md) — 定義層と実行層の責務
