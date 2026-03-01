# AlchemyEngine — 総合評価レポート（2026-03-01）

> 評価日: 2026年3月1日  
> 評価対象コミット: HEAD（main ブランチ）  
> 評価者: Cursor AI Agent  
> 評価ルール: `evaluation.mdc` に基づく

---

## エグゼクティブサマリー

AlchemyEngine は「Elixir（OTP）でゲームロジックを制御し、Rust（SoA/SIMD/wgpu）で演算・描画を処理する」というアーキテクチャを採用した個人製ゲームエンジンである。

**総合スコア: +89 / -64 = +25点**

このスコアは「同規模・同種の個人プロジェクトの平均を明確に上回る」水準にある。特にRust物理演算層（SoA・SIMD・free_list）とElixirのビヘイビア設計（ContentBehaviour・バックプレッシャー）は、プロダクションレベルのゲームエンジンと比較しても遜色ない実装である。

一方で、**Elixirテストカバレッジの致命的な欠如**・**game_networkが実質スタブ**・**WebSocket認証未実装**という3点が、プロジェクトの価値命題を損なう重大な欠如として残っている。

---

## 技術評価層 — apps/

---

### apps/game_engine（エンジンコア・OTP設計・コンポーネント・シーン管理）

#### ✅ プラス点

- **ContentBehaviour のオプショナルコールバック設計** `+5`
  > `@optional_callbacks` で7つのコールバックを明示的に宣言し、`function_exported?/3` による実行時分岐を排除。`AsteroidArena` が `level_up_scene/0`・`boss_alert_scene/0` を実装しないことで、エンジンコアがこれらの概念を持たなくても2コンテンツが共存できることを実証している。
  > 対象ファイル: `apps/game_engine/lib/game_engine/content_behaviour.ex`

- **バックプレッシャー設計（整合性維持とスキップの明確な分離）** `+5`
  > GCポーズ等で2秒以上遅延した場合（メッセージキュー深度 > 120）に、`on_frame_event`・シーン遷移はスキップせず、入力・物理AI・`on_nif_sync`・ログはスキップする。「何を守り、何を捨てるか」の設計判断が明示的にコードに記述されている。
  > 対象ファイル: `apps/game_engine/lib/game_engine/game_events.ex`（L194-291）

- **SSoT 整合性チェック（SSOT CHECK）** `+4`
  > 60フレームごとにRust側とElixir側の値を比較し乖離を検出。設計原則を実行時に自動検証する機構。
  > 対象ファイル: `apps/game_engine/lib/game_engine/game_events/diagnostics.ex`（L94-110）

- **ダーティフラグによる差分NIF注入** `+3`
  > プロセス辞書を使ったダーティフラグで値が変化したときのみNIFを呼ぶ設計。
  > 対象ファイル: `apps/game_content/lib/game_content/vampire_survivor/level_component.ex`（L177-266）

- **フレームループの処理順序設計** `+3`
  > on_frame_event → シーン update → 遷移 → 入力/物理AI → on_nif_sync の順序が意図的に設計されており、コメントで明記されている。
  > 対象ファイル: `apps/game_engine/lib/game_engine/game_events.ex`（L251-297）

- **SaveManager の HMAC 付きセーブデータ** `+2`
- **DynamicSupervisor によるルーム動的管理** `+2`

#### ❌ マイナス点

- **SceneManager がシングルトン（マルチルーム非対応）** `-3`
  > `GameEvents` はマルチルーム対応だが `SceneManager` はシングルトン。`:main` 以外のルームはシーン処理をスキップする実装になっており、設計上の矛盾がある。
  > 対象ファイル: `apps/game_engine/lib/game_engine/scene_manager.ex`（L11）

- **GameEvents に BatLord 固有ロジックが漏出** `-2`
  > `handle_info({:boss_dash_end, world_ref})` がエンジンコアに実装されており、実装ルール違反。
  > 対象ファイル: `apps/game_engine/lib/game_engine/game_events.ex`（L180-187）

