# AlchemyEngine — マイナス点 詳細一覧

## 採点基準

| 点数 | 基準 |
|:---:|:---|
| -1 | 改善余地あり。動作はするが設計・品質上の軽微な問題 |
| -2 | 重要な機能・設計の欠如。放置すると将来の拡張を阻害する |
| -3 | 設計上の明確な欠陥。バグ・クラッシュ・性能劣化を引き起こしうる |
| -4 | プロジェクトの価値命題を損なう重大な欠如。説明責任が果たせない |
| -5 | プロジェクトの根幹を揺るがす致命的な欠陥。存在しないに等しい |

---

## apps/game_engine — エンジンコア・OTP設計

### ❌ マイナス点

- **SceneManager がシングルトン（マルチルーム非対応）** `-3`
  > `SceneManager` がモジュール名で登録されるシングルトンであり `room_id` を持たない。`GameEvents` はマルチルーム対応（`room_id` を持つ）だが、シーン状態は全ルームで共有される。`game_events.ex` L207-214 で `:main` 以外のルームはシーン処理をスキップする実装になっており、マルチルーム対応を本格化する際には `SceneManager` のルーム分離が必要。ネットワーク層でマルチルームを謳いながらエンジンコアがシングルトンである矛盾が設計上の欠陥。
  > 対象ファイル: `apps/game_engine/lib/game_engine/scene_manager.ex`（L11）

- **GameEvents に BatLord 固有ロジックが漏出** `-2`
  > エンジンコアである `GameEvents` の `handle_info` に `{:boss_dash_end, world_ref}` というBatLord固有のメッセージ処理が実装されている。実装ルールの「エンジンはディスパッチのみ行う」に違反しており、コンテンツを追加するたびにエンジンコアを変更するリスクがある。`BossComponent.on_physics_process` が `GameEvents` プロセスに `Process.send_after` しているため、構造的に回避が難しい状態になっている。
  > 対象ファイル: `apps/game_engine/lib/game_engine/game_events.ex`（L180-187）

- **SaveManager の HMAC シークレットがデフォルト値でハードコード** `-2`
  > `hmac_secret/0` のデフォルト値 `"alchemy-engine-save-secret-v1"` がソースコードに公開されており、セーブデータの改ざん検証が実質的に無効化されている。本番環境で環境変数等で上書きしなければ全ユーザーのセーブデータが改ざん可能。強制機構がない。
  > 対象ファイル: `apps/game_engine/lib/game_engine/save_manager.ex`（L162）

- **GameEngine.SceneManager・GameEvents・EventBus・SaveManager のテストがゼロ** `-4`
  > エンジンコアの中核モジュール群（`SceneManager`・`GameEvents`・`EventBus`・`SaveManager`・`StressMonitor`・`Stats`）に対するテストが一切存在しない。`improvement-plan.md` でも自己認識されているが、エンジンコアのリグレッションを検出する手段がなく、リファクタリングの安全網がない。
  > 対象ファイル: `apps/game_engine/test/`（存在しない）

---

## apps/game_content — コンテンツ実装・ゲームロジック

### ❌ マイナス点

- **EntityParams と SpawnComponent のパラメータ二重管理** `-3`
  > `entity_params.ex` と `spawn_component.ex` の `boss_params/0` に同一の値（SlimeKing の `max_hp: 1000.0`・`special_interval: 5.0` 等）が独立して定義されている。さらにRust側にも同じ値が存在し、**3箇所に同じ値が散在**している。どれかを変更した際の同期漏れリスクが高く、`entity_params.ex` のモジュールドキュメントにも「定期的に検証すること」と書かれており、問題を自己認識しながら解消されていない。
  > 対象ファイル: `apps/game_content/lib/game_content/entity_params.ex`, `apps/game_content/lib/game_content/vampire_survivor/spawn_component.ex`

