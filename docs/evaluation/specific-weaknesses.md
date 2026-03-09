# AlchemyEngine — マイナス点 詳細一覧

> 最終更新: 2026-03-07（evaluation-2026-03-07 に基づく）

## 採点基準

| 点数 | 基準 |
|:---:|:---|
| -1 | 改善余地あり。動作はするが設計・品質上の軽微な問題 |
| -2 | 重要な機能・設計の欠如。放置すると将来の拡張を阻害する |
| -3 | 設計上の明確な欠陥。バグ・クラッシュ・性能劣化を引き起こしうる |
| -4 | プロジェクトの価値命題を損なう重大な欠如。説明責任が果たせない |
| -5 | プロジェクトの根幹を揺るがす致命的な欠陥。存在しないに等しい |

---

## apps/core — エンジンコア・OTP設計

### ❌ マイナス点

- **boss_dash_end の専用 handle_info 節（汎用化の余地）** `-1`
  > `handle_info({:boss_dash_end, _}, state)` は `dispatch_to_components(:on_engine_message, [msg, context])` を呼ぶ設計に改善済み。しかし新規エンジンメッセージ種別を追加するたびに `GameEvents` に専用節を追加する必要があり、完全な汎用化には至っていない。
  > 対象ファイル: `apps/contents/lib/contents/game_events.ex`（L343-347）

- **SaveManager の HMAC シークレットがデフォルト値でハードコード** `-2`
  > `hmac_secret/0` のデフォルト値 `"alchemy-engine-save-secret-v1"` が `save_manager.ex` と `config.exs` に公開されており、環境変数未設定時はセーブデータ改ざん検証が実質的に無効化される。本番では `SAVE_HMAC_SECRET` で上書きできるが、強制機構がない。
  > 対象ファイル: `apps/core/lib/core/save_manager.ex`（L187-188）, `config/config.exs`（L52）

- **Contents.SceneStack・GameEvents のテストがゼロ** `-3`
  > シーン遷移・フレームループの中核ロジックが未検証。リファクタリングの安全網が不足している。
  > 対象ファイル: `apps/core/test/`, `apps/contents/test/`

- **セーブ対象データの収集責務が未定義** `-2`
  > `SaveManager.save_session/1` は Rust スナップショットのみ保存。`score`, `kill_count`, `level`, `weapon_levels`, `boss_state` など Elixir 側 Playing state がセーブに含まれない。
  > 対象ファイル: `apps/core/lib/core/save_manager.ex`, `apps/contents/lib/contents/game_events.ex`

---

## apps/contents — コンテンツ実装・ゲームロジック

### ❌ マイナス点

- **EntityParams と SpawnComponent のパラメータ二重管理** `-3`
  > `entity_params.ex` と `spawn_component.ex` の `boss_params/0` に同一の値が独立して定義されており、Rust側にも同じ値が存在する。3箇所に同じ値が散在しており、同期漏れリスクが高い。`entity_params.ex` のモジュールドキュメントにも「定期的に検証すること」と書かれているが未解消。
  > 対象ファイル: `apps/contents/lib/contents/entity_params.ex`, `apps/contents/lib/contents/vampire_survivor/spawn_component.ex`

- **Diagnostics がコンテンツ固有の知識を持っている** `-2`
  > `Contents.GameEvents.Diagnostics.do_log_and_cache/3` が `playing_state` の `:enemies` / `:bullets` キーを直接参照。Rust ECS を使わないコンテンツ向けの補完だが、エンジン層がコンテンツ固有の構造を知っている。
  > 対象ファイル: `apps/contents/lib/contents/game_events/diagnostics.ex`（L58-66）

- **LevelComponent のアイテムドロップロジックの重複** `-2`
  > `on_frame_event({:enemy_killed, ...})` と `on_event({:entity_removed, ...})` の両方でアイテムドロップ処理が実装されており、同一の敵撃破に対して両方が呼ばれる可能性がある。`@drop_magnet_threshold`・`@drop_potion_threshold` が両箇所で使われているが、イベントの対応関係がコードから読み取りにくい。
  > 対象ファイル: `apps/contents/lib/contents/vampire_survivor/level_component.ex`（L30-96）

- **AsteroidArena のテストがゼロ** `-2`
  > contents の9テストファイルは全て VampireSurvivor 向け。`AsteroidArena`・`SplitComponent`・`AsteroidArena.SpawnSystem` 等の動作が未検証。
  > 対象ファイル: `apps/contents/test/`

- **BossComponent が Playing シーンを直接参照** `-1`
  > `BossComponent.on_physics_process/1` が `Content.VampireSurvivor.Scenes.Playing` をハードコード。他コンポーネントは `content.playing_scene()` を使用。コンポーネントの再利用・core 層への移動の障壁。
  > 対象ファイル: `apps/contents/lib/contents/vampire_survivor/boss_component.ex`