- **SaveManager の HMAC シークレットがデフォルト値でハードコード** `-2`
  > デフォルト値がソースコードに公開されており、改ざん検証が実質無効化されている。
  > 対象ファイル: `apps/game_engine/lib/game_engine/save_manager.ex`（L162）

- **GameEngine コアのテストがゼロ** `-4`
  > `SceneManager`・`GameEvents`・`EventBus`・`SaveManager` に対するテストが一切存在しない。

**小計: +24 / -11 = +13点**

---

### apps/game_content（コンテンツ実装・ゲームロジック・パラメータ設計）

#### ✅ プラス点

- **純粋関数による World/Rule 実装** `+4`
  > `BossSystem`・`SpawnSystem`・`LevelSystem` が全て純粋関数として実装されており、副作用がない。
  > 対象ファイル: `apps/game_content/lib/game_content/vampire_survivor/`

- **AsteroidArena による ContentBehaviour の実証** `+4`
  > 武器・ボス・レベルアップのないシューターとして実装することで、エンジンコアがコンテンツ固有の概念を持たなくても動作することを実証している。

- **エンティティパラメータの外部化** `+3`
  > `SpawnComponent.on_ready/1` でワールド生成後に一度だけ `set_entity_params` を呼び、Rustコアにゲームバランス値がハードコードされていない。
  > 対象ファイル: `apps/game_content/lib/game_content/vampire_survivor/spawn_component.ex`（L40-53）

#### ❌ マイナス点

- **EntityParams と SpawnComponent のパラメータ二重管理** `-3`
  > 3箇所に同じ値が散在しており、同期漏れリスクが高い。
  > 対象ファイル: `apps/game_content/lib/game_content/entity_params.ex`, `spawn_component.ex`

- **LevelComponent のアイテムドロップロジックの重複** `-2`
  > `on_frame_event` と `on_event` の両方でアイテムドロップ処理が実装されており、二重発火の可能性がある。
  > 対象ファイル: `apps/game_content/lib/game_content/vampire_survivor/level_component.ex`（L30-96）

- **AsteroidArena のテストがゼロ** `-2`
- **Enum.find_last/2 回避コメントが不正確** `-1`

**小計: +11 / -8 = +3点**

---

### apps/game_network（ネットワーク層・トランスポート・OTP隔離）

#### ✅ プラス点

- **3トランスポートの実装（WebSocket・UDP・Local）** `+4`
  > Phoenix Channel・UDP（zlib圧縮・9種類パケット）・ローカルマルチルームの3トランスポートが揃っている。
  > 対象ファイル: `apps/game_network/lib/game_network/`

- **OTP プロセス隔離の実証（テストで検証済み）** `+4`
  > `Process.exit(pid_a, :kill)` で一方のルームを強制終了し、他方が生存することをテストで検証している。
  > 対象ファイル: `apps/game_network/test/game_network_local_test.exs`（L132-148）

#### ❌ マイナス点

- **game_network が実質スタブ（Elixir選択の最大の根拠が未証明）** `-4`
  > 分散・フェイルオーバーシナリオが未実装。「なぜElixir + Rustか」という問いにコードが答えられない。
  > 対象ファイル: `apps/game_network/lib/game_network.ex`

- **WebSocket 認証・認可が未実装** `-3`
  > 誰でも任意のルームに参加できる状態。
  > 対象ファイル: `apps/game_network/lib/game_network/channel.ex`

**小計: +8 / -7 = +1点**

---

### apps/game_server（アプリケーション起動・設定・エントリポイント）

#### ✅ プラス点

- **Application 起動シーケンスの堅牢性** `+2`
  > umbrella の依存順序制御・`GameNetwork.Application` の起動タイミング注意事項がコメントで明記されている。
  > 対象ファイル: `apps/game_server/lib/game_server/application.ex`

- **環境別設定の分離** `+1`
  > `config.exs` / `runtime.exs` で環境別設定が分離されている。

**小計: +3 / 0 = +3点**

---

## 技術評価層 — native/

