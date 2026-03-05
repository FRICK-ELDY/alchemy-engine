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
