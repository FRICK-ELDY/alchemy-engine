# AlchemyEngine — 改善提案書

> 最終更新: 2026-03-01  
> 前回評価スコア: +87点（2026-03-01 evaluation）

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
| **総合** | **7/10** | **7/10** |

> Rust 安全性が 8→7 に低下: `spawn_elite_enemy` の脆弱なスロット特定ロジック・`FrameEvent::PlayerDamaged` の u32 オーバーフローリスク・`bench/chase_ai_bench.rs` のコンパイル不可が新たに発見された。  
> テストが 6→5 に低下: `game_nif`・`game_render`・`game_audio` の Rust テストがゼロであることが改めて確認された。

---

## 未解決課題

### I-A: bench/chase_ai_bench.rs のクレート名不一致（優先度: 緊急）

**問題:** ベンチマークが `game_simulation` クレートをインポートしているが、`Cargo.toml` のパッケージ名は `game_physics`。ベンチマークがコンパイルできない状態であり、`bench-regression` CIジョブが機能していない可能性がある。

**影響ファイル:**
- `native/game_physics/benches/chase_ai_bench.rs`（L5-8）

**作業ステップ:**
1. `use game_simulation::` を `use game_physics::` に変更する
2. `cargo bench -p game_physics` でコンパイルを確認する
3. `bench-regression` CIジョブが正常に動作することを確認する

---

### I-B: spawn_elite_enemy の脆弱なスロット特定ロジック（優先度: 高）

**問題:** `spawn` が `free_list` を使ってスロットを再利用する場合、`before_len..after_len` の範囲外のスロットが使われる。`i >= before_len` の条件では `free_list` 再利用スロットを捕捉できず、同じ `kind_id` の既存エネミーが `base_max_hp` と同じ HP を持つ場合、誤って既存エネミーの HP を変更する可能性がある。

**影響ファイル:**
- `native/game_nif/src/nif/action_nif.rs`（L182-194）

**作業ステップ:**
1. `EnemyWorld::spawn` が使用したスロットインデックスを返すよう変更する（`pub fn spawn(...) -> Vec<usize>`）
2. `action_nif.rs` の `spawn_elite_enemy` が返されたインデックスを直接使用するよう変更する
3. テストで `free_list` 再利用ケース（既存エネミーを kill してから spawn）を検証する

---

### I-C: FrameEvent::PlayerDamaged の u32 オーバーフローリスク（優先度: 高）

**問題:** `(damage * 1000.0) as u32` キャストで `damage` が大きい場合（ボスの接触ダメージ等）に `u32` オーバーフローが発生する。Rustの `as u32` キャストは飽和変換ではなく切り捨て変換のため、意図しない結果になる。

**影響ファイル:**
- `native/game_nif/src/nif/events.rs`（L21）

**作業ステップ:**
1. `(damage * 1000.0) as u32` を `(damage * 1000.0).clamp(0.0, u32::MAX as f32) as u32` に変更する
2. 同様のパターンが他の `FrameEvent` 変換にないか確認する

---

### I-D: #[cfg(target_arch = "x86_64")] の pub use 漏れ（優先度: 中）

**問題:** `game_logic/mod.rs` で `update_chase_ai_simd` が非 x86_64 環境でも `pub use` でエクスポートされているが、実際の定義は `#[cfg(target_arch = "x86_64")]` で条件付きのため、ARM/WASMでコンパイルするとリンクエラーになる。

**影響ファイル:**
- `native/game_physics/src/game_logic/mod.rs`（L9）

**作業ステップ:**
1. `pub use chase_ai::update_chase_ai_simd;` を `#[cfg(target_arch = "x86_64")] pub use chase_ai::update_chase_ai_simd;` に変更する
2. ARM/WASM ターゲットでのコンパイルを確認する（`cargo check --target aarch64-unknown-linux-gnu`）

---

### I-E: game_network が実質スタブ（優先度: 高）

**問題:** `game_network.ex` は実装なしのスタブ。「なぜElixir + Rustか」というプロジェクトの価値命題の核心（OTPによる分散・耐障害性）がコードで証明されていない。

**影響ファイル:**
- `apps/game_network/lib/game_network.ex`

**作業ステップ:**
1. `game_network.ex` に `open_room/1`・`close_room/1`・`broadcast/2` 等の公開APIを定義する
2. `libcluster` を追加し、複数ノード間でのルーム管理を実装する
3. ノードクラッシュ時のルーム移行シナリオをテストで検証する

---

### I-F: Elixir 側テストがほぼ未整備（優先度: 中）

**問題:** `GameEngine.SceneManager`・`GameEvents`・`EventBus`・`SaveManager` のテストが存在しない。エンジンコアのリグレッションを検出する手段がない。