- **LevelComponent のアイテムドロップロジックの重複** `-2`
  > `on_frame_event({:enemy_killed, ...})` と `on_event({:entity_removed, ...})` の両方でアイテムドロップ処理が実装されており、同一の敵撃破に対して両方が呼ばれる可能性がある。`@drop_magnet_threshold 2`・`@drop_potion_threshold 7` が両箇所で使われているが、これらが同一イベントを指すのか別イベントなのかがコードから読み取りにくい。
  > 対象ファイル: `apps/game_content/lib/game_content/vampire_survivor/level_component.ex`（L30-96）

- **AsteroidArena のテストがゼロ** `-2`
  > `game_content` の7テストファイルは全て `VampireSurvivor` 向けであり、`AsteroidArena` に対するテストが一切存在しない。`SplitComponent`・`AsteroidArena.SpawnSystem` 等の動作が未検証。
  > 対象ファイル: `apps/game_content/test/`

- **Enum.find_last/2 回避コメントが不正確** `-1`
  > `spawn_system.ex` と `asteroid_arena/spawn_system.ex` の `Enum.find_last/2` 回避コメントに「Elixir 1.12 以降で追加されているが undefined エラーが発生する」と書かれているが、Elixir 1.19 では使えるはず。将来の開発者を混乱させる不正確なコメントが残っている。
  > 対象ファイル: `apps/game_content/lib/game_content/vampire_survivor/spawn_system.ex`（L60-66）

---

## apps/game_network — ネットワーク層

### ❌ マイナス点

- **game_network が実質スタブ（Elixir選択の最大の根拠が未証明）** `-4`
  > `improvement-plan.md` の I-E で自己認識されているが、`game_network.ex` は実装なしのスタブ。「なぜElixir + Rustか」というプロジェクトの価値命題の核心（OTPによる分散・耐障害性）がコードで証明されていない。WebSocket・UDP・Localの3トランスポートは実装されているが、実際のマルチルーム分散シナリオ（複数ノード間のルーム移動・フェイルオーバー）が未実装。
  > 対象ファイル: `apps/game_network/lib/game_network.ex`

- **WebSocket 認証・認可が未実装** `-3`
  > `channel.ex` の `join/3` でルームIDの存在確認のみを行い、認証・認可のロジックがない。誰でも任意のルームに参加できる状態。`save_manager.ex` の HMAC と同様、セキュリティ設計が未完成。
  > 対象ファイル: `apps/game_network/lib/game_network/channel.ex`

---

## native/game_physics — ECS・SoA・SIMD

### ❌ マイナス点

- **bench/chase_ai_bench.rs のクレート名不一致（コンパイル不可）** `-3`
  > ベンチマークが `game_simulation` クレートをインポートしているが、`Cargo.toml` のパッケージ名は `game_physics`。ベンチマークがコンパイルできない状態であり、`bench-regression` CIジョブが実際には機能していない可能性がある。
  > 対象ファイル: `native/game_physics/benches/chase_ai_bench.rs`（L5-8）

- **spawn_elite_enemy の脆弱なスロット特定ロジック** `-3`
  > `spawn` が `free_list` を使ってスロットを再利用する場合、`before_len..after_len` の範囲外のスロットが使われる。`i >= before_len` の条件では `free_list` 再利用スロットを捕捉できず、同じ `kind_id` の既存エネミーが `base_max_hp` と同じ HP を持つ場合、誤って既存エネミーの HP を変更する可能性がある。
  > 対象ファイル: `native/game_nif/src/nif/action_nif.rs`（L182-194）

- **FrameEvent::PlayerDamaged の固定小数点変換でu32オーバーフローリスク** `-2`
  > `(damage * 1000.0) as u32` キャストで `damage` が大きい場合（ボスの接触ダメージ等）に `u32` オーバーフローが発生する。Rustの `as u32` キャストは飽和変換ではなく切り捨て変換のため、意図しない結果になる。`(damage * 1000.0).min(u32::MAX as f32) as u32` が安全。
  > 対象ファイル: `native/game_nif/src/nif/events.rs`（L21）

