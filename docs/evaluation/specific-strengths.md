# AlchemyEngine — プラス点 詳細一覧

## 採点基準

| 点数 | 基準 |
|:---:|:---|
| +1 | 正しく実装されている。問題はないが特筆するほどではない |
| +2 | 業界の一般的なベストプラクティスに沿った、良い設計判断 |
| +3 | 同規模・同種プロジェクトの平均を明確に上回る実装 |
| +4 | プロダクションレベルのゲームエンジン・OSSと比較しても遜色ない実装 |
| +5 | このクラスの個人プロジェクトでは見たことがないレベルの卓越した実装 |

---

## apps/game_engine — エンジンコア・OTP設計

### ✅ プラス点

- **ContentBehaviour のオプショナルコールバック設計** `+5`
  > `@optional_callbacks` で7つのコールバックを明示的に宣言し、`function_exported?/3` による実行時分岐を排除している。`AsteroidArena` が `level_up_scene/0`・`boss_alert_scene/0` を実装しないことで、エンジンコアがこれらの概念を持たなくても2コンテンツが共存できることを実証している。Godot の `_process` / `_physics_process` オーバーライドと同等の柔軟性をElixirのBehaviourで実現した設計は、同規模の個人プロジェクトでは見たことがないレベル。
  > 対象ファイル: `apps/game_engine/lib/game_engine/content_behaviour.ex`

- **バックプレッシャー設計（整合性維持とスキップの明確な分離）** `+5`
  > GCポーズ等で2秒以上遅延した場合（メッセージキュー深度 > 120）に、`on_frame_event`（スコア・HP・レベルアップ）とシーン遷移はスキップせず、入力・物理AI・`on_nif_sync`・ログはスキップする。「何を守り、何を捨てるか」の設計判断が明示的にコードに記述されており、Bevy の `FixedUpdate` スケジューラや Phoenix LiveView の差分更新と同等の思想を独自実装している。
  > 対象ファイル: `apps/game_engine/lib/game_engine/game_events.ex`（L194-291）

- **SSoT 整合性チェック（SSOT CHECK）** `+4`
  > 60フレームごとに `get_full_game_state` でRust側のスコア・キルカウントとElixir側の値を比較し、乖離があれば `[SSOT CHECK]` ログを出力する仕組みを `diagnostics.ex` に実装。Elixir = SSoT という設計原則を実行時に自動検証する機構は、プロダクションレベルのゲームエンジンでも珍しい。
  > 対象ファイル: `apps/game_engine/lib/game_engine/game_events/diagnostics.ex`（L94-110）

- **ダーティフラグによる差分NIF注入** `+3`
  > `LevelComponent.on_nif_sync/1` 内の全 `sync_*` 関数でプロセス辞書を使ったダーティフラグを実装し、値が変化したときのみNIFを呼ぶ設計。毎フレームのNIFオーバーヘッドを最小化しながらSSoTを維持する。
  > 対象ファイル: `apps/game_content/lib/game_content/vampire_survivor/level_component.ex`（L177-266）

- **フレームループの処理順序設計** `+3`
  > `handle_frame_events_main/3` の処理順序（on_frame_event → シーン update → 遷移 → 入力/物理AI → on_nif_sync → ログ）が意図的に設計されており、`on_physics_process`（ボスAI等）がNIF状態を書き換えた後に `on_nif_sync` を実行することで最新状態をRustに反映できる。コメントで明記されている。
  > 対象ファイル: `apps/game_engine/lib/game_engine/game_events.ex`（L251-297）

- **SaveManager の HMAC 付きセーブデータ** `+2`
  > セーブデータに HMAC-SHA256 署名を付与し、改ざん検出を実装。個人プロジェクトのゲームエンジンでセキュリティを考慮した設計は評価できる。
  > 対象ファイル: `apps/game_engine/lib/game_engine/save_manager.ex`

