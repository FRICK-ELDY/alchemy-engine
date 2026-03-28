# AlchemyEngine — プラス点 詳細一覧

> 最終更新: 2026-03-28（evaluation-2026-03-28 に基づく）

## 採点基準

| 点数 | 基準 |
|:---:|:---|
| +1 | 正しく実装されている。問題はないが特筆するほどではない |
| +2 | 業界の一般的なベストプラクティスに沿った、良い設計判断 |
| +3 | 同規模・同種プロジェクトの平均を明確に上回る実装 |
| +4 | プロダクションレベルのゲームエンジン・OSSと比較しても遜色ない実装 |
| +5 | このクラスの個人プロジェクトでは見たことがないレベルの卓越した実装 |

---

## apps/core — エンジンコア・OTP設計

### ✅ プラス点

- **Contents.Behaviour.Content のオプショナルコールバック設計** `+5`
  > `@optional_callbacks` で武器・ボス関連コールバックを明示し、`function_exported?/3` による実行時分岐を排除している。`Content.AsteroidArena` が `level_up_scene/0`・`boss_alert_scene/0` を実装しないことで、エンジンがこれらの概念を持たなくても複数コンテンツが共存できることを実証している。Godot の `_process` / `_physics_process` オーバーライドと同等の柔軟性を Elixir の Behaviour で実現した設計は、同規模の個人プロジェクトでは稀である。
  > 対象ファイル: `apps/contents/lib/behaviour/content.ex`

- **バックプレッシャー設計（整合性維持とスキップの明確な分離）** `+5`
  > GCポーズ等で2秒以上遅延した場合（メッセージキュー深度 > 120）に、`on_frame_event`（スコア・HP・レベルアップ）とシーン遷移はスキップせず、入力・物理AI・`on_nif_sync`・ログはスキップする。「何を守り、何を捨てるか」の設計判断が明示的にコードに記述されており、Bevy の `FixedUpdate` スケジューラや Phoenix LiveView の差分更新と同等の思想を独自実装している。
  > 対象ファイル: `apps/contents/lib/events/game.ex`

- **SSoT 整合性チェック（SSOT CHECK）** `+4`
  > 60フレームごとに `get_full_game_state` でRust側のスコア・キルカウントとElixir側の値を比較し、乖離があれば `[SSOT CHECK]` ログを出力する仕組みを `diagnostics.ex` に実装。Elixir = SSoT という設計原則を実行時に自動検証する機構は、プロダクションレベルのゲームエンジンでも珍しい。
  > 対象ファイル: `apps/contents/lib/events/game/diagnostics.ex`

- **SaveManager の HMAC 付きセーブデータ** `+2`
  > セーブデータに HMAC-SHA256 署名を付与し、改ざん検出を実装。個人プロジェクトのゲームエンジンでセキュリティを考慮した設計は評価できる。
  > 対象ファイル: `apps/core/lib/core/save_manager.ex`

- **DynamicSupervisor によるルーム動的管理** `+2`
  > `Core.RoomSupervisor` が `DynamicSupervisor` として実装されており、ルームの動的起動・停止が可能。`one_for_one` 戦略により `StressMonitor` がクラッシュしてもゲームが継続する設計がコメントで明示されている。`start_room`/`stop_room`/`list_rooms` API が整備済み。
  > 対象ファイル: `apps/server/lib/server/application.ex`, `apps/core/lib/core/room_supervisor.ex`

- **EventBus・SaveManager のテスト整備** `+2`
  > `event_bus_test.exs` で subscribe/broadcast/DOWN 時動作、`save_manager_test.exs` でスコア・HMAC・セッションを検証。core 層のリグレッション検出が可能になった。
  > 対象ファイル: `apps/core/test/core/`

- **NifBridgeBehaviour + Mox によるテスト用モック** `+2`
  > NIF をビヘイビアで抽象化し、テスト時には Mox でモック差し替え可能。Elixir 側のロジックを NIF に依存せず検証できる設計。
  > 対象ファイル: `apps/core/lib/core/nif_bridge_behaviour.ex`

---

## apps/contents — コンテンツ実装・ゲームロジック