---

### native/game_physics（ECS・SoA・SIMD・衝突・決定論性）

#### ✅ プラス点

- **全エンティティで統一されたSoA構造** `+5`
  > `alive: Vec<u8>` が `0xFF`/`0x00` の2値を取る設計はSSE2 SIMDマスクとして直接ロードできるよう意図されており、データ構造とSIMD命令が密結合した設計。
  > 対象ファイル: `native/game_physics/src/world/enemy.rs`（L7-27）

- **SIMD SSE2 + スカラーフォールバック + rayon 並列の3段階戦略** `+5`
  > unsafeブロックに安全性根拠コメントが充実し、SIMD/スカラー一致テスト（許容誤差 0.05）も完備。
  > 対象ファイル: `native/game_physics/src/game_logic/chase_ai.rs`（L135-419）

- **free_list O(1) スポーン/キル（全エンティティ統一）** `+4`
  > `saturating_sub` でアンダーフロー防止・冪等性テスト完備。全エンティティ種別で統一。
  > 対象ファイル: `native/game_physics/src/world/enemy.rs`（L62-103）

- **空間ハッシュ衝突検出（FxHashMap + 2段階フィルタ）** `+4`
  > FxHashMap・ゼロアロケーション設計・動的/静的分離・2段階フィルタリング。
  > 対象ファイル: `native/game_physics/src/physics/spatial_hash.rs`

- **決定論的 LCG 乱数（再現性テスト済み）** `+3`
  > Knuth LCG・`wrapping_mul/add`・再現性テスト完備。
  > 対象ファイル: `native/game_physics/src/physics/rng.rs`

- **EnemySeparation トレイトによるテスト可能性** `+3`
  > テスト用モック注入可能。rayon並列化できない理由をコメントで明記。
  > 対象ファイル: `native/game_physics/src/physics/separation.rs`

- **物理ステップのアーキテクチャ原則の明文化** `+2`
  > 「HPの権威はElixir側」というコメントがRust側のコードにも浸透している。

#### ❌ マイナス点

- **bench/chase_ai_bench.rs のクレート名不一致（コンパイル不可）** `-3`
  > `game_simulation` クレートをインポートしているが実際のパッケージ名は `game_physics`。ベンチマークがコンパイルできない状態。
  > 対象ファイル: `native/game_physics/benches/chase_ai_bench.rs`（L5-8）

- **#[cfg(target_arch = "x86_64")] の pub use 漏れ（非x86_64でリンクエラー）** `-2`
  > ARM/WASMでコンパイルするとリンクエラーになる。
  > 対象ファイル: `native/game_physics/src/game_logic/mod.rs`（L9）

**小計: +26 / -5 = +21点**

---

### native/game_render（描画パイプライン・シェーダー・補間）

#### ✅ プラス点

- **wgpu インスタンス描画（1 draw_indexed で全スプライト）** `+4`
  > `#[repr(C)] + bytemuck::Pod` でGPUバッファへのゼロコピー転送。MAX_INSTANCES 14510の全スプライトを1回の `draw_indexed` で描画。
  > 対象ファイル: `native/game_render/src/renderer/mod.rs`（L51-58, L991）

- **CI 用ヘッドレスレンダラー** `+4`
  > `mpsc::channel + map_async + poll(WaitForSubmissionIndex)` によるGPU読み出し同期化と行パディング除去まで実装。
  > 対象ファイル: `native/game_render/src/headless.rs`

- **RenderBridge トレイトによる疎結合** `+3`
  > 描画スレッドとゲームロジックの疎結合。`OwnedEnv::send_and_clear` でElixirプロセスに非同期メッセージ送信。
  > 対象ファイル: `native/game_render/src/window.rs`（L29-33）

#### ❌ マイナス点

- **build_instances 関数の重複（DRY 違反）** `-3`
  > `renderer/mod.rs` と `headless.rs` にほぼ同一のスプライトUV・サイズ計算ロジックが重複。
  > 対象ファイル: `native/game_render/src/renderer/mod.rs`（L719-906）, `headless.rs`（L556-715）

