# AlchemyEngine — 提案（0点）詳細一覧

> 最終更新: 2026-03-23（evaluation-2026-03-23 に基づく）

## 採点基準

| 点数 | 基準 |
|:---:|:---|
| 0 | 現時点では存在しないが、実装すればプロジェクトの価値を高める提案 |

提案点は批判ではなく「次のステップ」として記述する。

---

## apps/core — エンジンコア・OTP設計

### 💡 提案

- **コンポーネントの on_save / on_load コールバック** `0`
  > セーブ対象データをコンポーネントが自己申告する方式。`SaveManager` が各コンポーネントから `on_save/1` を収集し、ロード時に `on_load/2` で復元。バージョン管理・戻り値型の定義が必要。
  > 参考: improvement-plan.md I-K

- **GameEvents への汎用メッセージディスパッチ機構** `0`
  > `handle_info({:boss_dash_end, world_ref}, state)` のようなコンテンツ固有メッセージを、`GameEvents` が直接処理するのではなく、アクティブなコンポーネントに転送する汎用ディスパッチ機構を完全に実装する。例: タグ付きタプル `{:engine_message, tag, payload}` を受け取り、全コンポーネントの `on_engine_message/2` に転送する。新規メッセージ種別追加時に GameEvents の変更が不要になる。

- **SaveManager の HMAC シークレット強制機構** `0`
  > `Application.get_env(:core, :save_hmac_secret)` でデフォルト値を持たせず、未設定時に起動を拒否する。または `runtime.exs` で `System.fetch_env!("SAVE_HMAC_SECRET")` を使い、環境変数未設定時に明確なエラーメッセージで起動を停止する。

- **LiveDashboard 統合** `0`
  > `phoenix_live_dashboard` を追加し、`Core.Telemetry` のメトリクスをリアルタイムで可視化する。`StressMonitor` のフレームバジェット超過率・`lock_metrics` のRwLock待機時間・`EventBus` のメッセージキュー深度をダッシュボードで監視できるようにする。参考: Phoenix LiveDashboard の `Telemetry` ページ。

---

## apps/contents — コンテンツ実装・ゲームロジック

### 💡 提案

- **ContentBehaviour の diagnostics/0 コールバック** `0`
  > 「敵数・弾数」をコンテンツが報告する API を追加。`Diagnostics` が `playing_state` の `:enemies` / `:bullets` を直接参照する代わりに、コンテンツ経由で取得する。
  > 参考: improvement-plan.md I-M

- **EntityParams の Single Source of Truth 化** `0`
  > `entity_params.ex`・`spawn_component.ex` の `boss_params/0`・Rust側の値の3箇所に散在しているパラメータを、`entity_params.ex` のみに集約する。`spawn_component.ex` は `EntityParams.boss_params/0` を呼び出すだけにし、Rust側は `set_entity_params` NIF で受け取るだけにする。これにより「Elixir = SSoT」の原則が完全に実現される。

- **プロパティベーステスト（StreamData）の導入** `0`
  > `stream_data` パッケージを追加し、`LevelSystem.generate_weapon_choices/1`・`BossSystem.check_spawn/2`・`SpawnSystem.maybe_spawn/3` に対してプロパティテストを実装する。例: 「武器選択肢は常に1〜3個」「同じ武器が重複しない」等の不変条件を自動検証する。

- **第3コンテンツの実装（ContentBehaviour の汎用性実証）** `0`
  > VampireSurvivor・AsteroidArena に続く第3のコンテンツ（例: タワーディフェンス・リズムゲーム）を実装することで、`ContentBehaviour` の汎用性をさらに実証する。

---

## apps/network — ネットワーク層

### 💡 提案

- **分散フェイルオーバーと GameEvents → Network ブロードキャスト** `0`
  > 分散ノード間でフェイルオーバーし、`GameEvents` からのイベントを Network 層にブロードキャストする統合。多数プレイヤー保証の実証に寄与する。
  > 参考: improvement-plan.md I-E

- **分散ノード間ルーム移動の実装** `0`
  > Elixir の `Node.connect/1` と `Phoenix.PubSub` の分散モードを使い、複数のBeamノード間でルームを移動できる機能を実装する。これが実現すれば「なぜElixir + Rustか」という問いに対してコードで答えられる。参考: `libcluster`・`Horde.DynamicSupervisor`。