### ✅ プラス点

- **純粋関数による World/Rule 実装** `+4`
  > `BossSystem.check_spawn/2`・`SpawnSystem.maybe_spawn/3`・`LevelSystem.generate_weapon_choices/1` がすべて純粋関数として実装されており、副作用がない。シーン state を戻り値として返す設計により、テストが容易でリプレイ再現性が高い。Bevy の `System` 関数と同等の設計思想をElixirで実現している。
  > 対象ファイル: `apps/contents/lib/contents/vampire_survivor/boss_system.ex`, `spawn_system.ex`, `level_system.ex`

- **GameEvents による SSoT とイベント駆動の一貫性** `+4`
  > Rust 60Hz ループ → `{:frame_events, events}` 受信 → コンポーネントの `on_frame_event/2` に委譲。エンジンはディスパッチのみ行いゲームロジックを知らない設計。NIF 注入は `on_nif_sync/1` でコンポーネントが担当。
  > 対象ファイル: `apps/contents/lib/events/game.ex`

- **AsteroidArena による ContentBehaviour の実証** `+4`
  > VampireSurvivorとは異なる「武器・ボス・レベルアップのないシューター」として実装することで、エンジンコアがコンテンツ固有の概念を持たなくても動作することを実証している。`SplitComponent` が小惑星分裂ロジックを担い、`on_event({:entity_removed, ...})` で処理する設計は、コンポーネントシステムの柔軟性を示している。
  > 対象ファイル: `apps/contents/lib/contents/asteroid_arena/`

- **エンティティパラメータの外部化** `+3`
  > `SpawnComponent.on_ready/1` でワールド生成後に一度だけ `set_entity_params` を呼び、敵・武器・ボスのすべてのパラメータをRustに注入する。Rustコアにゲームバランス値がハードコードされていない。`EntityParamTables` による一括注入が可能。
  > 対象ファイル: `apps/contents/lib/contents/vampire_survivor/spawn_component.ex`（L40-53）, `apps/contents/lib/contents/entity_params.ex`, `native/nif/src/nif/world_nif.rs`

- **コンテンツテストの充実（VampireSurvivor 向け）** `+3`
  > boss・spawn・level・entity_params・weapon_formulas 等、VampireSurvivor 用の7テストファイルが存在し、純粋関数・ロジック部分を `async: true` で並列検証している。
  > 対象ファイル: `apps/contents/test/content/`

---

## apps/network — ネットワーク層

### ✅ プラス点

- **Phoenix.Token による WebSocket 認証** `+4`
  > `Network.RoomToken` で `Phoenix.Token.sign` によりルームIDスコープ付きトークンを発行し、`channel.join/3` で `verify(token, room_id)` により必須検証を行っている。`{:error, :missing}` 等の種別で拒否理由を返し、不正参加を防止する設計が実装済み。
  > 対象ファイル: `apps/network/lib/network/channel.ex`（L71-106）, `apps/network/lib/network/room_token.ex`

- **3トランスポートの実装（Local・Channel・UDP）** `+4`
  > Phoenix Channel（WebSocket）・UDP・ローカルマルチルームの3トランスポートが揃っており、用途に応じて選択できる。UDPプロトコルはzlib圧縮・32bitシーケンス番号・9種類のパケット種別を備えた本格的な実装。
  > 対象ファイル: `apps/network/lib/network/channel.ex`, `udp/server.ex`, `udp/protocol.ex`, `local.ex`

- **OTP プロセス隔離の実証（ルーム間クラッシュ分離）** `+4`
  > `LocalTest` の OTP隔離テストで `Process.exit(pid_a, :kill)` で一方のルームを強制終了し、他方が生存することをテストで検証している。「クラッシュ分離」という設計原則をテストで証明している点が秀逸。
  > 対象ファイル: `apps/network/test/network_local_test.exs`（L132-148）

---

## apps/server — アプリケーション起動

### ✅ プラス点

