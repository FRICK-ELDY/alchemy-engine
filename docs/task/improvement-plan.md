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

### I-LB: FormulaStore.LocalBackend の起動順保証（優先度: 中）

**問題:** `Core.FormulaStore.LocalBackend` は `Server.Application` の children に含まれるが、起動順の依存関係が明文化されていない。`FormulaStore.read_local/2` は LocalBackend が未起動だとクラッシュする。core 単体テストでは setup で起動しているが、本番の起動順が変わった場合の保証がない。

**影響ファイル:**
- `apps/server/lib/server/application.ex`
- `apps/core/lib/core/formula_store.ex`

**作業ステップ:**
1. LocalBackend を Registry・RoomSupervisor より前に起動する起動順の前提をドキュメント化する
2. アーキテクチャドキュメント（例: `docs/architecture/elixir/`）に起動順の依存関係を追記する
3. （任意）起動時に LocalBackend の存在を検証する assert や監視を検討する

---

### I-FB: formula_store_broadcast 接続時の確認 UX とユーザーセキュリティ設定（優先度: 中）

**問題:** `formula_store_broadcast` の MFA による自由度は利点だが、他ルームへの synced データ送信がユーザー知情・同意なく行われるリスクがある。接続時に何が送られるか明示し、ユーザーが許可・拒否を判断できる仕組みが必要である。

**要件（接続時ダイアログ）:**
- **どこに接続するか** — 対象ネットワーク／ルームを表示する
- **何を送るか** — 同期される synced キー（例: score, wave）の内容を表示する
- **許可／拒否** — ユーザーが選択できる
- **毎回確認するか** — チェックボックス。「毎回確認しない」を選択した場合はユーザーのセキュリティ設定に登録し、以後はその設定に従って自動で許可／拒否する

**影響想定:**
- フロントエンド（接続ダイアログ UI）
- ユーザー設定・セキュリティ保存（local または永続ストア）
- `formula_store_broadcast` 呼び出し前に「許可済みか」を参照するフロー

**作業ステップ:**
1. 接続確認ダイアログの仕様（表示項目・文言・遷移）を設計する
2. ユーザーセキュリティ設定の保存形式（例: room_id + 接続先 → allow/deny）を定義する
3. broadcast 実行前に設定を参照するフックを検討する
4. 「毎回確認しない」で登録した設定の編集・削除 UI を用意する

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

### I-RG: Rust 側に残るゲームロジック計算（優先度: 中）

**問題:** 武器数式・弾丸 damage・スコアポップ減衰・描画パラメータ等のゲームロジックが Rust 側に残存している。Elixir = SSoT の原則に沿い、contents へ移行または NIF 注入で SSoT 化する必要がある。

**対応状況（2026-03）:**
- 武器数式（weapon_upgrade_desc）: `Content.VampireSurvivor.WeaponFormulas` を contents に追加。レベルアップカード表示は Elixir で完結。
- `SpawnComponent.weapon_params/0` を public 化し、WeaponFormulas から SSoT として参照。

**残課題:** 詳細は [rust-game-logic-migration.md](../plan/rust-game-logic-migration.md) を参照。

| 課題ID | 内容 | 優先度 |
|:---|:---|:---:|
| R-W1 | weapon.rs 武器数式（physics 側 damage 計算） | 中 |
| R-W2 | 弾丸・当たり判定の damage 注入 | 中 |
| R-R1 | renderer UV・スプライトパラメータ（I-M と同一） | 中 |
| R-E1 | score_popup lifetime 減衰 | 低 |
| R-P1 | PlayerDamaged / SpecialEntityDamaged の dt 乗算 | 低 |

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

### D-C: ゲームロジックを contents に寄せる（Phase 1 完了 2026-03）

**方針:** アーキテクチャ原則「Elixir = SSoT」に沿い、武器数式・スコア計算等のゲームロジックを contents 側に移行する。

**Phase 1 完了（2026-03）:**
- `Content.VampireSurvivor.WeaponFormulas` を新規作成（effective_damage, effective_cooldown, whip_range, aura_radius, chain_count_for_level, weapon_upgrade_descs）
- `SpawnComponent.weapon_params/0` を public 化
- `RenderComponent` のレベルアップモーダルで `get_weapon_upgrade_descs` NIF の代わりに `WeaponFormulas.weapon_upgrade_descs/3` を使用

**残課題:** [rust-game-logic-migration.md](../plan/rust-game-logic-migration.md) の R-W1, R-W2, R-R1 等を参照。

---

## Formula エンジン（Phase 1〜4 完了、Phase 5 以降は課題）

### I-F5: Phase 5 — ビジュアルエディタ（優先度: 低・将来）

**内容:** ProtoFlux のような 3D/2D ノードエディタを実装する。グラフを視覚的に編集し、バイトコード（または FormulaGraph 形式）を出力する。

**参考:**
- ProtoFlux - Resonite Wiki
- ProtoFlux:Add、ProtoFlux:Store 等

**作業ステップ:**
1. エディタの技術選定（Web/ネイティブ/ゲーム内 UI）
2. FormulaGraph の入出力形式との統合設計
3. ノード接続・エッジの UI 設計
4. バイトコード／グラフのエクスポート機能

---

### I-FO: Formula エンジン — オープンな検討事項（優先度: 低）

| 項目 | 内容 |
|:---|:---|
| バイトコード形式 | スタック vs レジスタ、OpCode の詳細 |
| Store の永続化 | Elixir の ETS / Agent と Rust 側の境界 |
| 型システム | f32, i32, bool, vec2 等のサポート範囲 |
| physics_step との統合 | 毎フレームの計算をグラフで表現するか、既存 NIF のままか |
| デバッグ | グラフのトレース、途中値の可視化 |

**関連:** game-world-inner-flow.md、課題19（計算式・アルゴリズムの Rust 実行）

---