- **UDP の信頼性レイヤー（RUDP）** `0`
  > 現在の UDP 実装はシーケンス番号を持つが、再送・ACK・輻輳制御がない。ゲームの重要なイベント（レベルアップ・ゲームオーバー等）に対して軽量な再送機構を追加することで、パケットロスに対する耐性が向上する。参考: `laminar`（Rust の RUDP ライブラリ）。

---

## native/physics — ECS・SoA・SIMD

### 💡 提案

- **render_interpolation のクライアント側移行** `0`
  > 3D 補間ロジックをサーバー（physics/nif）からクライアント側に移行。フレームに `player_interp` を追加し、desktop_render が補間後の座標で描画する。
  > 参考: improvement-plan.md I-P

- **ARM NEON SIMD 対応** `0`
  > `chase_ai.rs` に `#[cfg(target_arch = "aarch64")]` で ARM NEON 版を追加する。Apple Silicon・Android・Raspberry Pi での性能向上。

- **WASM 対応（`wasm32-unknown-unknown`）** `0`
  > `#[cfg(target_arch = "wasm32")]` でスカラーフォールバックを使い、`rayon` を `wasm-bindgen-rayon` に切り替えることで、ブラウザ上での実行が可能になる。

- **決定論的物理によるリプレイ機能** `0`
  > `SimpleRng` の決定論的設計を活かし、初期シード + 入力列を記録することでリプレイを実現する。

- **ファジングターゲットの追加** `0`
  > `cargo-fuzz` で `decode_enemy_params`・`udp/protocol` のデコード関数・`spatial_hash.rs` の `query_nearby_into` にファズターゲットを追加する。参考: `libfuzzer-sys` クレート。

---

## native/shared — 共通データ

### 💡 提案

- **predict_input の実装** `0`
  > クライアント予測（レイテンシ対策）のため、過去の入力履歴と delta_ms から補間した入力を返す。network 連携後に追加予定とコメントされている。
  > 参考: predict.rs の「詳細な実装は network 連携後に追加予定」

- **Store の実装** `0`
  > スナップショットの過去・現在ペアを保持し、補間用のデータを提供する。network 連携後に追加予定とコメントされている。

## native/xr — XR層

### 💡 提案

- **OpenXR 統合の実装** `0`
  > `run_openxr_loop` に OpenXR インスタンス・ヘッドレスセッション作成、`xrLocateSpace` で head/controller pose 取得、ポーリングループで `on_event` を呼ぶ実装を追加する。XrInputEvent 型は既に定義済み。
  > 参考: lib.rs の TODO コメント

## native/render — 描画パイプライン

### 💡 提案

- **HudData のオーバーレイテキスト・ボタン汎用化** `0`
  > `GamePhase` を廃止し、`:overlay` / `:playing` / `:game_over` のような汎用識別子にする。オーバーレイテキスト・ボタン定義を Elixir 側が渡し、render 層はコンテンツ固有の概念を持たない。
  > 参考: improvement-plan.md I-N

- **build_instances の共通化** `0`
  > `renderer/mod.rs` と `headless.rs` のスプライト種別ごとのUV・サイズ計算ロジックを `pub(crate)` の共通関数に抽出する。`headless.rs` のコメントに「共有の `pub(crate)` 関数を使用」と書いてあるが未実装。これを実装すればDRY違反が解消される。

- **Skeleton/Ghost の専用スプライト追加** `0`
  > アトラスに Skeleton・Ghost 用の専用UVを追加し、Golem・Bat の流用をやめる。「遊べるゲーム」としての視覚的完成度が向上する。

---

## 横断

### テスト戦略

- **SceneStack の ExUnit テスト** `0`
  > push / pop / replace / update_current の遷移ロジックを単体テストでカバー。`async: true` で並列実行可能に。

- **E2E テスト（ゲームループの完結性検証）** `0`
  > 開始→プレイ→終了→リトライの経路を自動化テストで検証。ヘッドレスモードを活用。

### CI・セキュリティ

- **pull_request トリガーの追加** `0`
  > `.github/workflows/ci.yml` に `pull_request:` を追加し、PR作成・更新時にCIが自動実行されるようにする。PRマージ前の品質保証が有効化される。

- **mix audit / cargo audit の CI 組み込み** `0`
  > `mix_audit` と `cargo audit` をCIジョブに追加する。依存パッケージの脆弱性を自動検出し、セキュリティリスクを早期に発見できる。