- **Application 起動シーケンスの堅牢性** `+2`
  > `Registry`・`FormulaStore.LocalBackend`・`Contents.Scenes.Stack`・`EventBus`・`RoomSupervisor`・`StressMonitor`・`Stats`・`Telemetry` を `one_for_one` で起動し、`start_room(:main)` 失敗時は raise で起動を停止する設計。子プロセスの起動順が明確。
  > 対象ファイル: `apps/server/lib/server/application.ex`

- **環境別設定の分離（config.exs / runtime.exs）** `+1`
  > `runtime.exs` で `NETWORK_PORT`・`SAVE_HMAC_SECRET`・`SECRET_KEY_BASE` 等を環境変数から読み込み可能。
  > 対象ファイル: `config/runtime.exs`

---

## native/shared — 共通データ・Elixir 契約

### ✅ プラス点

- **#[repr(C)] + Pod/Zeroable による Zero-Copy 設計** `+2`
  > `Vec2`・`SnapshotHeader` が bytemuck で Zero-Copy 可能。ClientInfo.current() で環境情報を取得。interp（lerp, lerp_vec2）が明確に実装されている。
  > 対象ファイル: `native/shared/src/types.rs`, `native/shared/src/interp.rs`

---

## native/network — Zenoh 通信層

### ✅ プラス点

- **Protobuf フレームデコードの網羅性** `+4`
  > DrawCommand, CameraParams, UiCanvas, MeshDef, UiComponent 等を `decode_pb_render_frame` で RenderFrame へ変換。UiAnchor の未知値フォールバック等が実装されている。
  > 実装: `native/render_frame_proto/src/protobuf_render_frame.rs`。`network` は `native/network/src/protobuf_render_frame.rs` から `render` 経由で同関数を再エクスポート。契約 golden: `native/network/tests/render_frame_e2e_contract.rs`。

- **NetworkRenderBridge による RenderBridge 実装** `+2`
  > Zenoh 購読スレッド・frame_buffer・keys_held 管理。put_drop で CongestionControl::Drop。ClientInfo の発行。
  > 対象ファイル: `native/network/src/network_render_bridge.rs`

- **platform 切り替え（desktop / web）** `+2`
  > `#[cfg(not(target_family = "wasm"))]` で desktop、`#[cfg(target_family = "wasm")]` で web を切り替え。ClientSession の共通インターフェース。
  > 対象ファイル: `native/network/src/platform/mod.rs`

---

## native/nif（physics 含む）— NIF・ECS・SoA・SIMD

### ✅ プラス点

- **全エンティティで統一されたSoA構造** `+5`
  > `EnemyWorld`・`BulletWorld`・`ParticleWorld`・`ItemWorld` の全エンティティ種別でSoA（Structure of Arrays）が統一されている。`alive: Vec<u8>` が `0xFF`/`0x00` の2値を取る設計はSSE2 SIMDマスクとして直接ロードできるよう意図されている。
  > 対象ファイル: `native/nif/src/physics/world/`

- **SIMD SSE2 + rayon 並列 + スカラーフォールバックの3段階戦略** `+5`
  > `chase_ai.rs` に `#[cfg(target_arch = "x86_64")]` でSSE2 SIMD版・`RAYON_THRESHOLD` でrayon並列版・端数処理のスカラーフォールバックが実装されている。unsafeブロックに安全性根拠コメントが充実しており、SIMD/スカラー一致テストも完備。
  > 対象ファイル: `native/nif/src/physics/game_logic/chase_ai.rs`

- **free_list O(1) スポーン/キル（spawn の Vec<usize> 返却）** `+4`
  > `spawn` は `Vec<usize>` で使用スロットを返し、free_list 再利用スロットの誤特定リスクを排除。全エンティティ種別で統一された O(1) 設計。
  > 対象ファイル: `native/nif/src/physics/world/enemy.rs` 等

- **空間ハッシュ衝突検出（FxHashMap・ゼロアロケーション）** `+4`
  > `FxHashMap`（rustc-hash）による高速な空間ハッシュと、`query_nearby_into` でバッファ再利用。動的・静的の分離・2段階フィルタリングが実装されている。
  > 対象ファイル: `native/nif/src/physics/physics/spatial_hash.rs`

