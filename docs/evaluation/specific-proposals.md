# AlchemyEngine — 提案（0点）詳細一覧

## 採点基準

| 点数 | 基準 |
|:---:|:---|
| 0 | 現時点では存在しないが、実装すればプロジェクトの価値を高める提案 |

提案点は批判ではなく「次のステップ」として記述する。

---

## apps/game_engine — エンジンコア・OTP設計

### 💡 提案

- **SceneManager のルーム分離（マルチルーム完全対応）** `0`
  > `SceneManager` を `{GameEngine.SceneManager, room_id}` という名前付きプロセスに変更し、`GameEvents` と同様に `room_id` を持たせる。`DynamicSupervisor` 配下で `GameEvents` と同時に起動・停止することで、マルチルームが完全に機能する。参考: Elixir の `Registry.via_tuple/2` パターン。

- **GameEvents への汎用メッセージディスパッチ機構** `0`
  > `handle_info({:boss_dash_end, world_ref}, state)` のようなコンテンツ固有メッセージを、`GameEvents` が直接処理するのではなく、アクティブなコンポーネントに転送する汎用ディスパッチ機構を実装する。例: `on_engine_message/2` コールバックを `Component` ビヘイビアに追加し、`GameEvents` は受信したメッセージを全コンポーネントに転送するだけにする。

- **SaveManager の HMAC シークレット強制機構** `0`
  > `Application.get_env(:game_engine, :save_hmac_secret)` でデフォルト値を持たせず、未設定時に起動を拒否する。または `runtime.exs` で `System.fetch_env!("GAME_SAVE_HMAC_SECRET")` を使い、環境変数未設定時に明確なエラーメッセージで起動を停止する。

- **LiveDashboard 統合** `0`
  > `phoenix_live_dashboard` を追加し、`GameEngine.Telemetry` のメトリクスをリアルタイムで可視化する。`StressMonitor` のフレームバジェット超過率・`lock_metrics` のRwLock待機時間・`EventBus` のメッセージキュー深度をダッシュボードで監視できるようにする。参考: Phoenix LiveDashboard の `Telemetry` ページ。

---

## apps/game_content — コンテンツ実装・ゲームロジック

### 💡 提案

- **EntityParams の Single Source of Truth 化** `0`
  > `entity_params.ex`・`spawn_component.ex` の `boss_params/0`・Rust側の値の3箇所に散在しているパラメータを、`entity_params.ex` のみに集約する。`spawn_component.ex` は `EntityParams.boss_params/0` を呼び出すだけにし、Rust側は `set_entity_params` NIF で受け取るだけにする。これにより「Elixir = SSoT」の原則が完全に実現される。

- **プロパティベーステスト（StreamData）の導入** `0`
  > `stream_data` パッケージを追加し、`LevelSystem.generate_weapon_choices/1`・`BossSystem.check_spawn/2`・`SpawnSystem.maybe_spawn/3` に対してプロパティテストを実装する。例: 「武器選択肢は常に1〜3個」「同じ武器が重複しない」「ボスは同一種別が2回スポーンしない」等の不変条件を自動検証する。参考: `StreamData.integer/0`・`StreamData.list_of/1`。

- **第3コンテンツの実装（ContentBehaviour の汎用性実証）** `0`
  > VampireSurvivor・AsteroidArena に続く第3のコンテンツ（例: タワーディフェンス・リズムゲーム）を実装することで、`ContentBehaviour` の汎用性をさらに実証する。特に「ターン制」や「固定視点」など、現在の物理エンジンの前提を覆すコンテンツが実装できれば、エンジンの柔軟性の証明になる。

---

## apps/game_network — ネットワーク層

### 💡 提案

- **分散ノード間ルーム移動の実装** `0`
  > Elixir の `Node.connect/1` と `Phoenix.PubSub` の分散モードを使い、複数のBeamノード間でルームを移動できる機能を実装する。これが実現すれば「なぜElixir + Rustか」という問いに対してコードで答えられる。参考: `libcluster` による自動クラスタリング・`Horde.DynamicSupervisor` によるクラスター全体のプロセス管理。

- **WebSocket 認証（Phoenix.Token）** `0`
  > `Phoenix.Token.sign/3` でサーバーサイドトークンを生成し、`channel.ex` の `join/3` で `Phoenix.Token.verify/4` を使って検証する。トークンの有効期限・ルームIDのスコープ制限を実装することで、不正参加を防止できる。参考: Phoenix の公式ドキュメント「Authentication」。

- **UDP の信頼性レイヤー（RUDP）** `0`
  > 現在の UDP 実装はシーケンス番号を持つが、再送・ACK・輻輳制御がない。ゲームの重要なイベント（レベルアップ・ゲームオーバー等）に対して軽量な再送機構を追加することで、パケットロスに対する耐性が向上する。参考: `laminar`（Rust の RUDP ライブラリ）。

---

## native/game_physics — ECS・SoA・SIMD

### 💡 提案

- **ARM NEON SIMD 対応** `0`
  > `chase_ai.rs` に `#[cfg(target_arch = "aarch64")]` で ARM NEON 版を追加する。`vld1q_f32`・`vmulq_f32`・`vrsqrteq_f32` を使った NEON 実装により、Apple Silicon・Android・Raspberry Pi での性能が向上する。参考: `std::arch::aarch64` モジュール。

- **WASM 対応（`wasm32-unknown-unknown`）** `0`
  > `#[cfg(target_arch = "wasm32")]` でスカラーフォールバックを使い、`rayon` を `wasm-bindgen-rayon` に切り替えることで、ブラウザ上での実行が可能になる。`game_render` の `wgpu` は WebGPU バックエンドをサポートしているため、理論上は実現可能。参考: `wasm-pack`・`wgpu` の WebGPU バックエンド。