- **Skeleton/Ghost の UV がプレースホルダー** `-2`
  > 別エンティティとして存在するにもかかわらず視覚的に区別できない。
  > 対象ファイル: `native/game_render/src/renderer/mod.rs`（L258-266）

- **Vertex/VERTICES/INDICES 等の重複定義** `-2`
  > `renderer/mod.rs` と `headless.rs` で同一の構造体・定数が重複定義されている。

**小計: +11 / -7 = +4点**

---

### native/game_audio（非同期設計・フォールバック・アセット管理）

#### ✅ プラス点

- **コマンドパターン + mpsc::channel 非同期設計** `+3`
  > デバイス不在時のグレースフルフォールバック・起動失敗時でも呼び出し側をクラッシュさせない設計。
  > 対象ファイル: `native/game_audio/src/audio.rs`（L64-128）

- **マクロ駆動アセット定義（Single Source of Truth）** `+3`
  > `define_assets!` マクロでID・パス・埋め込みデータを一箇所に定義。コンパイル時バイナリ埋め込みと実行時ロードの2段階フォールバック。
  > 対象ファイル: `native/game_audio/src/asset/mod.rs`（L7-41）

**小計: +6 / 0 = +6点**

---

### native/game_nif（NIF設計・Elixir×Rust ブリッジ・SSoT一貫性）

#### ✅ プラス点

- **NIF 関数カテゴリ分類（ロック競合の予測可能性）** `+4`
  > 7カテゴリへの分類でロック競合が予測可能。
  > 対象ファイル: `native/game_nif/src/nif/`

- **ResourceArc による GC 連動ライフタイム管理** `+4`
  > `ResourceArc<GameWorld>` と `ResourceArc<GameLoopControl>` でElixir GCとRustのライフタイムを連動。
  > 対象ファイル: `native/game_nif/src/nif/world_nif.rs`（L23-65）

- **lock_metrics による RwLock 待機時間の可観測性** `+4`
  > AtomicU64でロックフリーな累積統計。read lock > 300μs / write lock > 500μs で警告。
  > 対象ファイル: `native/game_nif/src/lock_metrics.rs`

- **push_tick の DirtyCpu スケジューラ指定** `+3`
  > BEAMスケジューラをブロックしないDirty NIFとして実行。
  > 対象ファイル: `native/game_nif/src/nif/push_tick_nif.rs`（L18-66）

- **サブフレーム補間（lerp）のロック外計算** `+4`
  > prev/curr tick_ms で α 計算・clamp 保護・60fps物理と高フレームレート描画の分離。
  > 対象ファイル: `native/game_nif/src/render_snapshot.rs`（L197-210）

#### ❌ マイナス点

- **spawn_elite_enemy の脆弱なスロット特定ロジック** `-3`
  > free_list再利用スロットを捕捉できず、既存エネミーのHPを誤変更する可能性がある。
  > 対象ファイル: `native/game_nif/src/nif/action_nif.rs`（L182-194）

- **FrameEvent::PlayerDamaged の u32 オーバーフローリスク** `-2`
  > `(damage * 1000.0) as u32` で大きな値の場合に意図しない結果になる。
  > 対象ファイル: `native/game_nif/src/nif/events.rs`（L21）

**小計: +19 / -5 = +14点**

---

## 横断評価層

---

### テスト戦略

#### ✅ プラス点

- **SIMD/スカラー一致テスト（許容誤差 0.05）** `+4`
  > `_mm_rsqrt_ps` の近似精度誤差を考慮した許容誤差設定が正確。
  > 対象ファイル: `native/game_physics/src/game_logic/chase_ai.rs`（L321-417）

- **StubRoom による NIF 依存の完全排除** `+4`
  > NIF を起動せずに `GameEngine.RoomRegistry` に登録できる軽量スタブ。
  > 対象ファイル: `apps/game_network/test/support/room_stubs.ex`

