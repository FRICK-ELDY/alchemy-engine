# AlchemyEngine — 提案（0点）詳細一覧

> 最終更新: 2026-03-07（evaluation-2026-03-07 に基づく）

## 採点基準

| 点数 | 基準 |
|:---:|:---|
| 0 | 現時点では存在しないが、実装すればプロジェクトの価値を高める提案 |

提案点は批判ではなく「次のステップ」として記述する。

---

## apps/core — エンジンコア・OTP設計

### 💡 提案

- **GameEvents への汎用メッセージディスパッチ機構** `0`
  > `handle_info({:boss_dash_end, world_ref}, state)` のようなコンテンツ固有メッセージを、`GameEvents` が直接処理するのではなく、アクティブなコンポーネントに転送する汎用ディスパッチ機構を完全に実装する。例: タグ付きタプル `{:engine_message, tag, payload}` を受け取り、全コンポーネントの `on_engine_message/2` に転送する。新規メッセージ種別追加時に GameEvents の変更が不要になる。

- **SaveManager の HMAC シークレット強制機構** `0`
  > `Application.get_env(:core, :save_hmac_secret)` でデフォルト値を持たせず、未設定時に起動を拒否する。または `runtime.exs` で `System.fetch_env!("SAVE_HMAC_SECRET")` を使い、環境変数未設定時に明確なエラーメッセージで起動を停止する。

- **LiveDashboard 統合** `0`
  > `phoenix_live_dashboard` を追加し、`Core.Telemetry` のメトリクスをリアルタイムで可視化する。`StressMonitor` のフレームバジェット超過率・`lock_metrics` のRwLock待機時間・`EventBus` のメッセージキュー深度をダッシュボードで監視できるようにする。参考: Phoenix LiveDashboard の `Telemetry` ページ。

---

## apps/contents — コンテンツ実装・ゲームロジック

### 💡 提案

- **EntityParams の Single Source of Truth 化** `0`
  > `entity_params.ex`・`spawn_component.ex` の `boss_params/0`・Rust側の値の3箇所に散在しているパラメータを、`entity_params.ex` のみに集約する。`spawn_component.ex` は `EntityParams.boss_params/0` を呼び出すだけにし、Rust側は `set_entity_params` NIF で受け取るだけにする。これにより「Elixir = SSoT」の原則が完全に実現される。

- **プロパティベーステスト（StreamData）の導入** `0`
  > `stream_data` パッケージを追加し、`LevelSystem.generate_weapon_choices/1`・`BossSystem.check_spawn/2`・`SpawnSystem.maybe_spawn/3` に対してプロパティテストを実装する。例: 「武器選択肢は常に1〜3個」「同じ武器が重複しない」等の不変条件を自動検証する。

- **第3コンテンツの実装（ContentBehaviour の汎用性実証）** `0`
  > VampireSurvivor・AsteroidArena に続く第3のコンテンツ（例: タワーディフェンス・リズムゲーム）を実装することで、`ContentBehaviour` の汎用性をさらに実証する。

---

## apps/network — ネットワーク層

### 💡 提案

- **分散ノード間ルーム移動の実装** `0`
  > Elixir の `Node.connect/1` と `Phoenix.PubSub` の分散モードを使い、複数のBeamノード間でルームを移動できる機能を実装する。これが実現すれば「なぜElixir + Rustか」という問いに対してコードで答えられる。参考: `libcluster`・`Horde.DynamicSupervisor`。

- **UDP の信頼性レイヤー（RUDP）** `0`
  > 現在の UDP 実装はシーケンス番号を持つが、再送・ACK・輻輳制御がない。ゲームの重要なイベント（レベルアップ・ゲームオーバー等）に対して軽量な再送機構を追加することで、パケットロスに対する耐性が向上する。参考: `laminar`（Rust の RUDP ライブラリ）。

---

## native/physics — ECS・SoA・SIMD

### 💡 提案

- **ARM NEON SIMD 対応** `0`
  > `chase_ai.rs` に `#[cfg(target_arch = "aarch64")]` で ARM NEON 版を追加する。Apple Silicon・Android・Raspberry Pi での性能向上。

- **WASM 対応（`wasm32-unknown-unknown`）** `0`
  > `#[cfg(target_arch = "wasm32")]` でスカラーフォールバックを使い、`rayon` を `wasm-bindgen-rayon` に切り替えることで、ブラウザ上での実行が可能になる。

- **決定論的物理によるリプレイ機能** `0`
  > `SimpleRng` の決定論的設計を活かし、初期シード + 入力列を記録することでリプレイを実現する。

- **ファジングターゲットの追加** `0`
  > `cargo-fuzz` で `decode_enemy_params`・`udp/protocol` のデコード関数・`spatial_hash.rs` の `query_nearby_into` にファズターゲットを追加する。参考: `libfuzzer-sys` クレート。

---

## native/render — 描画パイプライン

### 💡 提案

- **build_instances の共通化** `0`
  > `renderer/mod.rs` と `headless.rs` のスプライト種別ごとのUV・サイズ計算ロジックを `pub(crate)` の共通関数に抽出する。`headless.rs` のコメントに「共有の `pub(crate)` 関数を使用」と書いてあるが未実装。これを実装すればDRY違反が解消される。

- **Skeleton/Ghost の専用スプライト追加** `0`
  > アトラスに Skeleton・Ghost 用の専用UVを追加し、Golem・Bat の流用をやめる。「遊べるゲーム」としての視覚的完成度が向上する。

---

## 横断

### 💡 提案

- **pull_request トリガーの追加** `0`
  > `.github/workflows/ci.yml` に `pull_request:` を追加し、PR作成・更新時にCIが自動実行されるようにする。PRマージ前の品質保証が有効化される。

- **mix audit / cargo audit の CI 組み込み** `0`
  > `mix_audit` と `cargo audit` をCIジョブに追加する。依存パッケージの脆弱性を自動検出し、セキュリティリスクを早期に発見できる。