- **決定論的 LCG 乱数** `+3`
  > Knuth LCG の定番定数を使用し、`wrapping_mul/add` で安全なオーバーフロー処理。再現性テストも完備。
  > 対象ファイル: `native/nif/src/physics/physics/rng.rs`

---

## native/render — 描画パイプライン

### ✅ プラス点

- **wgpu インスタンス描画（1 draw_indexed で全スプライト）** `+4`
  > `#[repr(C)] + bytemuck::Pod` でGPUバッファへのゼロコピー転送。全スプライトを1回の `draw_indexed` で描画するドローコール最小化設計。
  > 対象ファイル: `native/render/src/renderer/mod.rs`

- **CI 用ヘッドレスレンダラー** `+4`
  > `headless.rs` でオフスクリーンレンダラーを実装。CIでGPUレンダリングをテストできる設計は個人プロジェクトでは極めて珍しい。
  > 対象ファイル: `native/render/src/headless.rs`

- **サブフレーム補間（lerp）のロック外計算** `+3`
  > `prev_tick_ms`/`curr_tick_ms` の差分でフレーム間の経過割合 α を計算し、`clamp(0.0, 1.0)` でオーバーシュートを防止。60fps物理と高フレームレート描画を分離。
  > 対象ファイル: `native/nif/src/physics/world/render_snapshot.rs`

---

## native/audio — オーディオ

### ✅ プラス点

- **コマンドパターン + mpsc::channel 非同期設計** `+3`
  > `AudioCommand` enum と `mpsc::channel` によるコマンド駆動設計。デバイス不在時のグレースフルフォールバックが実装されている。
  > 対象ファイル: `native/audio/src/audio.rs`

- **define_assets! マクロによる SSoT** `+2`
  > ID・パス・埋め込みデータを一箇所に定義。`include_bytes!` でコンパイル時バイナリ埋め込みと実行時ロードの2段階フォールバック。
  > 対象ファイル: `native/audio/src/asset/mod.rs`

---

## native/window — 窓層・イベント管理

### ✅ プラス点

- **イベントループ所有権と RenderBridge 抽象化** `+3`
  > desktop_loop が winit ApplicationHandler を実装し、イベントループの所有権を持つ。RenderBridge トレイトで render と分離。カーソルグラブ制御。
  > 対象ファイル: `native/window/src/desktop_loop.rs`

---

## native/xr — XR層

### ✅ プラス点

- **XrInputEvent 型設計の明確さ** `+1`
  > HeadPose, ControllerPose, ControllerButton, TrackerPose の enum 定義。Hand, ControllerButton の列挙。openxr は optional feature。
  > 対象ファイル: `native/xr/src/lib.rs`

---

## native/app — 統合層

### ✅ プラス点

- **デスクトップエントリの整理** `+2`
  > main.rs で parse_args, GAME_ASSETS_PATH, NetworkRenderBridge, run_desktop_loop を組み立て。--connect, --room, --assets の引数解析。
  > 対象ファイル: `native/app/src/main.rs`

- **環境変数・アセットローダーの統合** `+2`
  > ZENOH_CONNECT, GAME_ASSETS_PATH の設定。loader_for_assets, load_atlas, load_shaders によるアセット取得。
  > 対象ファイル: `native/app/src/main.rs`

---

## native/nif — NIF設計・ブリッジ

### ✅ プラス点

- **NIF 関数カテゴリ分類（ロック競合の予測可能性）** `+4`
  > world_nif・action_nif・read_nif・push_tick_nif・game_loop_nif・render_nif・save_nif の7カテゴリに分類。Rustler の公式ガイドラインを超えた設計。
  > 対象ファイル: `native/nif/src/nif/`

- **ResourceArc による GC 連動ライフタイム管理** `+4`
  > `ResourceArc<GameWorld>` と `ResourceArc<GameLoopControl>` でElixir GCとRustのライフタイムを連動させている。
  > 対象ファイル: `native/nif/src/nif/world_nif.rs`

- **lock_metrics による RwLock 可観測性** `+3`
  > read lock > 300μs / write lock > 500μs で警告、5秒ごとに平均待機時間をレポート。NIFのロック競合を本番環境で観測できる設計。
  > 対象ファイル: `native/nif/src/lock_metrics.rs`

