# 実施計画: Component / Node / Struct 強化、Resonite 寄せ、Node DSL

> 作成日: 2026-04-07  
> ステータス: 着手前（Definition of Ready 満たしたら `3_Inprogress` へ）

---

## 1. 目的

- **Struct** を値型・時刻・空間表現の土台として拡張し、Node / Component 双方が同じ型語彙を共有できるようにする。
- **Component**（`apps/contents/lib/components/`）を、[Resonite Wiki のコンポーネントカテゴリ](https://wiki.resonite.com/Category:Components) を**参照 taxonomy**として、不足領域を優先度付きで追加・整理する。
- **Node**（`apps/contents/lib/nodes/`）を、[Resonite Wiki の ProtoFlux カテゴリ](https://wiki.resonite.com/Category:ProtoFlux) を**参照 taxonomy**として、グラフ実行・検証を段階的に広げる。
- **Node DSL** は [node-dsl-outlook.md](../1_backlog/node-dsl-outlook.md) の方針どおり、手実装でパターンが見えてから段階導入する（いきなり DSL 設計から入らない）。

---

## 2. 前提・非目標

### 2.1 前提

- アーキテクチャの全体像は [fix_contents.md](../../docs/architecture/fix_contents.md)（Node-Port-Link、Component とシーンの関係）に従う。
- 定義層と実行層の分離方針は [contents-defines-rust-executes.md](../1_backlog/contents-defines-rust-executes.md) を参照する。
- 現行の検証コンテンツは `Content.FormulaTest`（`Contents.Nodes`）を中心に据え、追加ノード・型は**テスト可能な単位**で入れる。

### 2.2 非目標（この計画で明示的にやらないこと）

- Resonite / FrooxEngine との**バイナリ互換・API 完全一致**の再現。
- ProtoFlux の**全ノード網羅**（カテゴリ数・ページ数が多いため、インベントリと優先度付けのみ計画に含め、実装はサブセット）。
- Node DSL の**初日からのフルスコープ実装**（見通しドキュメントのタイミング表に従う）。

---

## 3. Resonite Wiki の使い方（本リポジトリでの解釈）

| 参照元 | 役割 |
|--------|------|
| [Category:Components](https://wiki.resonite.com/Category:Components) | `Contents.Components.Category.*` の**フォルダ名・モジュール階層・「次に足すコンポーネント候補」**のヒント。サブカテゴリ一覧の参照元とする。 |
| [Category:ProtoFlux](https://wiki.resonite.com/Category:ProtoFlux) | `Contents.Nodes.Category.*` の**ノード群の分類・命名・優先バックログ**。Actions / Operators / Flow / Math 等の表をそのまま実装リストにはせず、依存の少ないものから選ぶ。 |

**マッピング記録の置き場所（推奨）**: 本計画のフェーズ 0 で `workspace/1_backlog/` に短いインベントリ MD を切るか、本書に追記する。コード内コメントは「Resonite の（カテゴリ名）に相当」程度に留め、長文はドキュメント側へ。

---

## 4. 現行コードの基準点（計画の起点）

| 層 | おもなパス | 備考 |
|----|------------|------|
| Structs | `apps/contents/lib/structs/category/**` | Value / Text / Time / Space / Users 等 |
| Components | `apps/contents/lib/components/category/**` | Device, Rendering, UI, Shader, Procedural 等 |
| Nodes | `apps/contents/lib/nodes/**` | Operators, Flow, Core/input, Actions, Time 等 |

---

## 5. フェーズ構成

### フェーズ 0: インベントリと優先度（着手前チェックリスト）

- [ ] Resonite [Category:Components](https://wiki.resonite.com/Category:Components) の**サブカテゴリ一覧**と、既存 `Contents.Components.Category.*` の**対応表**（1 行 1 カテゴリでよい）を作成する。
- [ ] Resonite [ProtoFlux](https://wiki.resonite.com/Category:ProtoFlux) の**メインカテゴリ**と、既存 `Contents.Nodes.Category.*` の**対応表**を作成する。
- [ ] **次の 3 スプリント分**の候補を選定する基準を書く（例: FormulaTest で検証できる、既存 Struct だけで完結、描画パイプライン変更が最小）。
- [ ] `mix test`（`apps/contents` 関連）が緑であることを確認する。

**フェーズ 0 完了条件**: 上記表と選定基準がリポジトリ内にあり、チーム（または実施者）が「次に何を実装するか」で迷わない状態。

---

### フェーズ 1: Struct 強化（Node / Component の共通型）

- [ ] ProtoFlux の **Operators / Math / Colors / Time** で頻出しそうな型のうち、未実装のものをリストアップする（例: ベクトル・矩形・列挙の扱いはエンジン方針に合わせて決定）。
- [ ] 既存ノード（`equals`, 算術系, `stopwatch` 等）が参照する型との**整合**（命名、`@type` / `@spec`）を取る。
- [ ] 新規 Struct は **ドキュメント 1 段落 + 単体テスト方針**（既存 structs テストパターンに合わせる）を満たす。

**フェーズ 1 完了条件**: 選んだ型が Node または Component の実装タスクで実際に参照され、コンパイルと関連テストが通る。

---

### フェーズ 2: Component 強化（Resonite Components 寄せ）

- [ ] フェーズ 0 の表に基づき、**1 カテゴリあたり 1〜2 コンポーネント**から着手する（例: Transform / Rendering / UI は既存が多いため「ギャップ」から）。
- [ ] 各コンポーネントに **moduledoc** で「Resonite のどのカテゴリ思想に近いか」を 1 文で記載する（完全一致を主張しない）。
- [ ] `Content.*` の `components/0` に載せるかは**検証用コンテンツで必要なもののみ**に限定し、デフォルト負荷を増やさない。

**フェーズ 2 完了条件**: 少なくとも 1 コンテンツで新規または拡張コンポーネントが実行パスに乗り、手動または自動で振る舞いが確認できる。

---

### フェーズ 3: Node 強化（ProtoFlux 寄せ）

- [ ] [Category:ProtoFlux](https://wiki.resonite.com/Category:ProtoFlux) のサブカテゴリから、**依存が少ない**ものを選ぶ（例: Operators, Flow の一部, Core の display/value 周辺）。
- [ ] 各ノードは既存の **Port / Link / Behaviour** パターンに合わせ、`Content.FormulaTest`（または専用小コンテンツ）で**実行結果が検証できる**ようにする。
- [ ] **Experimental** 相当はフラグまたは別 namespace で隔離する方針を決めてから実装する（任意だが推奨）。

**フェーズ 3 完了条件**: 追加ノードがグラフ上で利用され、回帰テストが更新されている。

---

### フェーズ 4: Node DSL（node-dsl-outlook に沿った段階導入）

[node-dsl-outlook.md](../1_backlog/node-dsl-outlook.md) の段階に従う。

- [ ] **4a**: 代表ノード（例: add, write, call, value, display）の手実装が揃い、Port 宣言の重複が可視化されていることを確認する。
- [ ] **4b（Outlook Phase 1）**: Port 宣言のみ DSL 化する PoC（スコープは outlook §4.1 に従い抑える）。
- [ ] **4c（Outlook Phase 2）**: `handle_pulse` / `handle_sample` の雛形生成。
- [ ] **4d（Outlook Phase 3）**: シリアライズ用スキーマ導出が必要になった時点で検討・実施。

**フェーズ 4 完了条件**: 各サブフェーズごとに `mix test` 通過と、既存 FormulaTest（または後継検証）での動作確認。

---

## 6. テスト・検証観点

- **自動**: `mix test`（変更したアプリ範囲）。Node 追加時は `apps/contents/test` にグラフまたはノード単体のテストを追加する。
- **手動**: `Content.FormulaTest` の HUD 表示、および該当する場合は `CanvasTest` / `BulletHell3D` の入力・描画。
- **回帰**: Component リストやシーン初期化の変更後、コンテンツ起動設定（`config` / `Core.Config`）の参照切れがないこと。

---

## 7. 関連ドキュメント

- [node-dsl-outlook.md](../1_backlog/node-dsl-outlook.md) — Node DSL の見通し・導入タイミング
- [contents-defines-rust-executes.md](../1_backlog/contents-defines-rust-executes.md) — 定義層と実行層
- [fix_contents.md](../../docs/architecture/fix_contents.md) — fix_contents アーキテクチャ
- Resonite Wiki: [Category:Components](https://wiki.resonite.com/Category:Components)、[Category:ProtoFlux](https://wiki.resonite.com/Category:ProtoFlux)
- [procedural-meshes-resonite-plan.md](./procedural-meshes-resonite-plan.md) — **Assets: Procedural Meshes** 先行（親計画フェーズ 2 の先遣）

---

## 8. 次のアクション

1. フェーズ 0 の表を埋める（担当者を決める）。  
2. フェーズ 1 で追加する Struct を 2〜3 個に絞って Issue または `3_Inprogress` 用タスクに落とす。  
3. Component / Node の並行実装は**同じスプリント内で型の依存が循環しない**組み合わせに限定する。