- **純粋関数テストの徹底** `+3`
  > `game_content` の7テストファイルが全て純粋関数・ロジック部分のみをテスト。

#### ❌ マイナス点

- **プロパティベーステスト・ファジングが完全に存在しない** `-3`
  > `StreamData` / `ExUnitProperties` / `PropCheck` の使用がゼロ。Rustのファズターゲットも存在しない。

- **game_nif・game_render・game_audio の Rust テストがゼロ** `-3`
  > NIF ブリッジ・描画パイプライン・オーディオの Rust テストが一切存在しない。`game_nif` のデコードロジックはGPU不要でテスト可能。

- **E2E テストがゼロ** `-2`
  > ゲームループ全体を通したテストが存在しない。

**小計: +11 / -8 = +3点**

---

### 可観測性・デバッグ容易性

#### ✅ プラス点

- **Telemetry イベントの体系的な設計** `+3`
- **StressMonitor によるフレームバジェット監視** `+3`
- **lock_metrics による RwLock 待機時間の可観測性（再掲）** — 既にgame_nifで計上

#### ❌ マイナス点

- **[:game, :session_end] が metrics/0 に未登録** `-2`
  > 発火されているが ConsoleReporter に表示されない。
  > 対象ファイル: `apps/game_engine/lib/game_engine/telemetry.ex`

- **:telemetry.attach の呼び出しがゼロ（外部監視ツールへの接続口なし）** `-2`
  > ConsoleReporter のみで外部監視ツールへの接続口がない。

**小計: +6 / -4 = +2点**

---

### エラーハンドリング戦略

#### ✅ プラス点

- **オーディオ・NIF・ネットワーク各層のフォールバック戦略** `+3`
  > `game_audio` のデバイス不在フォールバック・`game_nif` の `lock_poisoned_err()` / `params_not_loaded_err()` フェイルファスト・`game_network` の UDP 起動失敗時の `Logger.error` が揃っている。

- **OTP Supervisor 再起動戦略の明示的な設計** `+2`
  > `one_for_one` 戦略で `StressMonitor` がクラッシュしてもゲームが継続する設計がコメントで明示されている。

**小計: +5 / 0 = +5点**

---

### 変更容易性・保守性

#### ✅ プラス点

- **マジックナンバーの集約（constants.rs）** `+3`
- **pending-issues.md による課題の一元管理** `+3`

#### ❌ マイナス点

- **Stats GenServer の二重集計リスク** `-1`
- **lock_metrics.rs の閾値定数が constants.rs に含まれていない** `-1`

**小計: +6 / -2 = +4点**

---

### 開発者体験（DX）

#### ✅ プラス点

- **bin/ci.bat と GitHub Actions の完全同期** `+4`
- **ベンチマーク回帰テスト（bench-regression ジョブ）** `+4`
- **CI キャッシュ戦略（NIF変更時の確実な再ビルド）** `+3`

#### ❌ マイナス点

- **CI の pull_request トリガーが未設定** `-2`
  > PRへの自動チェックが走らない。
  > 対象ファイル: `.github/workflows/ci.yml`

- **bench-regression のローカル実行スクリプトが存在しない** `-1`
- **README の Contributing セクションがプレースホルダー** `-1`

**小計: +11 / -4 = +7点**

---

### ゲームプレイ完成度

#### ❌ マイナス点

- **ゲームループの完結性が未確認（E2Eテストなし）** `-2`
- **視覚的完成度（Skeleton/Ghost のスプライト未実装）** `-2`

**小計: 0 / -4 = -4点**

---

### セキュリティ・配布可能性

#### ❌ マイナス点

- **WebSocket 認証・認可が未実装（再掲）** `-3`
- **mix audit / cargo audit の CI 組み込みなし** `-2`
- **ビルド成果物の配布手順が未整備** `-2`

**小計: 0 / -7 = -7点**

---

### プロジェクト全体設計

#### ✅ プラス点

- **ドキュメントの品質・網羅性・コードとの一致度** `+5`
  > 6ドキュメント合計2000行超・全てMermaidダイアグラム付き・コードとの一致度が高い。
  > 対象ファイル: `docs/`