- **Enum.find_last/2 回避コメントが不正確** `-1`
  > spawn_system.ex のコメントに「Elixir 1.12 以降で追加されているが undefined エラーが発生する」とあるが、Elixir 1.19 では使えるはず。将来の開発者を混乱させる不正確なコメントが残っている。
  > 対象ファイル: `apps/contents/lib/contents/vampire_survivor/spawn_system.ex`（L60-66）

---

## apps/network — ネットワーク層

### ❌ マイナス点

- **分散ノード間フェイルオーバーが未実装** `-3`
  > Local・Channel・UDP の3トランスポートは実装済みで、OTP隔離テストも存在する。しかし複数 BEAM ノード間のルーム移動・`libcluster` によるクラスタリング・フェイルオーバーシナリオが未実装。「なぜ Elixir + Rust か」の分散面の証明が不十分。
  > 対象ファイル: `apps/network/lib/network.ex`, `apps/network/lib/network/local.ex`

---

## native/network — Zenoh 通信層（Rust）

### ❌ マイナス点

- **network が render に依存しておりアーキテクチャ違反** `-3`
  > `native-restructure-migration-plan.md` §2 の目標依存関係では `NETWORK --> SHARED` のみ。現状 `network` は `render` に依存しており、`NetworkRenderBridge` と `msgpack_decode` が render の型（`RenderFrame`、`RenderBridge`、`DrawCommand` 等）を使用しているため発生。network 層は描画層から独立すべき。解決方針: これら2モジュールを `app` クレートへ移動。
  > 対象ファイル: `native/network/Cargo.toml`, `native/network/src/network_render_bridge.rs`, `native/network/src/msgpack_decode.rs`

---

## native/nif — NIF設計・ブリッジ

### ❌ マイナス点

- **create_world が NifResult でラップされていない** `-1`
  > `create_world()` のみ `ResourceArc<GameWorld>` を直接返している。他 NIF は `NifResult<T>` で統一。将来失敗しうる処理が追加された場合、パニックが BEAM VM クラッシュに直結する。
  > 対象ファイル: `native/nif/src/nif/world_nif.rs`（L27-28）

---

## native/render — 描画パイプライン

### ❌ マイナス点

- **render が nif に依存しておりアーキテクチャ違反** `-3`
  > `native-restructure-migration-plan.md` §2 の目標依存関係では `RENDER --> SHARED` のみ。現状 `render` は `nif` に依存しており、`nif::physics::constants` の背景色定数（`BG_R`、`BG_G`、`BG_B`）を参照しているため発生。描画層はサーバー側 NIF から独立すべき。解決方針: 共有定数を `shared` クレートへ移動。
  > 対象ファイル: `native/render/Cargo.toml`, `native/render/src/headless.rs`, `native/render/src/renderer/mod.rs`

- **build_instances 関数の重複（DRY 違反）** `-3`
  > `renderer/mod.rs` の `update_instances` と `headless.rs` の `build_instances` に、スプライト種別ごとのUV・サイズ計算ロジックがほぼ同一で重複している。スプライト種別追加・変更時に両方の修正が必要で、同期漏れのリスクがある。
  > 対象ファイル: `native/desktop_render/src/renderer/mod.rs`, `native/desktop_render/src/headless.rs`

- **Skeleton/Ghost の UV がプレースホルダー** `-2`
  > `Skeleton` が `Golem` の UV を流用し、`Ghost` が `Bat` の UV を流用している。別エンティティとして存在するにもかかわらず視覚的に区別できない状態。ゲームプレイの完成度を損なっている。
  > 対象ファイル: `native/desktop_render/src/renderer/mod.rs`（該当 UV マッピング）

- **Vertex/VERTICES/INDICES 等の重複定義** `-2`
  > `renderer/mod.rs` と `headless.rs` で同一の構造体・定数が重複定義されている。`pub(crate)` で共有すべき。
  > 対象ファイル: `native/desktop_render/src/renderer/mod.rs`, `native/desktop_render/src/headless.rs`

---

## テスト戦略

### ❌ マイナス点

- **プロパティベーステスト・ファジングが完全に存在しない** `-3`
  > `StreamData` / `ExUnitProperties` / `PropCheck` / `Quixir` の使用がゼロ。Rustのファズターゲットも存在しない。ゲームロジックの境界条件・不変条件の自動検証が未整備。
  > 対象ファイル: `apps/contents/test/`, `native/physics/`

- **nif・render・audio の Rust テストがゼロ** `-3`
  > NIF ブリッジ・描画パイプライン・オーディオの Rust テストが一切存在しない。`headless.rs` が存在するにもかかわらずレンダリングテストが書かれていない。`nif` の `decode_enemy_params` 等のデコードロジックはGPU不要でテスト可能。
  > 対象ファイル: `native/nif/src/`, `native/desktop_render/src/`, `native/audio/src/`

