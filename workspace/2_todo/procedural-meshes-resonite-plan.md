# 実施計画: Resonite 寄せプロシージャルメッシュ（Assets: Procedural Meshes）

> 作成日: 2026-04-07  
> ステータス: 着手前  
> 親計画: [component-node-struct-resonite-node-dsl-plan.md](./component-node-struct-resonite-node-dsl-plan.md)（本書は同ファイルの **フェーズ 2（Component 強化）** の先遣タスクとして位置づける）

---

## 1. 目的

- Resonite Wiki の [Category:Components:Assets:Procedural Meshes](https://wiki.resonite.com/Category:Components:Assets:Procedural_Meshes) を参照 taxonomy とし、**プロシージャルメッシュ生成**を段階的に増やす。
- 現状の `Contents.Components.Category.Procedural.Meshes` 配下（静的ヘルパ中心、**本計画では主に `box.ex`**）を、[Component:BoxMesh](https://wiki.resonite.com/Component:BoxMesh) 等の**フィールド概念に近いパラメータ**で生成できるようにし、**コンテンツ／プレイ状態から値を与えられる**経路を用意する。
- 既存コンテンツ（`BulletHell3D`、`CanvasTest`、`FormulaTest`、`Tetris` 等）の **描画が壊れない**ことを各フェーズの完了条件とする。
- **`grid.ex` / `quad.ex` は本計画のスコープに含めない**（使い方が当初想定と異なるため、**当面は差分を入れない**。Resonite の GridMesh / QuadMesh 寄せや API 整理は別判断まで保留）。

---

## 2. 現状整理

| モジュール | 役割 | 本計画での扱い |
|------------|------|----------------|
| `.../meshes/box.ex` | `mesh_def/0` で単位立方体（辺長 1）固定 | **変更対象**（BoxMesh 寄せの中心） |
| `.../meshes/grid.ex` | `grid_plane/1` で XZ グリッド | **変更しない**（呼び出し側・用途の整理が先） |
| `.../meshes/quad.ex` | `mesh_def/0` でスカイボックス用クリップ空間 Quad | **変更しない**（同上） |

補足（参考のみ・本計画では追記・改修しない）:

- `grid.ex` は Wiki の [GridMesh](https://wiki.resonite.com/Component:GridMesh) 等との対応は**未整理**のまま据え置き。
- `quad.ex` は [QuadMesh](https://wiki.resonite.com/Component:QuadMesh)（ワールド用 Quad）とは**用途が異なる**既知事項として記録のみ。


メッシュは `Content` の `mesh_definitions/0`（`Contents.Behaviour.Content`）経由で `Content.FrameEncoder.encode_frame/5` の第 4 引数に渡され、`Contents.Components.Category.Rendering.Render` が毎フレーム `content.mesh_definitions()` を呼ぶ。**現状コールバックは arity 0 のため、playing_state を直接は参照できない**。

---

## 3. Resonite BoxMesh との対応（第 1 目標）

[Component:BoxMesh](https://wiki.resonite.com/Component:BoxMesh) の Usage フィールドのうち、**本エンジンでまず意味を持たせる**もの:


| Resonite フィールド  | 型（Wiki） | alchemy-engine での扱い（案）                                                          |
| --------------- | ------- | ------------------------------------------------------------------------------- |
| Size            | Float3  | ボックスの各軸スケール（単位立方体に対する倍率）。既定 `{1,1,1}` は現行の unit box と整合                         |
| UVScale         | Float3  | 頂点 UV または頂点色パターンに相当する処理がパイプラインに無ければ、**doc に「将来: UV」**とし、まずは頂点属性の一貫したスケール規則だけ決める |
| ScaleUVWithSize | Bool    | UVScale と Size の連動。UV 未実装なら **no-op または doc のみ**でよい                             |


**あと回し（本計画の初期スコープ外で明示）**

- persistent / UpdateOrder / Enabled — Object・コンポーネントライフサイクル統合後に [fix_contents.md](../../docs/architecture/fix_contents.md) 側で整理。
- OverrideBoundingBox / OverridenBoundingBox — カリング・ピッキング設計後。
- Profile（ColorProfile）— 色空間が定義されたら。
- BakeMesh — 「静的メッシュへ焼き込み」は別タスク。

---

## 4. 「コンテンツ内で編集可能」の意味と実装経路

次の 2 段階で書く。

### 4.1 フェーズ A（短期）— パラメータ化 API と静的既定

- `Box.mesh_def/0` は**後方互換**のため残し、内部で `mesh_def(opts)` に委譲するか、別名 `mesh_def_with/1` を用意する。
- 各 `Content.mesh_definitions/0` で、`playing_state` を読めない間は **モジュール属性・`context_defaults`・定数**から opts を組み立てる（＝「そのコンテンツのソース上で編集」）。
- ドキュメントに Resonite フィールド名との対応表を moduledoc で記載する。

### 4.2 フェーズ B（中期）— playing_state 連動

- `Contents.Behaviour.Content` に **`mesh_definitions(playing_state)` を optional callback として追加**し、`Rendering.Render` で `mesh_definitions/1` があれば state を渡す。無ければ従来どおり `mesh_definitions/0`。
- または `{commands, camera, ui, mesh_definitions}` を `build_frame` の戻りに含める拡張（FrameEncoder・Render の変更幅が大きいため、**optional callback 案を優先**する旨を計画に残す）。

フェーズ B はフェーズ A で API が固まってから着手する。

---

## 5. Grid / Quad（本計画では対象外）

- `apps/contents/lib/components/category/procedural/meshes/grid.ex` および `quad.ex` には**本計画のフェーズでは一切手を入れない**（doc 追記・リネーム・シグネチャ変更も含めない）。
- 将来ワールド用 Quad や GridMesh 相当が必要になった場合は **`grid.ex` / `quad.ex` を改変せず**、新規モジュール（例: `meshes/world_quad.ex`）や別タスクで設計し直す。

---

## 6. 追加メッシュの優先バックログ（Wiki カテゴリより）

[Category:Components:Assets:Procedural Meshes](https://wiki.resonite.com/Category:Components:Assets:Procedural_Meshes) の一覧を参照し、**頂点＋三角形インデックスが既存パイプラインと同形**のものから順に検討する。

推奨順（実装コストと利用頻度のバランス案）:

1. **BoxMesh 強化**（本書の中心）
2. **SphereMesh** / **CylinderMesh** 等（汎用プリミティブ）
3. ワールド用 Quad が必要なら **新規ファイル**で QuadMesh 相当（既存 `quad.ex` はスカイボックス専用のまま触らない）
4. その他（Torus、Ring 等）は需要に応じて

各追加時は **1 コンポーネント＝1 モジュール**（既存の `box.ex` 等の並び）を基本とし、Wiki の `Component:Name` に moduledoc でリンクする。

---

## 7. フェーズとチェックリスト

### フェーズ 0: 調査

- [Procedural Meshes カテゴリ](https://wiki.resonite.com/Category:Components:Assets:Procedural_Meshes) のページ一覧をコピーせず、**実装候補を 5 個程度**に絞ったメモを本ファイルまたは `workspace/1_backlog/` に追記する。
- `Content.FrameEncoder.mesh_def_to_pb/1` が想定する `mesh_def` マップのキー（`:name`, `:vertices`, `:indices`）を再確認する。

### フェーズ 1: BoxMesh 寄せ（API）

- `Size`（および可能なら `UVScale` / `ScaleUVWithSize` の扱い）を受け取る生成 API を実装する。
- 既存の `mesh_def/0` 挙動と一致することをテストまたは doctest で保証する。
- 少なくとも 1 つの Content で opts を変えた `mesh_def` を返せるようにする（フェーズ A の「ソース上編集」でよい）。

### フェーズ 2: optional `mesh_definitions/1`（任意・フェーズ B）

- Behaviour と `Rendering.Render` の分岐実装。
- 1 コンテンツで playing_state にメッシュパラメータを持たせ、フレームごとにメッシュ定義が変わる動作を確認する。

### フェーズ 3: 次のプリミティブ

- 優先バックログの次項（Sphere 等）を 1 件実装し、`mesh_definitions` に登録できるようにする。

---

## 8. 完了条件（全体）

- `mix test`（`apps/contents` 範囲）が通る。
- `mesh_definitions/0` を実装している既存コンテンツで、意図しないメッシュ名変更によるクライアント不整合が出ない（`:name` の互換方針をコメントで固定する）。
- 親計画 [component-node-struct-resonite-node-dsl-plan.md](./component-node-struct-resonite-node-dsl-plan.md) のフェーズ 2 に進む際、**Assets → Procedural** の対応表の 1 行目として本計画の成果（Box 強化＋候補リスト）を参照できる。

---

## 9. 関連リンク（Resonite Wiki）

- [Category:Components:Assets:Procedural Meshes](https://wiki.resonite.com/Category:Components:Assets:Procedural_Meshes)
- [Component:BoxMesh](https://wiki.resonite.com/Component:BoxMesh)
- [Component:GridMesh](https://wiki.resonite.com/Component:GridMesh)（ページ有無は Wiki 側の更新に依存）
- [Component:QuadMesh](https://wiki.resonite.com/Component:QuadMesh)

---

## 10. 関連ドキュメント（リポジトリ内）

- [component-node-struct-resonite-node-dsl-plan.md](./component-node-struct-resonite-node-dsl-plan.md) — 親・全体計画
- [fix_contents.md](../../docs/architecture/fix_contents.md) — Content / メッシュ / 描画の責務

