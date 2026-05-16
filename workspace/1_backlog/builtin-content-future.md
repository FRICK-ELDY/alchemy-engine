# 将来: `apps/contents/lib/contents/builtin`

**一言**: コンテンツが増えたとき、組み込み実装（`builtin`）と定義（`content_definitions`）に分けて登録・発見するための予約領域。

## 本ファイルの位置づけ

このメモは、**将来コンテンツ数が爆増したときに備えた対処のため**に置いてある。いまは少数の第一級コンテンツで運用してよいが、増えた段階で「何を組み込みとみなし、どう登録・発見するか」を迷わないように、意図だけ先に固定しておく。

## `content_definitions` との関係

組み込みコンテンツの**実装モジュール**を置く場所として `apps/contents/lib/contents/builtin/` を想定する一方、**定義・記述・一覧**（コンテンツ ID、メタデータ、descriptor 相当など）は `apps/contents/content_definitions` 側と**セットで設計する**前提である。  
（リポジトリにまだパスが無い場合も、将来追加するときの指針としてこの関係を維持する。）

## 方針

`builtin` は**エンジン側で用意する組み込みコンテンツ**（共有シーン・共通デモ・プラットフォーム同梱用など）を置く想定の名前空間である。現時点でディレクトリや `Content.*` モジュールが未配置でもよい。

- **コンテンツ縮小（canvas_test / bullet_hell_3d / formula_test 維持）の削除対象に含めない。**
- **ドキュメントで意図を残す**ことを優先する。実装は別タスクで行う。
- 詳細設計が固まったら、必要に応じて `docs/architecture/overview.md` 等へ 1 節追加する。

## パス（予定）

| 役割 | パス（予定） |
|------|----------------|
| 組み込みコンテンツのコード | `apps/contents/lib/contents/builtin/` |
| コンテンツ定義・記述 | `apps/contents/content_definitions/` |

## 関連

- `workspace/1_backlog/contents-scope-and-nif-removal.md` — 全体スコープ
- `workspace/7_done/contents-three-retain-and-nif-removal-plan.md` — 実施計画（builtin は削除しない）
- `Content.ContentLoader` / `Content.ComponentRegistry`（`apps/contents/lib/contents/*.ex`）— descriptor ベース実行の stub。将来 `content_definitions` と接続する想定の置き場