- **E2E テストがゼロ** `-2`
  > ゲームループ全体（開始→プレイ→終了→リトライ）を通したテストが存在しない。`headless.rs` を活用したE2Eテストが可能なはずだが未実装。
  > 対象ファイル: テストディレクトリ全体

---

## 可観測性・デバッグ容易性

### ❌ マイナス点

- **[:game, :session_end] が metrics/0 に未登録** `-2`
  > `diagnostics.ex` で `[:game, :session_end]` イベントが発火されているが、`telemetry.ex` の `metrics/0` に登録されていない。`ConsoleReporter` に表示されず、セッション終了時の統計が可観測性ツールに流れない。
  > 対象ファイル: `apps/core/lib/core/telemetry.ex`, `apps/contents/lib/contents/game_events/diagnostics.ex`

- **:telemetry.attach の呼び出しがゼロ（外部監視ツールへの接続口なし）** `-2`
  > `ConsoleReporter` のみで外部監視ツール（Prometheus・Grafana等）への接続口がない。本番環境でのパフォーマンス監視が `ConsoleReporter` の出力を目視確認するしかない。
  > 対象ファイル: `apps/core/lib/core/telemetry.ex`

- **NIF パニック時のゲームループ再起動ロジックが未実装** `-2`
  > NIF がパニックすると BEAM VM ごと落ちる。`NifResult` で捕捉可能なエラーはあるが、完全な回復フロー（ルーム再起動・状態復元）は未整備。
  > 対象ファイル: `apps/core/`, `apps/contents/lib/contents/game_events.ex`

---

## 変更容易性・保守性

### ❌ マイナス点

- **Stats GenServer の二重集計リスク** `-1`
  > `Stats` は `EventBus.subscribe()` で `{:game_events, events}` を受け取りキル数を集計するが、`record_kill/2`（`handle_cast`）という公開 API も持つ。両方から集計されると二重カウントになる可能性がある。インターフェースが冗長。
  > 対象ファイル: `apps/core/lib/core/stats.ex`（L38-102）

- **lock_metrics.rs の閾値定数が constants.rs に含まれていない** `-1`
  > `READ_WAIT_WARN_US`・`WRITE_WAIT_WARN_US`・`REPORT_INTERVAL_MS` が `lock_metrics.rs` 内にハードコードされており、定数集約の方針と整合していない。
  > 対象ファイル: `native/nif/src/lock_metrics.rs`（L8-16）

---

## 開発者体験（DX）

### ❌ マイナス点

- **CI の pull_request トリガーが未設定** `-2`
  > `.github/workflows/ci.yml` が `push` イベントのみをトリガーとしており、`pull_request:` イベントが未設定。PRへの自動チェックが走らず、PRマージ前の品質保証が機能しない。
  > 対象ファイル: `.github/workflows/ci.yml`

- **bench-regression のローカル実行スクリプトが存在しない** `-1`
  > `bin/ci.bat` がジョブA〜Dと1:1対応しているが、ジョブE（bench-regression）のローカル実行スクリプトが存在しない。ベンチマーク回帰をローカルで確認する手段がない。
  > 対象ファイル: `bin/`

- **README の Contributing セクションがプレースホルダー** `-1`
  > `README.md` の Contributing セクションが「（※チーム開発時のガイドラインや...）」というプレースホルダーのまま。
  > 対象ファイル: `README.md`

- **bin/ci.bat と GitHub CI の clippy スコープの差** `-1`
  > CI yml は `--exclude launcher` で clippy を実行するが、`bin/ci.bat` は launcher を含む workspace 全体で clippy を実行。ローカルで launcher に警告があると ci.bat が失敗し、CI では通る不整合がありうる。
  > 対象ファイル: `bin/ci.bat`（L46）, `.github/workflows/ci.yml`（L37）

---

## ゲームプレイ完成度

### ❌ マイナス点

- **ゲームループの完結性が未確認（E2Eテストなし）** `-2`
  > 開始→プレイ→終了→リトライの全経路が自動テストで検証されていない。ゲームオーバー後のリトライ・スコア表示・セーブデータ反映の動作が手動確認のみに依存している。

- **視覚的完成度（Skeleton/Ghost のスプライト未実装）** `-2`
  > Skeleton と Ghost が Golem と Bat の UV を流用しており、視覚的に区別できない。「遊べるゲーム」としての完成度を損なっている。

---

## セキュリティ・配布可能性

### ❌ マイナス点

- **mix audit / cargo audit の CI 組み込みなし** `-2`
  > 依存クレート・パッケージの脆弱性チェックが CI に含まれていない。`mix_audit` と `cargo audit` が未設定。
  > 対象ファイル: `.github/workflows/ci.yml`

- **ビルド成果物の配布手順が未整備** `-2`
  > Windows/macOS/Linux 向けのインストーラー・パッケージングの手順が存在しない。エンドユーザー向けの配布形態が未定義。
  > 対象ファイル: `README.md`, `docs/`