- **DynamicSupervisor によるルーム動的管理** `+2`
  > `GameEngine.RoomSupervisor` が `DynamicSupervisor` として実装されており、ルームの動的起動・停止が可能。`one_for_one` 戦略により `StressMonitor` がクラッシュしてもゲームが継続する設計がコメントで明示されている。
  > 対象ファイル: `apps/game_server/lib/game_server/application.ex`

---

## apps/game_content — コンテンツ実装・ゲームロジック

### ✅ プラス点

- **純粋関数による World/Rule 実装** `+4`
  > `BossSystem.check_spawn/2`・`SpawnSystem.maybe_spawn/3`・`LevelSystem.generate_weapon_choices/1` がすべて純粋関数として実装されており、副作用がない。シーン state を戻り値として返す設計により、テストが容易でリプレイ再現性が高い。Bevy の `System` 関数と同等の設計思想をElixirで実現している。
  > 対象ファイル: `apps/game_content/lib/game_content/vampire_survivor/boss_system.ex`, `spawn_system.ex`, `level_system.ex`

- **AsteroidArena による ContentBehaviour の実証** `+4`
  > VampireSurvivorとは異なる「武器・ボス・レベルアップのないシューター」として実装することで、エンジンコアがコンテンツ固有の概念を持たなくても動作することを実証している。`SplitComponent` が小惑星分裂ロジックを担い、`on_event({:entity_removed, ...})` で処理する設計は、コンポーネントシステムの柔軟性を示している。
  > 対象ファイル: `apps/game_content/lib/game_content/asteroid_arena/`

- **エンティティパラメータの外部化** `+3`
  > `SpawnComponent.on_ready/1` でワールド生成後に一度だけ `set_entity_params` を呼び、敵・武器・ボスのすべてのパラメータをRustに注入する。Rustコアにゲームバランス値がハードコードされていない。
  > 対象ファイル: `apps/game_content/lib/game_content/vampire_survivor/spawn_component.ex`（L40-53）

---

## apps/game_network — ネットワーク層

### ✅ プラス点

- **3トランスポートの実装（WebSocket・UDP・Local）** `+4`
  > Phoenix Channel（WebSocket）・UDP・ローカルマルチルームの3トランスポートが揃っており、用途に応じて選択できる。UDPプロトコルはzlib圧縮・32bitシーケンス番号・9種類のパケット種別を備えた本格的な実装。
  > 対象ファイル: `apps/game_network/lib/game_network/channel.ex`, `udp/server.ex`, `udp/protocol.ex`, `local.ex`

- **OTP プロセス隔離の実証（ルーム間クラッシュ分離）** `+4`
  > `LocalTest` の OTP隔離テスト（L132-148）で `Process.exit(pid_a, :kill)` で一方のルームを強制終了し、他方が生存することをテストで検証している。「クラッシュ分離」という設計原則をテストで証明している点が秀逸。
  > 対象ファイル: `apps/game_network/test/game_network_local_test.exs`（L132-148）

---

## native/game_physics — ECS・SoA・SIMD

### ✅ プラス点

- **全エンティティで統一されたSoA構造** `+5`
  > `EnemyWorld`・`BulletWorld`・`ParticleWorld`・`ItemWorld` の全エンティティ種別でSoA（Structure of Arrays）が統一されている。`alive: Vec<u8>` が `0xFF`/`0x00` の2値を取る設計はSSE2 SIMDマスクとして直接ロードできるよう意図されており、データ構造とSIMD命令が密結合した設計は個人プロジェクトでは見たことがないレベル。
  > 対象ファイル: `native/game_physics/src/world/enemy.rs`（L7-27）

- **SIMD SSE2 + スカラーフォールバック + rayon 並列の3段階戦略** `+5`
  > `chase_ai.rs` に `#[cfg(target_arch = "x86_64")]` でSSE2 SIMD版・`RAYON_THRESHOLD = 500` でrayon並列版・端数処理のスカラーフォールバックの3段階が実装されている。unsafeブロックに安全性根拠コメントが充実しており、SIMD/スカラー一致テスト（許容誤差 0.05）も完備。Bevy の `bevy_tasks` や Godot の WorkerThreadPool と比較しても遜色ない実装。
  > 対象ファイル: `native/game_physics/src/game_logic/chase_ai.rs`（L135-419）