- **#[cfg(target_arch = "x86_64")] の pub use 漏れ（非x86_64でリンクエラー）** `-2`
  > `game_logic/mod.rs` で `update_chase_ai_simd` が非 x86_64 環境でも `pub use` でエクスポートされているが、実際の定義は `#[cfg(target_arch = "x86_64")]` で条件付きのため、ARM/WASM でコンパイルするとリンクエラーになる。
  > 対象ファイル: `native/game_physics/src/game_logic/mod.rs`（L9）

---

## native/game_render — 描画パイプライン

### ❌ マイナス点

- **build_instances 関数の重複（DRY 違反）** `-3`
  > `renderer/mod.rs` の `update_instances` メソッドと `headless.rs` の `build_instances` 関数に、スプライト種別ごとのUV・サイズ計算ロジックがほぼ同一の内容で重複している。スプライト種別を追加・変更した際に両方の修正が必要で、同期漏れのリスクがある。`headless.rs` のコメントに「共有の `pub(crate)` 関数を使用」と書いてあるが実際には共有されていない。
  > 対象ファイル: `native/game_render/src/renderer/mod.rs`（L719-906）, `native/game_render/src/headless.rs`（L556-715）

- **Skeleton/Ghost の UV がプレースホルダー（視覚的に区別不可）** `-2`
  > `Skeleton` が `Golem` の UV を流用し、`Ghost` が `Bat` の UV を流用している。別エンティティとして存在するにもかかわらず視覚的に区別できない状態。TODO コメントが残っており、ゲームプレイの完成度を損なっている。
  > 対象ファイル: `native/game_render/src/renderer/mod.rs`（L258-266）

- **Vertex/VERTICES/INDICES/ScreenUniform/CameraUniform の重複定義** `-2`
  > `renderer/mod.rs` と `headless.rs` で同一の構造体・定数が重複定義されている。`pub(crate)` で共有すべき。
  > 対象ファイル: `native/game_render/src/renderer/mod.rs`, `native/game_render/src/headless.rs`

---

## テスト戦略

### ❌ マイナス点

- **プロパティベーステスト・ファジングが完全に存在しない** `-3`
  > `StreamData` / `ExUnitProperties` / `PropCheck` / `Quixir` の使用がゼロ。`entity_params_test.exs` の `score_from_exp` テストで「単調増加」を手動の固定値リストで検証しているが、プロパティテストではない。Rustのファズターゲットも存在しない。ゲームロジックの境界条件・不変条件の自動検証が未整備。
  > 対象ファイル: `apps/game_content/test/`, `native/game_physics/`

- **game_nif・game_render・game_audio の Rust テストがゼロ** `-3`
  > NIF ブリッジ・描画パイプライン・オーディオの Rust テストが一切存在しない。「GPU・音声デバイスが必要なため除外」という理由があるが、`headless.rs` が存在するにもかかわらずレンダリングテストが書かれていない。`game_nif` の `decode_enemy_params` 等のデコードロジックはGPU不要でテスト可能。
  > 対象ファイル: `native/game_nif/src/`, `native/game_render/src/`, `native/game_audio/src/`

- **E2E テストがゼロ** `-2`
  > ゲームループ全体（開始→プレイ→終了→リトライ）を通したテストが存在しない。`headless.rs` のヘッドレスレンダラーを活用したE2Eテストが可能なはずだが未実装。
  > 対象ファイル: テストディレクトリ全体

---

## 可観測性・デバッグ容易性

### ❌ マイナス点

- **[:game, :session_end] が metrics/0 に未登録** `-2`
  > `diagnostics.ex` で `[:game, :session_end]` イベントが発火されているが、`telemetry.ex` の `metrics/0` に登録されていない。`ConsoleReporter` に表示されず、セッション終了時の統計（経過時間・スコア）が可観測性ツールに流れない。
  > 対象ファイル: `apps/game_engine/lib/game_engine/telemetry.ex`

