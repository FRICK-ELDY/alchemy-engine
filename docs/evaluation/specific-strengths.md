# AlchemyEngine — 具体的なプラス点

> 評価日: 2026-03-01（第2回）  
> 評価対象: プロジェクト全体（Elixir + Rust 全レイヤー）

| スコア | 基準 |
|:---:|:---|
| +1 | 正しい |
| +2 | 良い判断 |
| +3 | 平均を上回る |
| +4 | プロダクション水準 |
| +5 | 個人プロジェクトで見たことがない |

---

## Elixir 層

### OTP 設計

- **`:one_for_one` Supervisor ツリーの正しい構成** `+2`
  > `GameServer.Application` が Registry / SceneManager / InputHandler / EventBus / RoomSupervisor / StressMonitor / Stats / Telemetry を `:one_for_one` で管理。各プロセスが独立してクラッシュ・再起動できる正しい設計。

- **DynamicSupervisor + Registry による複数ルーム先行設計** `+3`
  > `GameEngine.RoomSupervisor`（DynamicSupervisor）と `GameEngine.RoomRegistry`（Registry）の組み合わせで、`{:via, Registry, {GameEngine.RoomRegistry, room_id}}` による名前付きプロセスを実現。ルームの動的追加・削除が O(1) で可能な設計。

- **`StressMonitor` が独立プロセスとして存在する** `+2`
  > 監視プロセスがクラッシュしてもゲームが継続する設計が意図的に実装されており、ドキュメントにも明記されている。

- **5 つの独立 GenServer による責務分離** `+3`
  > `GameEvents`（ディスパッチ）/ `SceneManager`（シーン管理）/ `EventBus`（Pub/Sub）/ `InputHandler`（入力）/ `Stats`（統計）が独立した GenServer として分離されており、各プロセスの責務が明確。

---

### ContentBehaviour 設計

- **`ContentBehaviour` によるコンテンツ完全交換（2 コンテンツ実証済み）** `+5`
  > `VampireSurvivor` と `AsteroidArena` という性質の異なる 2 コンテンツが同一エンジン上で動作することを実証。`config.exs` の 1 行変更でコンテンツが切り替わる設計は、「エンジンはコンテンツを知らない」という原則の完全な実証。個人プロジェクトでこのレベルの抽象化が実証済みなのは見たことがない。

- **`Component` ビヘイビアのオプショナルコールバック設計** `+2`
  > `on_ready / on_frame_event / on_physics_process / on_nif_sync / on_event` が全てオプショナルで、コンポーネントは必要なコールバックのみ実装すればよい。Unity の `MonoBehaviour` に相当する設計が正しく実現されている。

- **`SceneBehaviour` 遷移戻り値の型安全設計** `+2`
  > `{:continue, state}` / `{:transition, :pop, state}` / `{:transition, {:push, mod, arg}, state}` / `{:transition, {:replace, mod, arg}, state}` という明示的な遷移戻り値型が、シーン遷移ロジックを安全かつ読みやすくしている。

---

### Elixir as SSoT

- **Elixir as SSoT フェーズ 1〜5 の完遂** `+4`
  > ゲームロジック制御フロー・シーン管理・パラメータ・ボス AI がすべて Elixir 側に存在し、Rust 側にゲームルールがハードコードされていない。`GameWorldInner` から HUD/ルール固有フィールドを排除し、Elixir からの注入パターンを一貫して適用している。

- **ボス AI ロジックが Elixir 側に存在（SSoT 最難関の適用）** `+4`
  > ボスの速度・ダッシュ・タイマーを Elixir 側で計算し、`set_boss_velocity` NIF で注入するという設計は、「Rust にゲームルールをハードコードしない」原則の最難関の適用。ボス AI が Elixir の `BossComponent.on_physics_process/1` に完全に存在する。

- **`:telemetry` による観測性** `+2`
  > `frame_dropped` / `frame_processed` / `nif_call` 等のイベントが `:telemetry` で計測されており、`ConsoleReporter` で可視化される。

---

### バックプレッシャー機構

- **メールボックス深度監視によるフレームドロップ制御** `+4`
  > `@backpressure_threshold 120`（60Hz × 2 秒分）を超えた場合、NIF 書き込み・ブロードキャスト等の重い副作用をスキップしつつ、スコア・HP 等のゲーム整合性に影響するイベント処理は継続するという設計。Elixir の `Process.info(self(), :message_queue_len)` を活用した実用的な実装。同規模の個人プロジェクトでここまで精緻なバックプレッシャー制御を実装しているケースは稀。