- **free_list O(1) スポーン/キル（全エンティティ統一）** `+4`
  > `kill` は `saturating_sub` でアンダーフロー防止・冪等性テスト完備。`spawn` は `free_list.pop()` でO(1)スロット再利用。全エンティティ種別で統一されており、ECSフレームワーク（Bevy の `EntityAllocator`）と同等の設計。
  > 対象ファイル: `native/game_physics/src/world/enemy.rs`（L62-103）

- **空間ハッシュ衝突検出（FxHashMap + 2段階フィルタ）** `+4`
  > `FxHashMap`（rustc-hash）による高速な空間ハッシュと、`query_nearby_into` でバッファ再利用によるゼロアロケーション設計。動的（敵・弾丸）と静的（障害物）の分離・2段階フィルタリングが実装されている。
  > 対象ファイル: `native/game_physics/src/physics/spatial_hash.rs`

- **決定論的 LCG 乱数（再現性テスト済み）** `+3`
  > Knuth LCGの定番定数を使用し、`wrapping_mul/add` で安全なオーバーフロー処理。`PARTICLE_RNG_SEED` を `constants.rs` で定数化し、パーティクルの決定論的再現が可能。再現性テストも完備。
  > 対象ファイル: `native/game_physics/src/physics/rng.rs`

- **EnemySeparation トレイトによるテスト可能性** `+3`
  > `EnemySeparation` トレイトにより、テスト用モックを注入可能。分離パスがrayon並列化できない理由（書き込み衝突）をコメントで明記。設計判断の根拠がコードに残っている。
  > 対象ファイル: `native/game_physics/src/physics/separation.rs`

- **物理ステップのアーキテクチャ原則の明文化** `+2`
  > `physics_step.rs` に「HPの権威はElixir側。ここではイベント発行のみ行い」というコメントがあり、SSoT原則がRust側のコードにも浸透している。
  > 対象ファイル: `native/game_physics/src/game_logic/physics_step.rs`（L111-113）

---

## native/game_nif — NIF設計・ブリッジ

### ✅ プラス点

- **NIF 関数カテゴリ分類（ロック競合の予測可能性）** `+4`
  > `world_nif.rs`（パラメータ注入）・`action_nif.rs`（アクション）・`read_nif.rs`（読み取り専用）・`push_tick_nif.rs`（DirtyCpu）・`game_loop_nif.rs`（ループ制御）・`render_nif.rs`・`save_nif.rs` の7カテゴリに分類されており、ロック競合の予測可能性が高い。Rustler の公式ガイドラインを超えた設計。
  > 対象ファイル: `native/game_nif/src/nif/`

- **ResourceArc による GC 連動ライフタイム管理** `+4`
  > `ResourceArc<GameWorld>` と `ResourceArc<GameLoopControl>` でElixir GCとRustのライフタイムを連動させている。`impl rustler::Resource` の登録まで完備しており、メモリリークのリスクがない。
  > 対象ファイル: `native/game_nif/src/nif/world_nif.rs`（L23-65）

- **lock_metrics による RwLock 待機時間の可観測性** `+4`
  > `AtomicU64` でロックフリーな累積統計を管理し、read lock > 300μs / write lock > 500μs で警告、5秒ごとに平均待機時間をレポートする仕組みを実装。NIFのロック競合を本番環境で観測できる設計は、プロダクションレベルのゲームエンジンでも珍しい。
  > 対象ファイル: `native/game_nif/src/lock_metrics.rs`

- **push_tick の DirtyCpu スケジューラ指定** `+3`
  > `#[rustler::nif(schedule = "DirtyCpu")]` でBEAMスケジューラをブロックしないDirty NIFとして実行。物理演算という重い処理をBEAMのスケジューラに影響させない設計が正しく実装されている。
  > 対象ファイル: `native/game_nif/src/nif/push_tick_nif.rs`（L18-66）

