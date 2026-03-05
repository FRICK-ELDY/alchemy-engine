# AlchemyEngine — 改善提案書

> 最終更新: 2026-03-06  
> 前回評価スコア: +102点（2026-03-06 evaluation、前回 +80 → +22 改善）

---

## スコアカード

| カテゴリ | 2026-03-05 | 2026-03-06 |
|:---|:---:|:---:|
| Rust 物理演算・SoA 設計 | 9/10 | 9/10 |
| Rust SIMD 最適化 | 9/10 | 9/10 |
| Rust 並行性設計 | 8/10 | 8/10 |
| Rust 安全性 | 7/10 | 8/10 ↑ |
| Rust プラットフォーム対応 | — | 8/10 |
| Elixir OTP 設計 | 8/10 | 8/10 |
| Elixir 耐障害性 | 6/10 | 6/10 |
| Elixir 並行性・分散 | 1/10 | 2/10 ↑ |
| Elixir ビヘイビア活用 | 8/10 | 8/10 |
| アーキテクチャ（ビジョン一致度） | 7/10 | 7/10 |
| テスト | 5/10 | 6/10 ↑ |
| セキュリティ | 3/10 | 3/10 |
| 開発者体験（DX） | 5/10 | 6/10 ↑ |
| **総合** | **6/10** | **7/10** ↑ |

> **改善済み（2026-03-06）**:  
> - Rust 安全性: `spawn_elite_enemy` の spawn 返却値使用・`PlayerDamaged` の clamp 実装  
> - テスト: EventBus・SaveManager のテスト追加、chase_ai_bench クレート参照修正  
> - 並行性・分散: Network.DistributedTest による移行シナリオ検証  
> - DX: bin/ci.bat のローカルエラーゼロ通過を確認済み  
> - Rust プラットフォーム: `update_chase_ai_simd` の pub use に `#[cfg(target_arch = "x86_64")]` 付与（非 x86_64 でリンクエラー回避）
> **残課題**: SceneStack・GameEvents のテスト、pull_request トリガー

---

## 未解決課題

### I-F: Contents.SceneStack・GameEvents のテスト整備（優先度: 高）

**問題:** シーン遷移・フレームループの中核ロジック（`Contents.SceneStack`・`Contents.GameEvents`）に対するテストが存在しない。リファクタリングの安全網が不足している。

**影響ファイル:**
- `apps/contents/lib/contents/scene_stack.ex`
- `apps/contents/lib/contents/game_events.ex`

**作業ステップ:**
1. `NifBridgeMock`（Mox）を使い NIF 依存なしに `SceneStack` のシーン遷移をテストする
2. `GameEvents` のフレームループ・バックプレッシャー設計をユニットテストで検証する
3. `async: true` が使える範囲で並列実行可能なテストに設計する

---

### I-M: renderer/mod.rs のゲーム固有パラメータを contents へ移行（優先度: 中）

**問題:** `native/render/src/renderer/mod.rs` に、アトラスオフセット・敵種別サイズ・スプライト種別の UV 計算など、多数のゲーム固有パラメータがハードコードされている。アーキテクチャ原則「Elixir = SSoT」「Rust = 演算層」に照らすと、これらの値は contents 側で持ち、NIF 経由で注入するべきである。

**影響ファイル:**
- `native/render/src/renderer/mod.rs`（アトラス定数・`enemy_sprite_size`・`enemy_anim_uv`・`sprite_instance_from_command` 等）

**作業ステップ:**
1. contents にスプライトパラメータ（UV 座標・サイズ・kind_id マッピング等）の SSoT を定義する
2. NIF で `DrawCommand` に加え、パラメータ（UV・サイズ）を Elixir から渡せるようにする
3. renderer 側は汎用的な「kind_id → パラメータ」の lookup のみ行い、値をハードコードしない
4. 既存の挙動を変えずに段階的に移行する

---

## 設計タスク（別ドキュメント）

### D-A: シーン管理を contents へ移行 ✅ 完了

**方針:** 「あらゆる概念を contents に寄せる」。SceneManager / SceneBehaviour を core から contents へ移行する。

**参照:** 残課題・改善候補は [improvement-plan.md](../plan/improvement-plan.md) の「残課題（シーン管理 → contents 移行タスクより）」に統合済み。

**状況:** Phase 1〜6 完了。`Core.SceneManager`・`Core.SceneBehaviour` を削除し、`Contents.SceneStack`・`Contents.SceneBehaviour` に移行済み。

**関連:** I-F（テスト整備）は `Contents.SceneStack` に対するテストとして実施する。

### D-B: GameEvents を contents へ移行（完了済み 2026-03）

**方針:** オプション B（責務分離）を採用。contents に `Contents.GameEvents` / `Contents.GameEvents.Diagnostics` を移行。core の責務を「ループ制御・イベント受信・ContentBehaviour インターフェース」に限定。BatLord 固有ロジックは `on_engine_message/2` 汎用ディスパッチに置き換え済み。

**未解決事項・確認ポイント:** [improvement-plan.md](../plan/improvement-plan.md) の「GameEvents → contents 移行タスクより」を参照。

---
