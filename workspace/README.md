# workspace

このディレクトリは、タスクの状態遷移を管理するためのワークスペースです。

## レーン構成

- `1_backlog`: まだ着手準備が整っていない課題
- `2_todo`: 着手可能な課題
- `3_Inprogress`: 実装中（主にエージェントが処理）
- `4_human_review`: 人間レビュー待ち
- `5_rework`: レビュー差し戻し後の再作業
- `6_merging`: マージ最終判断
- `7_done`: 完了

## 推奨フロー

`1_backlog -> 2_todo -> 3_Inprogress -> 4_human_review -> (5_rework -> 3_Inprogress)* -> 6_merging -> 7_done`

## 運用ルール（最小）

- 人間が担当するのは `4_human_review` と `6_merging` を基本とする
- 差し戻し時は `5_rework` に修正要求を明文化して渡す
- 各タスクは1つのディレクトリにのみ存在させる（重複配置しない）