---

### ネットワーク層

- **`GameNetwork.Local` によるローカルマルチルーム実証** `+4`
  > `local.ex`（275 行）が `open_room / close_room / connect_rooms / disconnect_rooms / broadcast` を完全実装。`game_network_local_test.exs` で OTP 隔離テスト（一方のルームがクラッシュしても他方が継続する）が実証されており、Elixir を選んだ根拠が初めてコードとして証明された。

- **Phoenix Channels / WebSocket トランスポート実装** `+3`
  > `channel.ex`（159 行）が `"room:*"` トピックへの join・input/action ハンドリング・フレームイベントブロードキャストを実装。Phoenix の `handle_in/handle_info` パターンが正しく使用されている。

- **UDP トランスポート実装** `+3`
  > `udp/server.ex`（263 行）が `:gen_udp` ベースの UDP サーバーを実装。バイナリプロトコルのエンコード/デコードが `protocol.ex` のバイナリパターンマッチで完全に表現されており、`case` 文なしに全パケット種別を処理している。

---

### その他 Elixir の強み

- **UDP プロトコルのバイナリパターンマッチ** `+3`
  > `protocol.ex` で `<<@type_join, seq::32, room_id::binary>>` 等のバイナリパターンマッチを使用。Elixir の真価を最も直接的に示す実装の一つ。

- **`FrameCache` の `read_concurrency: true`** `+2`
  > ETS テーブルを `read_concurrency: true` で作成し、複数プロセスからの並行読み取りを最適化。書き込みは GenServer で直列化、読み取りは直接 ETS から行うホットパス最適化が正しく実装されている。

- **HMAC 署名付きセーブデータ** `+3`
  > `SaveManager` が HMAC-SHA256 署名を付与し、タイミング攻撃対策として定数時間比較（`:crypto.hash_equals/2`）を使用。セーブデータの改ざん検出が正しく実装されている。

---

## Rust 層

### SoA ECS 設計

- **全エンティティ種別の完全 SoA ECS 設計** `+4`
  > `EnemyWorld` / `BulletWorld` / `ParticleWorld` / `ItemWorld` がすべて SoA（Structure of Arrays）形式で実装されており、CPU キャッシュ効率が最大化されている。Bevy ECS と同等の思想を手書きで実現。

- **`free_list` による O(1) スポーン/キル** `+3`
  > スロット管理に `free_list: Vec<usize>` を使用し、エンティティのスポーン・キルが O(1) で行われる。`Vec` の再アロケーションが発生しない設計。

---

### SIMD 実装

- **SSE2 SIMD 4 体並列 Chase AI** `+4`
  > `update_chase_ai_simd`（`chase_ai.rs`）が `_mm_rsqrt_ps`（逆平方根）と `_mm_loadu_ps` を使用して 4 体の敵 AI を並列処理。`alive_mask` による死亡敵の速度フィールド保護が正しく実装されている。

- **`alive_mask` による死亡敵の速度フィールド保護** `+4`
  > `alive: Vec<u8>` を 0xFF（生存）/ 0x00（死亡）で管理し、`_mm_cmpeq_epi8` + `_mm_unpacklo_epi8` × 2 でバイトマスク → dword マスクに展開。SIMD レーンの書き戻しを alive フラグで保護するテクニックは高度。

- **SIMD / rayon / スカラーの 3 段階適応戦略** `+3`
  > x86_64 では SIMD、`RAYON_THRESHOLD`（500 体）以上では rayon 並列、それ以下ではシングルスレッドスカラーという 3 段階の適応戦略。`#[cfg(not(target_arch = "x86_64"))]` でのフォールバックも完備。

- **SIMD/スカラー一致テストの存在** `+4`
  > `simd_and_scalar_produce_same_result` テストが SIMD 版とスカラー版の等価性を検証。unsafe コードの正当性を自動テストで保証している。

---

### 空間ハッシュ

- **`FxHashMap` 空間ハッシュによる O(n) 衝突検出** `+4`
  > `spatial_hash.rs` が `FxHashMap`（rustc-hash）を使用した空間ハッシュを実装。O(n²) の総当たり衝突検出を O(n) に削減。