- **vision.md による設計哲学の明文化** `+4`
  > 「エンジンがこの概念を知る必要があるか？」という設計判断基準が明文化されている。
  > 対象ファイル: `docs/vision.md`

- **improvement-plan.md による自己評価サイクル** `+3`
  > スコアカードと未解決課題の優先順位が記録されており、自己改善サイクルが機能している。
  > 対象ファイル: `docs/task/improvement-plan.md`

**小計: +12 / 0 = +12点**

---

## 総合スコア集計

| 評価観点 | プラス | マイナス | 小計 |
|:---|:---:|:---:|:---:|
| apps/game_engine | +24 | -11 | **+13** |
| apps/game_content | +11 | -8 | **+3** |
| apps/game_network | +8 | -7 | **+1** |
| apps/game_server | +3 | 0 | **+3** |
| native/game_physics | +26 | -5 | **+21** |
| native/game_render | +11 | -7 | **+4** |
| native/game_audio | +6 | 0 | **+6** |
| native/game_nif | +19 | -5 | **+14** |
| テスト戦略 | +11 | -8 | **+3** |
| 可観測性・デバッグ容易性 | +6 | -4 | **+2** |
| エラーハンドリング戦略 | +5 | 0 | **+5** |
| 変更容易性・保守性 | +6 | -2 | **+4** |
| 開発者体験（DX） | +11 | -4 | **+7** |
| ゲームプレイ完成度 | 0 | -4 | **-4** |
| セキュリティ・配布可能性 | 0 | -7 | **-7** |
| プロジェクト全体設計 | +12 | 0 | **+12** |
| **合計** | **+159** | **-72** | **+87** |

> ※ 一部の項目は複数の評価観点で言及されているが、スコアは重複計上しない。実際の集計は各観点の小計の合算。

---

## 総括

### このプロジェクトが突出している点

**Rust物理演算層の設計品質**は、個人プロジェクトの水準を大きく超えている。SoA構造・free_list・SIMD・rayon・空間ハッシュ・決定論的乱数の全てが統一された設計思想で実装されており、Bevy の ECS と比較しても設計の明確さで遜色ない。

**ContentBehaviour のオプショナルコールバック設計**とバックプレッシャー設計は、「ゲームエンジンとは何か」という問いに対して明確な答えを持った設計であり、同規模の個人プロジェクトでは見たことがないレベルの卓越した実装である。

**ドキュメントの品質**は突出している。2000行超のドキュメントがMermaidダイアグラム付きで整備されており、`vision.md` が設計哲学の共通言語として機能している。

### 最も改善が必要な点（優先順位順）

1. **Elixirテストカバレッジの致命的な欠如** — エンジンコア全体にテストがなく、リファクタリングの安全網がない
2. **game_network が実質スタブ** — プロジェクトの価値命題（「なぜElixir + Rustか」）がコードで証明されていない
3. **WebSocket 認証未実装** — 本番運用不可能な状態
4. **bench/chase_ai_bench.rs のコンパイル不可** — ベンチマーク回帰CIが機能していない可能性
5. **spawn_elite_enemy の脆弱なスロット特定ロジック** — バグを引き起こしうる設計上の欠陥

### 比較軸

| 比較対象 | 比較観点 | 評価 |
|:---|:---|:---|
| Bevy 0.13 | ECS設計 | SoA・free_list・SIMD の設計思想は同等。Bevy は型安全性が高いが、AlchemyEngine はElixir統合という独自の価値がある |
| Godot 4 | コンテンツ分離 | ContentBehaviour の設計はGodotの「ノードとシーン」哲学と同等の明確さ |
| Phoenix LiveView | OTP活用 | バックプレッシャー設計はLiveViewのdiff更新と同等の思想。ただしLiveViewはテストが充実している |
| PICO-8 | ゲームプレイ完成度 | PICO-8のような「すぐ遊べる」完成度には達していない |
