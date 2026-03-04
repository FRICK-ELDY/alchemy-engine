# AlchemyEngine — 改善提案書

> 最終更新: 2026-03-04  
> 前回評価スコア: +83点（2026-03-04 evaluation）

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
> Rust 安全性 8→7: `spawn_elite_enemy`・`FrameEvent::PlayerDamaged` オーバーフロー・bench コンパイル不可。  
> テスト 6→5: `nif`・`render`・`audio` の Rust テストがゼロ。

---

## 未解決課題

### I-0: bin/ci.bat の完全通過（優先度: 最優先）

**問題:** `bin/ci.bat` がエラーゼロで通過しない。評価ルールの DX 原則「ローカル CI がエラーゼロで通過すること」に違反。README の「品質保証」セクションの記述と実態が乖離している。

**影響:**
- cargo fmt: 複数ファイルでフォーマット差分（native/nif, render 等）
- cargo clippy: input_openxr（未使用変数 `on_event`、不要な mut）、render（too many arguments、needless_range_loop）
- cargo bench: chase_ai_bench.rs の `game_simulation` → `physics` 修正が必要

**作業ステップ:**
1. `cargo fmt --manifest-path native/Cargo.toml --all` で全ファイルをフォーマット
2. input_openxr: 未使用変数の削除・`mut` の除去
3. render: 多引数関数を構造体に集約、needless_range_loop を iterator に置き換え
4. chase_ai_bench.rs: `use game_simulation::` を `use physics::` に変更
5. `bin/ci.bat` を実行し、全ジョブ PASS を確認

---

### I-A: bench/chase_ai_bench.rs のクレート名不一致（優先度: 緊急・I-0 に含む）

**問題:** ベンチマークが `game_simulation` クレートをインポートしているが、`Cargo.toml` のパッケージ名は `physics`。ベンチマークがコンパイルできない状態であり、`bench-regression` CIジョブが機能していない可能性がある。

**影響ファイル:**
- `native/physics/benches/chase_ai_bench.rs`（L5-8）

**作業ステップ:**
1. `use game_simulation::` を `use physics::` に変更する
2. `cargo bench -p physics` でコンパイルを確認する
3. `bench-regression` CIジョブが正常に動作することを確認する

---

### I-B: spawn_elite_enemy の脆弱なスロット特定ロジック（優先度: 高）

**問題:** `spawn` が `free_list` を使ってスロットを再利用する場合、`before_len..after_len` の範囲外のスロットが使われる。`i >= before_len` の条件では `free_list` 再利用スロットを捕捉できず、同じ `kind_id` の既存エネミーが `base_max_hp` と同じ HP を持つ場合、誤って既存エネミーの HP を変更する可能性がある。

**影響ファイル:**
- `native/nif/src/nif/action_nif.rs`（L182-194）

**作業ステップ:**
1. `EnemyWorld::spawn` が使用したスロットインデックスを返すよう変更する（`pub fn spawn(...) -> Vec<usize>`）
2. `action_nif.rs` の `spawn_elite_enemy` が返されたインデックスを直接使用するよう変更する
3. テストで `free_list` 再利用ケース（既存エネミーを kill してから spawn）を検証する

---

### I-C: FrameEvent::PlayerDamaged の u32 オーバーフローリスク（優先度: 高）

**問題:** `(damage * 1000.0) as u32` キャストで `damage` が大きい場合（ボスの接触ダメージ等）に `u32` オーバーフローが発生する。Rustの `as u32` キャストは飽和変換ではなく切り捨て変換のため、意図しない結果になる。

**影響ファイル:**
- `native/nif/src/nif/events.rs`（L21）

**作業ステップ:**
1. `(damage * 1000.0) as u32` を `(damage * 1000.0).clamp(0.0, u32::MAX as f32) as u32` に変更する
2. 同様のパターンが他の `FrameEvent` 変換にないか確認する

---

### I-D: #[cfg(target_arch = "x86_64")] の pub use 漏れ（優先度: 中）

**問題:** `game_logic/mod.rs` で `update_chase_ai_simd` が非 x86_64 環境でも `pub use` でエクスポートされているが、実際の定義は `#[cfg(target_arch = "x86_64")]` で条件付きのため、ARM/WASMでコンパイルするとリンクエラーになる。

**影響ファイル:**
- `native/physics/src/game_logic/mod.rs`（L9）

**作業ステップ:**
1. `pub use chase_ai::update_chase_ai_simd;` を `#[cfg(target_arch = "x86_64")] pub use chase_ai::update_chase_ai_simd;` に変更する
2. ARM/WASM ターゲットでのコンパイルを確認する（`cargo check --target aarch64-unknown-linux-gnu`）

---

### I-E: network が実質スタブ（優先度: 高）

**問題:** `network.ex` は実装なしのスタブ。「なぜElixir + Rustか」というプロジェクトの価値命題の核心（OTPによる分散・耐障害性）がコードで証明されていない。

**影響ファイル:**
- `apps/network/lib/network.ex`