- **DirtyCpu スケジューラ指定** `+3`
  > `#[rustler::nif(schedule = "DirtyCpu")]` で物理演算をBEAMスケジューラに影響させない設計。
  > 対象ファイル: `native/nif/src/nif/push_tick_nif.rs`

- **NifResult によるエラーハンドリングの統一** `+2`
  > `create_world` を除く NIF は `NifResult<T>` で戻り値を統一。Elixir 側で `{:ok, _}` / `{:error, _}` のパターンマッチが可能。`lock_poisoned_err` 等で RwLock の poison を NifResult に変換。
  > 対象ファイル: `native/nif/src/nif/*.rs`

---

## テスト戦略

### ✅ プラス点

- **SIMD/スカラー一致テスト（許容誤差 0.05）** `+4`
  > chase_ai.rs のテストで8体（SIMD 2バッチ）を使い、死亡敵の速度フィールドが変化しないことまで検証。許容誤差設定が正確。
  > 対象ファイル: `native/physics/src/game_logic/chase_ai.rs`

- **StubRoom による NIF 依存の完全排除** `+3`
  > `room_stubs.ex` の `StubRoom` が NIF を起動せずにテストを実行可能。NIF依存を排除したテスト戦略が徹底されている。
  > 対象ファイル: `apps/network/test/support/room_stubs.ex`

---

## 開発者体験（DX）

### ✅ プラス点

- **mix alchemy.ci と GitHub Actions の主要ジョブの対応** `+3`
  > `mix alchemy.ci` が Rust fmt/clippy/test（nif）と Elixir compile/format/credo/test を一括実行し、GHA の rust-check / rust-test / elixir-check / elixir-test と実質対応。`check` オプションでテスト省略も可能。2026-03-28 時点で Windows 上で `RESULT: ALL PASSED` を確認済み。
  > 対象ファイル: `apps/core/lib/mix/tasks/alchemy.ci.ex`, `.github/workflows/ci.yml`

- **PR 向け CI と Protobuf 生成物検証** `+2`
  > `on: pull_request` により PR 上でも同一パイプラインが走る。`proto-verify` ジョブで `mix alchemy.gen.proto` 後の生成物 diff を検証し、Elixir 側の protobuf ドリフトを検出する。
  > 対象ファイル: `.github/workflows/ci.yml`

- **ベンチマーク回帰テスト（main push 時）** `+3`
  > bench-regression ジョブが main push 時に `cargo bench -p nif` を実行し、github-action-benchmark で前回比 110% 超をアラート。
  > 対象ファイル: `.github/workflows/ci.yml`

- **README と development.md による起動手順の明確化** `+2`
  > Prerequisites（Elixir 1.19 / OTP 28, Rust stable, zenohd）が明記。`mix run` / ランチャー / 一括起動の違いが説明されている。
  > 対象ファイル: `README.md`, `development.md`

---

## 可観測性

### ✅ プラス点

- **Telemetry イベントの発行** `+2`
  > `[:game, :frame_dropped]`・`[:game, :session_end]`・`[:game, :boss_spawn]`・`[:game, :level_up]` など、主要なゲームイベントで telemetry を実行。
  > 対象ファイル: `apps/contents/lib/events/game.ex`, `apps/contents/lib/events/game/diagnostics.ex`

---

## プロジェクト全体設計

### ✅ プラス点

- **ドキュメントの品質・網羅性・コードとの一致度** `+5`
  > `vision.md`・`docs/architecture/` が Mermaid ダイアグラム付きで充実しており、コードとの一致度が高い。個人プロジェクトのドキュメント品質としては突出している。
  > 対象ファイル: `docs/`

- **vision.md による設計哲学の明文化** `+4`
  > 「エンジンがこの概念を知る必要があるか？」という設計判断基準が vision.md に明文化されている。Godot の「ノードとシーン」哲学と同等の明確さ。「無限の空間」「ユーザーの存在」が保証範囲であることが明確。Engine と Content の責務分離、Elixir = SSoT / Rust = 実行層の思想が一貫して記述されている。
  > 対象ファイル: `docs/vision.md`