- **:telemetry.attach の呼び出しがゼロ（外部監視ツールへの接続口なし）** `-2`
  > `ConsoleReporter` のみで外部監視ツール（Prometheus・Grafana等）への接続口がない。本番環境でのパフォーマンス監視が `ConsoleReporter` の出力を目視確認するしかない。
  > 対象ファイル: `apps/game_engine/lib/game_engine/telemetry.ex`

---

## 変更容易性・保守性

### ❌ マイナス点

- **Stats GenServer の二重集計リスク** `-1`
  > `Stats` は `EventBus.subscribe()` で `{:game_events, events}` を受け取りキル数を集計するが、`record_kill/2`（`handle_cast`）という公開 API も持つ。両方から集計されると二重カウントになる可能性がある。インターフェースが冗長。
  > 対象ファイル: `apps/game_engine/lib/game_engine/stats.ex`（L38-102）

- **lock_metrics.rs の閾値定数が constants.rs に含まれていない** `-1`
  > `READ_WAIT_WARN_US: 300`・`WRITE_WAIT_WARN_US: 500`・`REPORT_INTERVAL_MS: 5000` が `lock_metrics.rs` 内にハードコードされており、`constants.rs` に含まれていない。
  > 対象ファイル: `native/game_nif/src/lock_metrics.rs`（L8-16）

---

## 開発者体験（DX）

### ❌ マイナス点

- **CI の pull_request トリガーが未設定** `-2`
  > `.github/workflows/ci.yml` が `push` イベントのみをトリガーとしており、`pull_request:` イベントが未設定。PRへの自動チェックが走らず、PRマージ前の品質保証が機能しない。
  > 対象ファイル: `.github/workflows/ci.yml`

- **bench-regression のローカル実行スクリプトが存在しない** `-1`
  > `bin/ci.bat` がジョブA〜Dと1:1対応しているが、ジョブE（`bench-regression`）のローカル実行スクリプトが存在しない。ベンチマーク回帰をローカルで確認する手段がない。
  > 対象ファイル: `bin/`

- **README の Contributing セクションがプレースホルダー** `-1`
  > `README.md` の Contributing セクションが `（※チーム開発時のガイドラインや...）` というプレースホルダーのまま。
  > 対象ファイル: `README.md`

---

## ゲームプレイ完成度

### ❌ マイナス点

- **ゲームループの完結性が未確認（E2Eテストなし）** `-2`
  > 開始→プレイ→終了→リトライの全経路が自動テストで検証されていない。ゲームオーバー後のリトライ・スコア表示・セーブデータ反映の動作が手動確認のみに依存している。

- **視覚的完成度（Skeleton/Ghost のスプライト未実装）** `-2`
  > Skeleton と Ghost が Golem と Bat の UV を流用しており、視覚的に区別できない。「遊べるゲーム」としての完成度を損なっている。
  > 対象ファイル: `native/game_render/src/renderer/mod.rs`（L258-266）

---

## セキュリティ・配布可能性

### ❌ マイナス点

- **WebSocket 認証・認可が未実装（再掲）** `-3`
  > ネットワーク層の評価で既述。誰でも任意のルームに参加できる状態はセキュリティ上の重大な欠如。
  > 対象ファイル: `apps/game_network/lib/game_network/channel.ex`

- **mix audit / cargo audit の CI 組み込みなし** `-2`
  > 依存クレート・パッケージの脆弱性チェックが CI に含まれていない。`mix audit`（`mix_audit` パッケージ）と `cargo audit` が未設定。
  > 対象ファイル: `.github/workflows/ci.yml`

- **ビルド成果物の配布手順が未整備** `-2`
  > Windows/macOS/Linux 向けのインストーラー・パッケージングの手順が存在しない。`README.md` に `iex -S mix` での起動手順はあるが、エンドユーザー向けの配布形態が未定義。
  > 対象ファイル: `README.md`, `docs/`