- **サブフレーム補間（lerp）のロック外計算** `+4`
  > `render_snapshot.rs` で `prev_tick_ms`/`curr_tick_ms` の差分でフレーム間の経過割合 α を計算し、`clamp(0.0, 1.0)` でオーバーシュートを防止。60fps物理と高フレームレート描画を分離するサブフレーム補間が正しく実装されている。
  > 対象ファイル: `native/game_nif/src/render_snapshot.rs`（L197-210）

---

## native/game_render — 描画パイプライン

### ✅ プラス点

- **wgpu インスタンス描画（1 draw_indexed で全スプライト）** `+4`
  > `#[repr(C)] + bytemuck::Pod` でGPUバッファへのゼロコピー転送。`MAX_INSTANCES = 14510` の全スプライトを1回の `draw_indexed` で描画するドローコール最小化設計。wgpu 0.19 時代の個人プロジェクトとしては非常に高品質。
  > 対象ファイル: `native/game_render/src/renderer/mod.rs`（L51-58, L991）

- **CI 用ヘッドレスレンダラー** `+4`
  > `headless.rs` で `mpsc::channel + map_async + poll(WaitForSubmissionIndex)` によるGPU読み出し同期化と、行パディング除去まで実装したオフスクリーンレンダラーが存在する。CIでGPUレンダリングをテストできる設計は、個人プロジェクトでは極めて珍しい。
  > 対象ファイル: `native/game_render/src/headless.rs`

- **RenderBridge トレイトによる疎結合** `+3`
  > `RenderBridge: Send + 'static` トレイトで描画スレッドとゲームロジックを疎結合。`on_move_input`/`on_ui_action` で `OwnedEnv::send_and_clear` を使ってElixirプロセスに非同期メッセージ送信する設計が正しく実装されている。
  > 対象ファイル: `native/game_render/src/window.rs`（L29-33）

---

## native/game_audio — オーディオ

### ✅ プラス点

- **コマンドパターン + mpsc::channel 非同期設計** `+3`
  > `AudioCommand` enumと `mpsc::channel` によるコマンド駆動設計。`start_audio_thread` 失敗時でもハンドルを返し、呼び出し側をクラッシュさせない設計。デバイス不在時の `log::warn!` のみのグレースフルフォールバックが正しく実装されている。
  > 対象ファイル: `native/game_audio/src/audio.rs`（L64-128）

- **マクロ駆動アセット定義（Single Source of Truth）** `+3`
  > `define_assets!` マクロでID・パス・埋め込みデータを一箇所に定義。`include_bytes!` でコンパイル時バイナリ埋め込みと実行時ロードの2段階フォールバックが実装されている。
  > 対象ファイル: `native/game_audio/src/asset/mod.rs`（L7-41）

---

## テスト戦略

### ✅ プラス点

- **SIMD/スカラー一致テスト（許容誤差 0.05）** `+4`
  > `chase_ai.rs` のテスト（L321-417）で8体（SIMD 2バッチ）を使い、死亡敵の速度フィールドが変化しないことまで検証。`_mm_rsqrt_ps` の近似精度誤差（最大 ~0.04%）を考慮した許容誤差設定が正確。
  > 対象ファイル: `native/game_physics/src/game_logic/chase_ai.rs`（L321-417）

- **StubRoom による NIF 依存の完全排除** `+4`
  > `test/support/room_stubs.ex` の `StubRoom` が NIF を起動せずに `GameEngine.RoomRegistry` に登録できる軽量スタブ。`notify: pid` オプションで `assert_receive` による同期確認が可能。NIF依存を排除したテスト戦略が徹底されている。
  > 対象ファイル: `apps/game_network/test/support/room_stubs.ex`

- **純粋関数テストの徹底** `+3`
  > `game_content` の7テストファイルがすべて純粋関数・ロジック部分のみをテストし、NIF・SceneManagerへの依存を避けている。`async: true` で並列実行可能。
  > 対象ファイル: `apps/game_content/test/`

---

