# fix_contents アーキテクチャ — 将来対応項目

> 参照: [fix-contents-implementation-procedure.md](../completed/fix-contents-implementation-procedure.md)（実施済み）
>
> 本ドキュメントは、fix_contents 実施手順書で未実施の項目をまとめたものです。

---

## 1. 現行コード移行（別タスク）

実施手順書では **新規ディレクトリ・モジュールの構築** に限定している。以下は別途「現行コード移行手順」として実施する想定:

- `lib/contents/` 内の既存 Contents の参照先変更
- `apps/core` 配下の `ContentBehaviour` / `Component` との関係整理
- `Contents.SceneBehaviour` の Object 層との統合
- 既存 LocalUserComponent 等の components 層への移行（[contents-components-reorganization-procedure.md](../current/contents-components-reorganization-procedure.md) と整合を取る）

---

## 2. ノード実装（math カテゴリ）

Phase 3 ではディレクトリのみ作成。以下の数学関数ノードは後続で実装する。

- `nodes/category/math/sign.ex`
- `nodes/category/math/cos.ex`
- `nodes/category/math/tan.ex`
- （その他必要に応じて追加）

---

## 関連ドキュメント

- [fix-contents-implementation-procedure.md](../completed/fix-contents-implementation-procedure.md) — 実施済み手順
- [fix_contents.md](../../architecture/fix_contents.md) — アーキテクチャ設計
- [contents-components-reorganization-procedure.md](../current/contents-components-reorganization-procedure.md) — コンポーネント再編成（移行と整合）

