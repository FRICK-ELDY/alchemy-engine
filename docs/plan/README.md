# docs/plan — 実施計画・設計書

> 本ディレクトリはプロジェクトの実施計画・設計書を格納する。  
> **実施時期**に応じてフォルダで分類し、いつ何をやるかを明確にする。

---

## フォルダ構成

| フォルダ | 用途 |
|----------|------|
| **[current/](current/)** | 今やってる／次にやるプラン |
| **[backlog/](backlog/)** | いつやるか未定の将来候補 |
| **[completed/](completed/)** | 全フェーズ完了（参照用） |
| **[reference/](reference/)** | 実施時期と無関係な参照ドキュメント（課題一覧・現状整理など） |

---

## 実施順序

詳細な実施順序・依存関係は **[roadmap.md](roadmap.md)** を参照。

### クイックリファレンス

- **Contents アーキテクチャ**: fix-contents-implementation → contents-migration → scene-concept
- **クライアント・サーバー**: client-server-separation → env-and-serialization, render-thread-offload
- **基盤**: bin-deprecation, parameters-types
- **VR**: vr-test-implementation, vr-openxr-loader-path-issue

---

## 新規プランの追加ルール

1. **新規プラン**はまず `backlog/` に配置する
2. 実施時期が決まったら `current/` へ移動し、[roadmap.md](roadmap.md) に追記する
3. 各ドキュメントの冒頭に以下を記載する（任意）:
   ```markdown
   > 作成日: YYYY-MM-DD
   > 状態: 進行中 | 未着手 | 完了 | 保留
   > 依存: [xxx.md](path) Phase N 完了
   ```

---

## 実施完了時の扱い（マージルール）

**計画よりも上位層（architecture / vision / policy 等）から plan を参照するのは避ける。**

計画の実施が完了したら、その成果は plan に残すのではなく、**計画よりも上位層にマージする**こと。

1. 設計・仕様として確定した内容 → `docs/architecture/` に反映する
2. 方針・ポリシーとして確定した内容 → `docs/policy/` 等に反映する
3. plan 内の `completed/` には「実施履歴・参照用」として残すが、上位層は plan を参照せず、マージ後のドキュメントを参照する
4. 上位層のドキュメントが plan へのリンクを持っている場合は、マージ完了後にそのリンクを削除する

---

## 一覧

### current/（今・次）

| ファイル | 概要 |
|----------|------|
| [contents-migration-plan](current/contents-migration-plan.md) | 既存コンテンツの新アーキテクチャ移行 |
| [contents-components-reorganization-procedure](current/contents-components-reorganization-procedure.md) | コンポーネント再編 |
| [bin-deprecation-mix-tasks-plan](current/bin-deprecation-mix-tasks-plan.md) | bin 廃止・mix tasks 化 |
| [env-and-serialization-migration-plan](current/env-and-serialization-migration-plan.md) | 環境変数・Erlang term シリアライズ |
| [render-thread-offload-plan](current/render-thread-offload-plan.md) | 描画スレッドオフロード |
| [parameters-types-implementation-procedure](current/parameters-types-implementation-procedure.md) | パラメータ型実装 |
| [vr-test-implementation-procedure](current/vr-test-implementation-procedure.md) | VR テスト実装 |
| [vr-openxr-loader-path-issue](current/vr-openxr-loader-path-issue.md) | OpenXR ローダーパス問題 |

### completed/

| ファイル | 概要 |
|----------|------|
| [fix-contents-implementation-procedure](completed/fix-contents-implementation-procedure.md) | structs / nodes / components / objects 骨格実装 ✅ |
| [client-server-separation-procedure](completed/client-server-separation-procedure.md) | クライアント・サーバー分離（フェーズ 0-3 実施済み）✅ |
| [platform-info-crate-and-local-user-execution-plan](completed/platform-info-crate-and-local-user-execution-plan.md) | client_info 作成〜メニュー表示 ✅ |
| [scene-concept-addition-plan](completed/scene-concept-addition-plan.md) | シーン概念の追加 ✅ |

### backlog/

| ファイル | 概要 |
|----------|------|
| [upper-layer-infrastructure-plan](backlog/upper-layer-infrastructure-plan.md) | 上層インフラ（認証・ディスカバリ） |
| [asset-cdn-design](backlog/asset-cdn-design.md) | アセット CDN 設計 |
| [asset-storage-classification](backlog/asset-storage-classification.md) | アセット配置分類 |
| [group-call-canvas-plan](backlog/group-call-canvas-plan.md) | 通話 UI・音声 |
| [visual-editor-architecture](backlog/visual-editor-architecture.md) | ビジュアルエディタ |
| [node-dsl-outlook](backlog/node-dsl-outlook.md) | Node DSL 展望 |
| [native-restructure-migration-plan](backlog/native-restructure-migration-plan.md) | native クレート再構成 |
| [contents-defines-rust-executes](backlog/contents-defines-rust-executes.md) | 定義 vs 実行の責務 |

### reference/

| ファイル | 概要 |
|----------|------|
| [fix-contents-implementation-future](reference/fix-contents-implementation-future.md) | fix_contents 未実施項目（現行コード移行・math ノード） |
| [client-server-separation-future](reference/client-server-separation-future.md) | クライアント・サーバー分離 未実施項目（フェーズ 4-5） |
| [scene-concept-phase4-future](reference/scene-concept-phase4-future.md) | Scene 概念 将来拡張の検討（Phase 4） |
| [improvement-plan](reference/improvement-plan.md) | 課題一覧・改善方針 |
| [rust-ecs-implementation-status](reference/rust-ecs-implementation-status.md) | ECS 実装状況 |
| [game-world-inner-flow](reference/game-world-inner-flow.md) | データフロー整理 |
