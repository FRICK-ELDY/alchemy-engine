# bin 廃止・Mix タスク移行 — 将来対応項目

> 参照: [bin-deprecation-mix-tasks-plan.md](../7_done/bin-deprecation-mix-tasks-plan.md)（本編は完了済み）
>
> 本ドキュメントは、bin 廃止・Mix タスク移行プランで「将来対応時に追加」とされた未実施項目をまとめたものです。

---

## 1. mix alchemy.build の多プラットフォーム対応

### 現状

- `mix alchemy.build` は `-p app` でデスクトップ（Windows/Linux/macOS）向けビルドのみ対応
- オプション: `--release`（デフォルトは debug）、`--desktop`（現状はこれのみ）

### 未実施項目

| オプション | 対象 | 備考 |
|:---|:---|:---|
| `--web` | WebAssembly ビルド | 対応クレート・ビルド設定の追加が必要 |
| `--android` | Android 向けビルド | 対応クレート・ビルド設定の追加が必要 |
| `--ios` | iOS 向けビルド | 対応クレート・ビルド設定の追加が必要 |

各プラットフォーム対応時に、`alchemy.build` タスクへオプションとビルドロジックを追加すること。

---

## 2. その他（任意）

- 過去プラン・政策ドキュメント内の `client_desktop` 表記: 履歴として残す方針のため、無理に置換しない
- 一部のコードコメント（例: render_component.ex）に `client_desktop` が残っている場合、文脈に応じて「app」「デスクトップクライアント」への置換を検討可能
