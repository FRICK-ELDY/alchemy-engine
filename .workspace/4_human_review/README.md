# 4_human_review

## 目的

人間が内容妥当性を確認し、次アクションを決める。

## 入れるもの

- `3_Inprogress` で完了した課題
- レビューに必要な説明、テスト結果、懸念点

## 判定

- `approve`: `6_merging` へ
- `request changes`: `5_rework` へ
- `reject`: `1_backlog` へ戻して再定義

## チェック観点（例）

- 要件適合
- 破壊的変更の有無
- セキュリティ/運用影響

## 次の遷移

判定結果に応じて、以下のいずれかのレーンへ移動する。

- `6_merging`
- `5_rework`
- `1_backlog`