---

### 決定論的物理

- **LCG 決定論的乱数（リプレイ/同期の基盤）** `+5`
  > `SimpleRng` が `wrapping_mul` + `wrapping_add` による LCG（線形合同法）を実装。シード固定で完全再現可能な乱数列を生成。リプレイ・ネットワーク同期の正しい基盤。個人プロジェクトで決定論的乱数を意図的に実装しているケースは稀。

---

### NIF 設計

- **`ResourceArc` による Elixir GC 連動ライフタイム管理** `+5`
  > `GameWorld` を `ResourceArc<RwLock<GameWorldInner>>` として Elixir プロセスが保持。Elixir GC が参照カウントを管理し、Elixir 側でリソースが不要になった時点で Rust 側のメモリが自動解放される。Rustler の最も高度な機能を正しく活用。

- **RwLock 競合時間の閾値監視（300μs / 500μs）** `+3`
  > `lock_metrics.rs` が read lock 待機 > 300μs / write lock 待機 > 500μs で `log::warn!` を発行。5 秒ごとに平均待機時間をレポート。パフォーマンス劣化を早期検出できる。

- **`game_physics` の依存が 3 クレートのみ** `+3`
  > `rustc-hash` / `rayon` / `log` のみ。外部依存の最小化により、将来の WASM 対応・クロスコンパイルの障壁が低い。

---

### ヘッドレスレンダラー

- **wgpu オフスクリーンレンダリングによる CI 対応** `+4`
  > `headless.rs`（715 行）が wgpu のオフスクリーンターゲットへの描画を実装。ウィンドウなしで PNG バイト列を返すことができ、CI でのレンダリング回帰テストが可能になった。`image` クレートによる PNG エンコードも含む本格実装。

---

## Elixir × Rust 連携

- **NIF 関数の 5 カテゴリ分類（ロック競合の予測可能性）** `+5`

  | カテゴリ | ロック種別 | 頻度 |
  |:---|:---:|:---:|
  | `control` | write | 低頻度 |
  | `inject` | write | 高頻度 |
  | `query_light` | read | 高頻度 |
  | `snapshot_heavy` | write | 低頻度 |
  | `game_loop` | write | 60Hz |

  > この 5 カテゴリ分類がロック競合パターンを予測可能にしている。設計意図がドキュメントにも明記されている。

- **60Hz Rust ループ → `OwnedEnv::send_and_clear` → Elixir** `+3`
  > Rust の 60Hz ゲームループが `OwnedEnv::send_and_clear` で Elixir プロセスにフレームイベントを送信する設計。Rustler の非同期メッセージ送信を正しく活用。

- **パラメータ注入パターン（Rust にゲームバランス値なし）** `+5`
  > `EntityParams`（HP・速度・EXP 報酬等）が Elixir の `entity_params.ex` で定義され、`set_entity_params` NIF で Rust 側に注入される。Rust コードにゲームバランス値が一切ハードコードされていない。

- **`NifBridgeBehaviour` + Mox による NIF モック** `+4`
  > `NifBridgeBehaviour` ビヘイビアが定義されており、テスト時に `Mox` で NIF をモックできる。NIF を含むコードのユニットテストが可能になる正しい設計。

---

## 物理層

- **7 種の `FirePattern`（正確な幾何学計算）** `+4`
  > `Aimed` / `Spread` / `Ring` / `Chain` / `Boomerang` / `Orbit` / `Whip` の 7 種が実装されており、各パターンの幾何学計算（角度・速度ベクトル）が正確。

- **ボス速度・タイマーの Elixir 注入（SSoT 最難関）** `+4`
  > ボスの速度・ダッシュ判定・タイマーが Elixir 側で計算され、`set_boss_velocity` NIF で注入される。Rust 側にボス AI ロジックが存在しない。

---

## 描画層

- **wgpu インスタンス描画（最大 14,502 エントリ）** `+3`
  > `MAX_INSTANCES = 14510` の静的バッファを確保し、1 ドローコールで全スプライトを描画。インスタンス描画による GPU 効率化が正しく実装されている。

- **サブフレーム補間（lerp）がロック外で計算される** `+4`
  > `render_snapshot.rs` でのサブフレーム補間（`alpha = (now - prev) / (curr - prev)`）が RwLock 外で計算される。ロック保持時間を最小化する正しい設計。