**影響ファイル:**
- `apps/game_engine/test/`（存在しない）

**作業ステップ:**
1. `apps/game_engine/test/game_engine/scene_manager_test.exs` を作成し、シーン遷移（push/pop/replace）をテストする
2. `apps/game_engine/test/game_engine/save_manager_test.exs` を作成し、セーブ/ロード・HMAC検証をテストする
3. `apps/game_engine/test/game_engine/event_bus_test.exs` を作成し、サブスクライバー配信をテストする
4. `GameEngine.NifBridgeMock`（`apps/game_engine/test/support/mocks.ex` に既に定義済み）を使ってNIF依存を排除する

---

### I-G: WebSocket 認証・認可が未実装（優先度: 高）

**問題:** `channel.ex` の `join/3` でルームIDの存在確認のみを行い、認証・認可のロジックがない。誰でも任意のルームに参加できる状態。

**影響ファイル:**
- `apps/game_network/lib/game_network/channel.ex`

**作業ステップ:**
1. `Phoenix.Token.sign/3` でサーバーサイドトークンを生成するエンドポイントを追加する
2. `channel.ex` の `join/3` で `Phoenix.Token.verify/4` を使ってトークンを検証する
3. トークンの有効期限・ルームIDのスコープ制限を実装する
4. 認証テストを `game_network_channel_test.exs` に追加する

---

### I-H: EntityParams の Single Source of Truth 化（優先度: 中）

**問題:** `entity_params.ex`・`spawn_component.ex` の `boss_params/0`・Rust側の値の3箇所に同じ値が散在している。

**影響ファイル:**
- `apps/game_content/lib/game_content/entity_params.ex`
- `apps/game_content/lib/game_content/vampire_survivor/spawn_component.ex`

**作業ステップ:**
1. `spawn_component.ex` の `boss_params/0` を削除し、`EntityParams.boss_params/0` を呼び出すよう変更する
2. `EntityParams` が `boss_params/0` を公開APIとして提供するよう整理する
3. Rust側の値が `set_entity_params` NIF経由でのみ設定されることを確認する

---

### I-I: CI の pull_request トリガー追加（優先度: 中）

**問題:** `.github/workflows/ci.yml` が `push` イベントのみをトリガーとしており、PRへの自動チェックが走らない。

**影響ファイル:**
- `.github/workflows/ci.yml`

**作業ステップ:**
1. `on:` セクションに `pull_request: { branches: [main] }` を追加する
2. `concurrency` の `group` を `${{ github.workflow }}-${{ github.ref }}` に変更してPRとpushで独立したキャンセルが動作するようにする

---

### I-J: game_render の build_instances 重複解消（優先度: 低）

**問題:** `renderer/mod.rs` の `update_instances` と `headless.rs` の `build_instances` にほぼ同一のスプライトUV・サイズ計算ロジックが重複している。

**影響ファイル:**
- `native/game_render/src/renderer/mod.rs`（L719-906）
- `native/game_render/src/headless.rs`（L556-715）

**作業ステップ:**
1. スプライト種別ごとのUV・サイズ計算ロジックを `pub(crate) fn build_sprite_instance(...)` として `renderer/mod.rs` に切り出す
2. `headless.rs` の `build_instances` がこの共有関数を呼び出すよう変更する
3. スプライト種別を追加した際に1箇所のみ変更すればよいことをテストで確認する

---

### I-K: Skeleton/Ghost のスプライト実装（優先度: 低）

**問題:** Skeleton と Ghost が Golem と Bat の UV を流用しており、視覚的に区別できない。

**影響ファイル:**
- `native/game_render/src/renderer/mod.rs`（L258-266）

**作業ステップ:**
1. テクスチャアトラスに Skeleton・Ghost 専用のスプライトスロットを確保する
2. `skeleton_anim_uv` と `ghost_anim_uv` を専用UVに変更する
3. TODO コメントを削除する

---

## 完了済みタスク（フェーズ1・1.5）

~~I-G: HUD 型修正~~  
~~I-H: SIMD alive_mask テスト追加~~  
~~I-I: 命名明確化（EnemyWorld.alive を Vec<u8> に変更）~~  
~~I-J: rayon 並列化閾値の定数化（RAYON_THRESHOLD）~~  
~~I-K: lock_metrics の AtomicU64 実装~~  
~~I-L: DirtyCpu スケジューラ指定~~  
~~I-M: ResourceArc GC 連動実装~~  
~~I-N: Ghost・Skeleton の UV に TODO コメント追加~~  
~~I-O: ベンチマーク回帰 CI ジョブ追加~~