## 可観測性・デバッグ容易性

### ✅ プラス点

- **Telemetry イベントの体系的な設計** `+3`
  > `[:game, :tick]`・`[:game, :level_up]`・`[:game, :boss_spawn]`・`[:game, :frame_dropped]`・`[:game, :session_end]` の5種類のイベントが体系的に設計されており、`Telemetry.Metrics.ConsoleReporter` で可視化されている。
  > 対象ファイル: `apps/game_engine/lib/game_engine/telemetry.ex`

- **StressMonitor によるフレームバジェット監視** `+3`
  > `StressMonitor` GenServerがフレームバジェット超過時に `Logger.warning` を出力し、`one_for_one` 戦略でクラッシュしてもゲームが継続する設計。
  > 対象ファイル: `apps/game_engine/lib/game_engine/stress_monitor.ex`

---

## 変更容易性・保守性

### ✅ プラス点

- **マジックナンバーの集約（constants.rs）** `+3`
  > 物理定数（画面サイズ・マップサイズ・速度・半径・セルサイズ等）が `constants.rs` に集約されており、散在が極めて少ない。
  > 対象ファイル: `native/game_physics/src/constants.rs`

- **pending-issues.md による課題の一元管理** `+3`
  > 未解決課題9件が番号・優先度・影響ファイル・作業ステップ付きで `pending-issues.md` に一元管理されており、コード内のTODOが2件のみ。技術的負債の把握と管理が行き届いている。
  > 対象ファイル: `docs/pending-issues.md`

---

## 開発者体験（DX）

### ✅ プラス点

- **bin/ci.bat と GitHub Actions の完全同期** `+4`
  > `ci.bat` が GitHub Actions の各ジョブ（A/B/C/D）と1:1対応しており、ローカルとCIの乖離がない。`FAILED` 変数に失敗ジョブを蓄積して最後にサマリー表示する設計も優秀。
  > 対象ファイル: `bin/ci.bat`, `.github/workflows/ci.yml`

- **ベンチマーク回帰テスト（bench-regression ジョブ）** `+4`
  > `bench-regression` ジョブが `main` push 時に `cargo bench -p game_physics` を実行し、前回比+10%超でCIをブロック。ベンチマーク結果をGitHub Pagesに自動プッシュする設計は、プロダクションレベルのOSSでも珍しい個人プロジェクトの取り組み。
  > 対象ファイル: `.github/workflows/ci.yml`

- **CI キャッシュ戦略（NIF変更時の確実な再ビルド）** `+3`
  > `elixir-test` ジョブのキャッシュキーに `native/**/*.toml` を含めることで、NIF変更時に確実にキャッシュが無効化される。Rustler NIFを含むElixirプロジェクトの典型的な落とし穴を回避している。
  > 対象ファイル: `.github/workflows/ci.yml`

---

## プロジェクト全体設計

### ✅ プラス点

- **ドキュメントの品質・網羅性・コードとの一致度** `+5`
  > `vision.md`（175行）・`architecture-overview.md`（303行）・`elixir-layer.md`（434行）・`rust-layer.md`（563行）・`data-flow.md`（306行）・`game-content.md`（418行）の6ドキュメントが全てMermaidダイアグラム付きで充実しており、コードとの一致度が高い。個人プロジェクトのドキュメント品質としては突出している。
  > 対象ファイル: `docs/`

- **vision.md による設計哲学の明文化** `+4`
  > 「エンジンがこの概念を知る必要があるか？」という設計判断基準が `vision.md` に明文化されており、コードレビュー・設計議論の共通言語として機能している。Godot の「ノードとシーン」哲学と同等の明確さ。
  > 対象ファイル: `docs/vision.md`

- **improvement-plan.md による自己評価サイクル** `+3`
  > スコアカード（各カテゴリ 1〜10点）と未解決課題の優先順位が `improvement-plan.md` に記録されており、自己改善サイクルが機能している。完了済みタスクの取り消し線による進捗管理も明確。
  > 対象ファイル: `docs/task/improvement-plan.md`
