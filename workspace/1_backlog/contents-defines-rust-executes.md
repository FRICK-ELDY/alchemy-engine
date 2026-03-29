# Contents 定義 / Rust 実行 — 方針とリファクタリング計画

> 作成日: 2026-03-07  
> 出典: NIF 層の関数型/データ指向混在の議論、[contents-to-physics-bottlenecks.md](../../docs/architecture/contents-to-physics-bottlenecks.md)  
> 参照: [implementation.mdc](../../../.cursor/rules/implementation.mdc)、[improvement-plan.md](../0_reference/improvement-plan.md)

---

## 1. 方針（保証の原則）

### 1.1 レイヤー別の責務


| レイヤー                              | 保障するもの          | 保障しないもの       |
| --------------------------------- | --------------- | ------------- |
| **Elixir (contents)**             | **定義**          | 処理の実装・結果の保証   |
| **Rust (render / physics / nif)** | **定義に基づく処理と結果** | 定義の作成・ゲームロジック |


### 1.2 定義の内訳


| 定義の種類     | 内容                           | 現状                                                                    |
| --------- | ---------------------------- | --------------------------------------------------------------------- |
| **メッシュ**  | 頂点・インデックス・UV・法線等のジオメトリ       | `unit_box` / `skybox_quad` / `grid_lines`（GridPlane）はいずれも Elixir 定義 ✓ |
| **シェーダー** | WGSL ソース・uniform 定義・パイプライン設定 | Elixir 定義（assets 配下）or `include_str!` フォールバック ✓                       |
| **式**     | 数式・パラメータ計算（FormulaGraph）     | Elixir が定義、Rust VM が実行 ✓                                              |


### 1.3 Rust の責務（実行層）

- **定義を受け取り、それに従って処理する**
- 定義の妥当性検証・エラーハンドリング
- 処理結果の出力（描画、物理イベント、オーディオ等）
- **定義にない知識を Rust 内に持たない**

---

## 2. 課題

### 2.1 シェーダー


| 課題                       | 内容                                                                                                 |
| ------------------------ | -------------------------------------------------------------------------------------------------- |
| **リアルタイム編集 → プレビュー**     | コンテンツ内エディタで WGSL 編集 → Apply → コンパイル結果を即確認する UX                                                     |
| **アセット化・他コンテンツでの再利用**    | ShaderAsset スキーマ設計、名前での参照・ロード機構                                                                    |
| **Phase 1〜2 の実装**        | 既存アーキタイプの body 差し替え → 新アーキタイプ定義可能にする                                                               |
| **Path Traversal 対策の実装** | [shader-path-traversal-design.md](../2_todo/shader-path-traversal-design.md) Phase 1〜2 参照 |


### 2.2 転送・その他


| 課題     | 内容                                                      |
| ------ | ------------------------------------------------------- |
| 転送効率化（継続） | `get_render_entities` の O(n) コピー削減（差分更新・プール等）、必要に応じて計測。詳細は [p5-transfer-optimization-design.md](../7_done/p5-transfer-optimization-design.md) |
| セキュリティ | 不信頼コンテンツ利用時のサンドボックス化                                    |


---

## 3. 採用しない方針


| 方針                                      | 理由                                                               |
| --------------------------------------- | ---------------------------------------------------------------- |
| **案 B: Rust 側で SoA から DrawCommand を生成** | Rust に描画判断（メッシュ選択・UV 等）を持たせることになり、「Elixir が定義」の原則に反する            |
| **Rust 側でのゲーム固有概念のハードコード**              | `implementation.mdc` の層間インターフェース設計に違反。既存の `spawn_boss` 等の廃止方針と一致 |
| **Phase 3（完全フレックス）の実装**                 | 検討のみ。実装範囲は Phase 2（新アーキタイプ定義可能）までとする                             |


---

## 4. 関連ドキュメント

- [p5-transfer-protobuf-implementation-plan.md](../7_done/p5-transfer-protobuf-implementation-plan.md) — P5 Protobuf 実施プラン（完了）
- [implementation.mdc](../../../.cursor/rules/implementation.mdc) — 保証の原則・層間インターフェース
- [shader-path-traversal-design.md](../2_todo/shader-path-traversal-design.md) — P4-S Path Traversal 対策設計
- [contents-to-physics-bottlenecks.md](../../docs/architecture/contents-to-physics-bottlenecks.md) — ボトルネック・改善案
- [improvement-plan.md](../0_reference/improvement-plan.md) — 全体改善計画
- [Rust: desktop_render](../../docs/architecture/rust/desktop/render.md) — 描画パイプライン現状
- [Rust: nif](../../docs/architecture/rust/nif.md) — NIF インターフェース
- [formula-hardcode-inventory.md](../2_todo/formula-hardcode-inventory.md) — P1-1 ハードコード一覧
- [formula-migration-evaluation.md](../2_todo/formula-migration-evaluation.md) — P1-2 武器式 Formula 移行評価
- [formula-vm-bytecode.md](../../docs/architecture/formula-vm-bytecode.md) — P1-3 Formula VM バイトコード仕様
- [draw-command-spec.md](../../docs/architecture/draw-command-spec.md) — P2-1 DrawCommand タグ・フィールド仕様（SSoT）
- [shader-elixir-interface.md](../../docs/architecture/shader-elixir-interface.md) — P4-2〜5 シェーダー Elixir インターフェース・アセット構成

