# Contents 定義 / Rust 実行 — 方針とリファクタリング計画

> 作成日: 2026-03-07  
> 出典: NIF 層の関数型/データ指向混在の議論、[contents-to-physics-bottlenecks.md](../../architecture/contents-to-physics-bottlenecks.md)  
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

## 2. 残タスク（フェーズ）

### P5: 転送効率化（バイナリ・バッチ） 【優先度: 中・中期】

contents-to-physics-bottlenecks の改善案と連携。P5-1（`set_frame_injection` バッチ API）は実装済み。


| タスク  | 内容                                             | 影響ファイル                        |
| ---- | ---------------------------------------------- | ----------------------------- |
| P5-2 | DrawCommand・メッシュ定義のバイナリ形式（MessagePack / 自前）を検討 | `decode/`, `nif`              |
| P5-3 | `push_render_frame` の decode オーバーヘッド低減         | `render_frame_nif`, `decode/` |
| P5-4 | `get_render_entities` の O(n) コピー削減（差分更新・プール等）  | `read_nif`, `physics`         |


**工数目安**: 5〜12 日  
**参照**: [contents-to-physics-bottlenecks.md](../../architecture/contents-to-physics-bottlenecks.md) セクション 6、[p5-transfer-optimization-design.md](../../architecture/p5-transfer-optimization-design.md)

---

## 3. 課題

### 3.1 シェーダー


| 課題                       | 内容                                                                                                 |
| ------------------------ | -------------------------------------------------------------------------------------------------- |
| **リアルタイム編集 → プレビュー**     | コンテンツ内エディタで WGSL 編集 → Apply → コンパイル結果を即確認する UX                                                     |
| **アセット化・他コンテンツでの再利用**    | ShaderAsset スキーマ設計、名前での参照・ロード機構                                                                    |
| **Phase 1〜2 の実装**        | 既存アーキタイプの body 差し替え → 新アーキタイプ定義可能にする                                                               |
| **Path Traversal 対策の実装** | [shader-path-traversal-design.md](../../architecture/shader-path-traversal-design.md) Phase 1〜2 参照 |


### 3.2 転送・その他


| 課題     | 内容                                                      |
| ------ | ------------------------------------------------------- |
| 転送効率化  | P5-2〜4: バイナリ形式、decode オーバーヘッド低減、get_render_entities 最適化 |
| セキュリティ | 不信頼コンテンツ利用時のサンドボックス化                                    |


---

## 4. 採用しない方針


| 方針                                      | 理由                                                               |
| --------------------------------------- | ---------------------------------------------------------------- |
| **案 B: Rust 側で SoA から DrawCommand を生成** | Rust に描画判断（メッシュ選択・UV 等）を持たせることになり、「Elixir が定義」の原則に反する            |
| **Rust 側でのゲーム固有概念のハードコード**              | `implementation.mdc` の層間インターフェース設計に違反。既存の `spawn_boss` 等の廃止方針と一致 |
| **Phase 3（完全フレックス）の実装**                 | 検討のみ。実装範囲は Phase 2（新アーキタイプ定義可能）までとする                             |


---

## 5. 関連ドキュメント

- [implementation.mdc](../../../.cursor/rules/implementation.mdc) — 保証の原則・層間インターフェース
- [shader-path-traversal-design.md](../../architecture/shader-path-traversal-design.md) — P4-S Path Traversal 対策設計
- [contents-to-physics-bottlenecks.md](../../architecture/contents-to-physics-bottlenecks.md) — ボトルネック・改善案
- [improvement-plan.md](../0_reference/improvement-plan.md) — 全体改善計画
- [Rust: desktop_render](../../architecture/rust/desktop/render.md) — 描画パイプライン現状
- [Rust: nif](../../architecture/rust/nif.md) — NIF インターフェース
- [formula-hardcode-inventory.md](../../architecture/formula-hardcode-inventory.md) — P1-1 ハードコード一覧
- [formula-migration-evaluation.md](../../architecture/formula-migration-evaluation.md) — P1-2 武器式 Formula 移行評価
- [formula-vm-bytecode.md](../../architecture/formula-vm-bytecode.md) — P1-3 Formula VM バイトコード仕様
- [draw-command-spec.md](../../architecture/draw-command-spec.md) — P2-1 DrawCommand タグ・フィールド仕様（SSoT）
- [shader-elixir-interface.md](../../architecture/shader-elixir-interface.md) — P4-2〜5 シェーダー Elixir インターフェース・アセット構成

