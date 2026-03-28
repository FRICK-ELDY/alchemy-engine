# プラン実施ロードマップ

> 最終更新: 2026-03-15  
> 各プランの実施順序・依存関係・状態を整理するマスターロードマップ。

---

## 凡例

| 状態 | 意味 |
|:---|:---|
| **進行中** | 現在作業中または直近で着手予定 |
| **完了** | 全フェーズ完了 |
| **未着手** | これから着手 |
| **保留** | 前提条件待ち・時期未定 |

---

## 実施順序（依存関係順）

### トラック A: Contents アーキテクチャ

| 順序 | ドキュメント | フェーズ | 依存 | 状態 |
|:---:|-------------|----------|------|------|
| 1 | [fix-contents-implementation-procedure](7_done/fix-contents-implementation-procedure.md) | Phase 1〜5（structs → nodes → components → objects） | なし | 完了 |
| 2 | [contents-migration-plan](7_done/contents-migration-plan.md) | Phase 1〜7（既存コンテンツ移行） | 1 の Phase 5 完了後 | 完了 |
| 3 | [contents-components-reorganization-procedure](1_backlog/contents-components-reorganization-procedure.md) | Phase 1〜3 | 1 と並行可能 | 未着手 |
| 4 | [scene-concept-addition-plan](7_done/scene-concept-addition-plan.md) | Phase 1〜3 完了、Phase 4 は reference へ | 2 の Phase 3 以降と整合 | 完了 |

### トラック B: クライアント・サーバー・ネットワーク

| 順序 | ドキュメント | フェーズ | 依存 | 状態 |
|:---:|-------------|----------|------|------|
| 1 | [client-server-separation-procedure](7_done/client-server-separation-procedure.md) | 0〜3 実施済み、4〜5 は [client-server-separation-future](0_reference/client-server-separation-future.md) | なし | 一部完了 |
| 2 | [env-and-serialization-migration-plan](1_backlog/env-and-serialization-migration-plan.md) | 環境変数・Erlang term 化 | B-1 の Phase 1 と整合 | 一部完了（platform-info 実装済み） |
| 3 | [render-thread-offload-plan](1_backlog/render-thread-offload-plan.md) | 1〜3 | B-1 の Phase 2 と並行検討可能 | 未着手 |

### トラック C: 基盤・ツール

| 順序 | ドキュメント | フェーズ | 依存 | 状態 |
|:---:|-------------|----------|------|------|
| 1 | [bin-deprecation-mix-tasks-plan](7_done/bin-deprecation-mix-tasks-plan.md) | 0〜3 | ランチャー安定後 | 完了 |
| 2 | [parameters-types-implementation-procedure](7_done/parameters-types-implementation-procedure.md) | Phase 1 | なし | 完了 |

### トラック D: VR・プラットフォーム

| 順序 | ドキュメント | フェーズ | 依存 | 状態 |
|:---:|-------------|----------|------|------|
| 1 | [vr-test-implementation-procedure](1_backlog/vr-test-implementation-procedure.md) | Phase A〜B | なし | 未着手 |
| 2 | [vr-openxr-loader-path-issue](1_backlog/vr-openxr-loader-path-issue.md) | 1 件 | Steam パス外での OpenXR ローダー問題 | 未着手 |

### 完了済み

| ドキュメント | 備考 |
|-------------|------|
| [platform-info-crate-and-local-user-execution-plan](7_done/platform-info-crate-and-local-user-execution-plan.md) | client_info 作成〜メニュー表示まで全フェーズ完了 |

---

## バックログ（時期未定）

以下は実施時期が未定。前提条件や優先度の見直し後に `2_todo` へ移動する。

| ドキュメント | 備考 |
|-------------|------|
| [upper-layer-infrastructure-plan](1_backlog/upper-layer-infrastructure-plan.md) | vision Phase 3 以降の前提 |
| [asset-cdn-design](1_backlog/asset-cdn-design.md) | CDN・アセット配信 |
| [asset-storage-classification](1_backlog/asset-storage-classification.md) | アセット配置分類 |
| [group-call-canvas-plan](1_backlog/group-call-canvas-plan.md) | 通話 UI・音声統合 |
| [visual-editor-architecture](1_backlog/visual-editor-architecture.md) | ビジュアルエディタ |
| [node-dsl-outlook](1_backlog/node-dsl-outlook.md) | Node DSL 検討（fix-contents Phase 3 以降） |
| [native-restructure-migration-plan](1_backlog/native-restructure-migration-plan.md) | native クレート再構成 |
| [contents-defines-rust-executes](1_backlog/contents-defines-rust-executes.md) | 定義層 vs 実行層の責務（方針・長期） |

---

## 参照ドキュメント（実施時期と無関係）

常に参照する課題一覧・現状整理。実施順序には含めない。

| ドキュメント | 用途 |
|-------------|------|
| [improvement-plan](0_reference/improvement-plan.md) | 課題一覧・優先度・改善方針 |
| [rust-ecs-implementation-status](0_reference/rust-ecs-implementation-status.md) | ECS 実装状況の整理 |
| [game-world-inner-flow](0_reference/game-world-inner-flow.md) | データフロー・ボトルネック整理 |

---

## 更新ルール

1. プランを着手したら、該当行の状態を「進行中」に更新する
2. 全フェーズ完了したら `7_done/` へ移動し、ロードマップの状態を更新する
3. 実施時期が決まった課題は `1_backlog/` から `2_todo/` へ移動する
4. 新規プランはまず `1_backlog/` に配置し、優先度が上がったら `2_todo/` へ移動する