**作業ステップ:**
1. `network.ex` に `open_room/1`・`close_room/1`・`broadcast/2` 等の公開APIを定義する
2. `libcluster` を追加し、複数ノード間でのルーム管理を実装する
3. ノードクラッシュ時のルーム移行シナリオをテストで検証する

---

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

### I-G: WebSocket 認証・認可が未実装（優先度: 高）

**問題:** `channel.ex` の `join/3` でルームIDの存在確認のみを行い、認証・認可のロジックがない。誰でも任意のルームに参加できる状態。

**影響ファイル:**
- `apps/network/lib/network/channel.ex`

**作業ステップ:**
1. `Phoenix.Token.sign/3` でサーバーサイドトークンを生成するエンドポイントを追加する
2. `channel.ex` の `join/3` で `Phoenix.Token.verify/4` を使ってトークンを検証する
3. トークンの有効期限・ルームIDのスコープ制限を実装する
4. 認証テストを `network_channel_test.exs` に追加する

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

### I-I: CI の pull_request トリガー追加（優先度: 中）

**問題:** `.github/workflows/ci.yml` が `push` イベントのみをトリガーとしており、PRへの自動チェックが走らない。

**影響ファイル:**
- `.github/workflows/ci.yml`

**作業ステップ:**
1. `on:` セクションに `pull_request: { branches: [main] }` を追加する
2. `concurrency` の `group` を `${{ github.workflow }}-${{ github.ref }}` に変更してPRとpushで独立したキャンセルが動作するようにする

---

### I-J: render の build_instances 重複解消（優先度: 低）

**問題:** `renderer/mod.rs` の `update_instances` と `headless.rs` の `build_instances` にほぼ同一のスプライトUV・サイズ計算ロジックが重複している。

**影響ファイル:**
- `native/render/src/renderer/mod.rs`（L719-906）
- `native/render/src/headless.rs`（L556-715）

**作業ステップ:**
1. スプライト種別ごとのUV・サイズ計算ロジックを `pub(crate) fn build_sprite_instance(...)` として `renderer/mod.rs` に切り出す
2. `headless.rs` の `build_instances` がこの共有関数を呼び出すよう変更する
3. スプライト種別を追加した際に1箇所のみ変更すればよいことをテストで確認する

---

### I-K: Skeleton/Ghost のスプライト実装（優先度: 低）

**問題:** Skeleton と Ghost が Golem と Bat の UV を流用しており、視覚的に区別できない。

**影響ファイル:**
- `native/render/src/renderer/mod.rs`（L258-266）

**作業ステップ:**
1. テクスチャアトラスに Skeleton・Ghost 専用のスプライトスロットを確保する
2. `skeleton_anim_uv` と `ghost_anim_uv` を専用UVに変更する
3. TODO コメントを削除する

---

### I-L: render_frame_nif.rs の肥大化（優先度: 中）

**問題:** `native/nif/src/nif/render_frame_nif.rs` が DrawCommand・CameraParams・UiComponent の全デコードロジックを1ファイルに集約しており、コンテンツ追加のたびに肥大化する。現時点で634行あり、新しい DrawCommand や UiComponent を追加するたびに同ファイルへの変更が集中する。

**影響ファイル:**
- `native/nif/src/nif/render_frame_nif.rs`

**作業ステップ:**
1. `native/nif/src/nif/decode/` ディレクトリを作成し、以下の3モジュールに分割する
   - `decode/draw_command.rs` — `decode_commands` / `decode_command`
   - `decode/camera.rs` — `decode_camera`
   - `decode/ui_canvas.rs` — `decode_ui_canvas` / `decode_ui_node` / `decode_ui_component` 等
2. `render_frame_nif.rs` は NIF エントリポイント（`push_render_frame`・`create_render_frame_buffer`）のみに絞る
3. 共通ヘルパー（`decode_color`・`atom_str`・`tag_of` 等）は `decode/mod.rs` に集約する

---

## 設計タスク（別ドキュメント）

### D-A: シーン管理を contents へ移行 ✅ 完了

**方針:** 「あらゆる概念を contents に寄せる」。SceneManager / SceneBehaviour を core から contents へ移行する。

**参照:** 残課題・改善候補は [improvement-plan.md](../improvement-plan.md) の「残課題（シーン管理 → contents 移行タスクより）」に統合済み。

**状況:** Phase 1〜6 完了。`Core.SceneManager`・`Core.SceneBehaviour` を削除し、`Contents.SceneStack`・`Contents.SceneBehaviour` に移行済み。

**関連:** I-F（テスト整備）は `Contents.SceneStack` に対するテストとして実施する。

### D-B: GameEvents を contents へ移行（完了済み 2026-03）

**方針:** オプション B（責務分離）を採用。contents に `Contents.GameEvents` / `Contents.GameEvents.Diagnostics` を移行。core の責務を「ループ制御・イベント受信・ContentBehaviour インターフェース」に限定。BatLord 固有ロジックは `on_engine_message/2` 汎用ディスパッチに置き換え済み。

**未解決事項・確認ポイント:** [improvement-plan.md](../improvement-plan.md) の「GameEvents → contents 移行タスクより」を参照。

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