- **WGSL スプライトシェーダー（レガシー GLSL なし）** `+2`
  > モダンな WGSL シェーダーを使用。OpenGL/GLSL への依存がなく、wgpu の設計思想に沿っている。

---

## オーディオ層

- **コマンドパターン + `mpsc::channel` 完全非同期** `+3`
  > `AudioCommandSender` が `mpsc::Sender` をラップし、呼び出し元がノンブロッキングで SE/BGM を再生できる。オーディオスレッドが専用スレッドで動作する正しい設計。

- **デバイス不在時のグレースフルフォールバック** `+4`
  > デバイス初期化失敗時も `AudioCommandSender` を返し、コマンドが無視されるだけでゲームが継続する。CI 環境・ヘッドレス環境での動作を保証。

- **4 段階フォールバックのアセット探索** `+2`
  > `include_bytes!` / 実行ファイル相対パス / カレントディレクトリ / `assets/` ディレクトリの 4 段階でアセットを探索。開発環境・本番環境の両方で動作する。

---

## コンポーネント層

- **Unity 相当のライフサイクルコールバック** `+3`
  > `on_ready / on_frame_event / on_physics_process / on_nif_sync / on_event` という Unity の `Start / Update / FixedUpdate` に相当するライフサイクルが正しく実装されている。

- **シーンスタック（push / pop / replace）完全実装** `+3`
  > `SceneManager` が push / pop / replace の 3 種のシーン遷移を実装。`LevelUp` シーンが `Playing` シーンの上に push され、`pop` で戻るという設計が正しく動作している。

- **`pause_on_push?/1` によるシーン別ポーズ制御** `+2`
  > `ContentBehaviour` の `pause_on_push?/1` で、シーンが push された際に物理演算をポーズするかどうかをコンテンツ側で制御できる。`LevelUp` シーン中は物理演算が停止する。

---

## プロジェクト全体設計

- **11 ファイル・約 1,500 行のドキュメント（Mermaid 図付き）** `+5`
  > `architecture-overview.md` / `elixir-layer.md` / `rust-layer.md` / `data-flow.md` / `game-content.md` / `vision.md` / `pending-issues.md` / `visual-editor-architecture.md` / `improvement-plan.md` / `ci.md` 等が Mermaid シーケンス図・フローチャート付きで整備されている。個人プロジェクトとして異例の水準。

- **自己認識的な弱点管理（improvement-plan / pending-issues）** `+3`
  > `pending-issues.md` が未解決課題を管理し、`improvement-plan.md` が改善提案を優先度付きで整理。評価→改善→アーカイブのサイクルが機能している。

- **Umbrella プロジェクトによるアプリ境界の明確化** `+2`
  > `game_engine` / `game_content` / `game_network` / `game_server` の 4 アプリが Umbrella で管理され、依存関係が明示的。

- **Rust ワークスペース + `"nif"` フィーチャーフラグ** `+2`
  > `game_physics` が `"nif"` フィーチャーフラグで NIF 依存を分離。`cargo test -p game_physics` が BEAM VM なしで実行できる。

- **`game_content` 純粋関数テストが `async: true` で並列実行可能** `+2`
  > `SpawnSystem` / `BossSystem` / `LevelSystem` / `EntityParams` の純粋関数テストが `async: true` で並列実行される。

- **Rust `chase_ai.rs` の充実した単体テスト** `+4`
  > SIMD/スカラー一致テスト・LCG 再現性テスト・境界値テストが `#[cfg(test)]` モジュールに整備されている。

- **GitHub Actions CI パイプライン（5 ジョブ）** `+4`

  | ジョブ | 内容 |
  |:---|:---|
  | `rust-check` | fmt + clippy -D warnings |
  | `rust-test` | game_physics ユニットテスト |
  | `elixir-check` | compile + format + credo |
  | `elixir-test` | NIF 込み統合テスト |
  | `bench-regression` | main ブランチのみ、+10% 劣化でブロック |

  > ベンチマーク回帰チェックまで含む CI は個人プロジェクトとして高水準。

- **ローカル CI スクリプト（`bin/ci.bat`）** `+2`
  > GitHub Actions と同等のチェックをローカルで実行できる `bin/ci.bat` が整備されている。