- **決定論的物理によるリプレイ機能** `0`
  > `SimpleRng` の決定論的設計を活かし、初期シード + 入力列を記録することでリプレイを実現する。`SaveManager` にリプレイデータの保存・再生機能を追加することで、バグ再現・スピードラン・観戦モードが可能になる。

- **ファジングターゲットの追加** `0`
  > `cargo-fuzz` で `decode_enemy_params`・`udp/protocol.rs` のデコード関数・`spatial_hash.rs` の `query_nearby_into` にファズターゲットを追加する。特にUDPプロトコルのデコードは外部入力を受け取るため、ファジングによるクラッシュ発見が重要。参考: `libfuzzer-sys` クレート。

---

## native/game_render — 描画パイプライン

### ✅ 提案

- **フラスタムカリング** `0`
  > カメラ視野外のエンティティをインスタンスバッファに追加しない最適化。現在は全エンティティ（最大14510個）を毎フレームGPUに転送しているが、カメラ範囲外のエンティティをCPU側でフィルタリングすることで、GPUバンド幅と頂点シェーダーの負荷を削減できる。

- **テクスチャアトラス自動生成ツール** `0`
  > スプライト画像から自動的にテクスチャアトラスとUV座標テーブルを生成するビルドスクリプトを追加する。現在はUV座標が `renderer/mod.rs` にハードコードされており、スプライト追加のたびに手動でUV計算が必要。参考: `texture-packer` クレート。

- **レンダーグラフ設計** `0`
  > 現在の単一パスレンダリングを、パーティクル・HUD・ポストエフェクト等を独立したパスで処理するレンダーグラフ設計に移行する。参考: Bevy の `RenderGraph`・wgpu の `RenderBundle`。

---

## native/game_audio — オーディオ

### 💡 提案

- **ボイスリミット・優先度システム** `0`
  > 同時再生数の上限（例: SE 最大16チャンネル）と優先度（BGM > 重要SE > 環境SE）を実装する。現在は `mpsc::channel` に無制限にコマンドを送れるため、大量の敵が同時に死亡した際に音が重なる可能性がある。

- **空間オーディオ（パン・距離減衰）** `0`
  > プレイヤーとサウンド発生源の距離・方向に基づいてパンニングと音量を調整する空間オーディオを実装する。`PlaySeWithPosition(AssetId, f32, f32)` コマンドを追加し、`cpal` の出力バッファで左右チャンネルを独立して制御する。

---

## テスト戦略

### 💡 提案

- **GameEngine コアのテスト整備（SceneManager・GameEvents・EventBus）** `0`
  > `improvement-plan.md` の I-F に対応。`GameEngine.SceneManager` のシーン遷移・`GameEvents` のフレームループ・`EventBus` のサブスクライバー配信を `ExUnit` でテストする。`NifBridgeMock`（Mox）を使えばNIF依存なしにテスト可能。参考: `apps/game_engine/test/support/mocks.ex` に既に `NifBridgeMock` が定義されている。

- **NIF デコードロジックの Rust ユニットテスト** `0`
  > `game_nif` の `decode_enemy_params`・`decode_weapon_params`・`decode_boss_params` は Erlang Term のデコードロジックであり、GPUなしでテスト可能。`rustler::types::tuple::get_tuple` 等のデコードパスをユニットテストすることで、パラメータ注入の信頼性が向上する。

---

## 可観測性・デバッグ容易性

### 💡 提案

- **Prometheus + Grafana 統合** `0`
  > `telemetry_metrics_prometheus` パッケージを追加し、`[:game, :tick, :physics_ms]`・`[:game, :frame_dropped, :count]`・`lock_metrics` のRwLock待機時間をPrometheusエンドポイントで公開する。Grafanaダッシュボードで物理演算の性能劣化・フレームドロップ率・ロック競合を可視化できる。

- **OpenTelemetry トレーシング** `0`
  > `opentelemetry` パッケージを追加し、ゲームセッション全体のトレースを記録する。`GameEvents.handle_info` → `on_frame_event` → `on_nif_sync` の処理チェーンをスパンとして記録することで、ボトルネックの特定が容易になる。

---

## セキュリティ・配布可能性

### 💡 提案

- **mix audit / cargo audit の CI 組み込み** `0`
  > `.github/workflows/ci.yml` に `mix_audit` と `cargo audit` のジョブを追加する。`mix_audit` は `mix deps.audit`、`cargo audit` は `cargo install cargo-audit && cargo audit` で実行できる。依存パッケージの既知脆弱性を自動検出する。

- **GitHub Releases + クロスコンパイルビルド** `0`
  > `cross` クレートと GitHub Actions の `matrix` 戦略を使い、Windows/macOS/Linux 向けのバイナリを自動ビルドして GitHub Releases に公開する。`mix release` で Elixir リリースを作成し、Rust NIF を同梱することで、Erlang/Elixir 未インストール環境でも動作するスタンドアロン配布物を作成できる。

---

## プロジェクト全体設計

### 💡 提案

- **visual-editor-architecture.md の実装着手** `0`
  > `docs/visual-editor-architecture.md`（245行）に詳細な設計が記述されているビジュアルエディタを実装する。`Phoenix LiveView` + `wgpu` のヘッドレスレンダラーを組み合わせることで、ブラウザ上でコンテンツをリアルタイム編集できるエディタが実現できる。これが完成すれば「エンジン」としての価値命題が大幅に向上する。

- **CHANGELOG.md の整備** `0`
  > バージョン履歴・破壊的変更・新機能を記録する `CHANGELOG.md` を追加する。`git-cliff` を使って `Conventional Commits` から自動生成することで、メンテナンスコストを最小化できる。
