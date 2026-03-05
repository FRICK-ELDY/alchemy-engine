# AlchemyEngine — 改善提案書

> 最終更新: 2026-03-05  
> 前回評価スコア: +80点（2026-03-05 evaluation）

---

## スコアカード

| カテゴリ | 前回 | 現在 |
|:---|:---:|:---:|
| Rust 物理演算・SoA 設計 | 9/10 | 9/10 |
| Rust SIMD 最適化 | 9/10 | 9/10 |
| Rust 並行性設計 | 8/10 | 8/10 |
| Rust 安全性 | 8/10 | 7/10 ↓ |
| Elixir OTP 設計 | 8/10 | 8/10 |
| Elixir 耐障害性 | 6/10 | 6/10 |
| Elixir 並行性・分散 | 1/10 | 1/10 |
| Elixir ビヘイビア活用 | 7/10 | 8/10 ↑ |
| アーキテクチャ（ビジョン一致度） | 7/10 | 7/10 |
| テスト | 6/10 | 5/10 ↓ |
| セキュリティ | — | 3/10 |
| 開発者体験（DX） | 7/10 | 5/10 ↓ |
| **総合** | **7/10** | **6/10** ↓ |

> DX が 7→5 に低下: `bin/ci.bat` が cargo fmt / cargo clippy で失敗し、評価ルールの「エラーゼロで通過」前提に違反。README の品質保証記述と実態が乖離。  
> Rust 安全性 8→7: `spawn_elite_enemy`・`FrameEvent::PlayerDamaged` オーバーフロー。  
> テスト 6→5: `nif`・`render`・`audio` の Rust テストがゼロ。

---

## 未解決課題

### I-F: Elixir 側テストがほぼ未整備（優先度: 中）

**問題:** `Contents.SceneStack`・`Core.GameEvents`・`Core.EventBus`・`Core.SaveManager` のテストが存在しない。エンジンコアのリグレッションを検出する手段がない。（※ `Core.SceneManager` は scene-management-to-contents タスクにより `Contents.SceneStack` に移行済み）

**影響ファイル:**
- `apps/core/test/`（存在しない）

**作業ステップ:**
1. `apps/core/test/core/scene_manager_test.exs` を作成し、シーン遷移（push/pop/replace）をテストする
2. `apps/core/test/core/save_manager_test.exs` を作成し、セーブ/ロード・HMAC検証をテストする
3. `apps/core/test/core/event_bus_test.exs` を作成し、サブスクライバー配信をテストする
4. `Core.NifBridgeMock`（`apps/core/test/support/mocks.ex` に既に定義済み）を使ってNIF依存を排除する

---

### I-H: EntityParams の Single Source of Truth 化（優先度: 中）

**問題:** `entity_params.ex`・`spawn_component.ex` の `boss_params/0`・Rust側の値の3箇所に同じ値が散在している。

**影響ファイル:**
- `apps/contents/lib/contents/entity_params.ex`
- `apps/contents/lib/contents/vampire_survivor/spawn_component.ex`

**作業ステップ:**
1. `spawn_component.ex` の `boss_params/0` を削除し、`EntityParams.boss_params/0` を呼び出すよう変更する
2. `EntityParams` が `boss_params/0` を公開APIとして提供するよう整理する
3. Rust側の値が `set_entity_params` NIF経由でのみ設定されることを確認する

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
