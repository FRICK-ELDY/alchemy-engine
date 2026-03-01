# AlchemyEngine — 具体的なマイナス点

> 評価日: 2026-03-01（第2回）  
> 評価対象: プロジェクト全体（Elixir + Rust 全レイヤー）

| スコア | 基準 |
|:---:|:---|
| -1 | 改善余地あり。動作はするが設計・品質上の軽微な問題 |
| -2 | 重要な機能・設計の欠如。放置すると将来の拡張を阻害する |
| -3 | 設計上の明確な欠陥。バグ・クラッシュ・性能劣化を引き起こしうる |
| -4 | プロジェクトの価値命題を損なう重大な欠如 |
| -5 | プロジェクトの根幹を揺るがす致命的な欠陥 |

---

## Elixir 層

### `GameEvents` の残存課題

- **`GameEvents`（426行）のテストがゼロ** `-3`
  > IP-01 リファクタリングにより 697行→426行に削減されたが、依然としてテストが存在しない。フレームイベント処理・シーン遷移・NIF 呼び出し順序・セーブ/ロード連携のいずれも自動検証されていない。バックプレッシャー機構（`@backpressure_threshold 120`）の動作も未テスト。プロジェクトで最も重要なモジュールのテストが皆無であることは設計上の明確な欠陥。  
  > 対象ファイル: `apps/game_engine/lib/game_engine/game_events.ex`

- **`SceneManager` / `EventBus` / 全シーンモジュールのテストがゼロ** `-2`
  > シーンスタックの push/pop/replace ロジック、EventBus のサブスクライバー配信、各シーンの `update/2` 純粋関数部分がすべて未テスト。`game_engine` アプリのテストカバレッジは事実上ゼロ。将来の拡張を阻害する。  
  > 対象ディレクトリ: `apps/game_engine/test/`（`test_helper.exs` と `support/mocks.ex` のみ）

---

### NIF の残存課題

- **`create_world()` NIF が `NifResult` を返さない** `-2`
  > `pending-issues.md` に記録済みの課題。`create_world()` が失敗した場合の Elixir 側エラーハンドリングが存在しない。`GameServer.Application.start/2` での `raise` 使用と合わせて、起動失敗時の OTP 互換エラー処理が不完全。将来の拡張を阻害する。  
  > 対象ファイル: `native/game_nif/src/nif/world_nif.rs`、`apps/game_server/lib/game_server/application.ex:37`

- **NIF バージョニング・ABI 互換性チェックがない** `-2`
  > Rust NIF と Elixir コードのバージョンが一致しているかを起動時に検証する仕組みがない。NIF の ABI が変わった際に実行時クラッシュが発生するまで気づけない。将来の拡張を阻害する。

---

### ネットワーク層の残存課題

- **複数ルームの同時起動が実証されていない** `-2`
  > `GameNetwork.Local` の実装は完成しているが、`GameServer.Application` が起動するのは `:main` の 1 ルームのみ。`game_network_local_test.exs` での OTP 隔離テストは `StubRoom` を使用しており、実際の `GameEvents` プロセスを複数起動した際の動作が未検証。将来の拡張を阻害する。

- **WebSocket 認証が未実装** `-2`
  > `GameNetwork.UserSocket.connect/3` が全接続を無条件に受け入れる。`pending-issues.md` に「フェーズ3以降でトークン検証を追加する想定」と記載されているが、現状は認証なしで本番デプロイできない。将来の拡張を阻害する。  
  > 対象ファイル: `apps/game_network/lib/game_network/user_socket.ex:19-21`

- **ラグ補償・ロールバック netcode がない** `-2`
  > UDP トランスポートは実装されているが、パケットロス・遅延への対処（ラグ補償・ロールバック）がない。マルチプレイヤーゲームとして実用化するには必須の機能。将来の拡張を阻害する。

---

### クラッシュ回復

- **NIF パニック後のゲームループ再起動ロジックが存在しない** `-2`
  > `GameEvents` がクラッシュして Supervisor が再起動しても、前のプロセスが保持していた Rust `GameWorld` リソースは失われる。チェックポイント/リストア機構がなく、クラッシュ後に既知の良い状態から再開できない。将来の拡張を阻害する。

---

## Rust 層

### プラットフォーム対応

- **SIMD パスが x86_64 専用で ARM NEON 実装がない** `-2`
  > `update_chase_ai_simd` は SSE2 専用。Apple Silicon（M1/M2/M3）・ARM サーバー・モバイル環境では rayon フォールバックになる。`#[cfg(target_arch = "x86_64")]` で分岐しており、ARM NEON への拡張が考慮されていない。将来の拡張を阻害する。  
  > 対象ファイル: `native/game_physics/src/game_logic/chase_ai.rs:135`

- **WASM / `#[no_std]` ターゲットへの準備がゼロ** `-2`
  > `game_physics` の依存が最小限なので技術的には可能だが、`cfg` フラグも feature ゲートも存在しない。将来の拡張を阻害する。

---

### スプライト・アセット

- **スプライトアトラスの UV 座標がマジックナンバーで散在している** `-2`
  > `renderer/mod.rs` と `renderer/ui.rs` にピクセルオフセットがハードコードされている。新しいスプライトを追加するには UV 計算を手動で行い複数箇所を編集する必要があり、将来の拡張を阻害する。  
  > 対象ファイル: `native/game_render/src/renderer/mod.rs:80-99`

- **Ghost・Skeleton の UV が `TODO` プレースホルダー** `-2`
  > `// TODO: assign correct UV` コメントが残存しており、これらの敵が現在のビルドで正しいスプライトで表示されていない。未完成の視覚表現がそのまま残っており、将来の拡張を阻害している。  
  > 対象ファイル: `native/game_render/src/renderer/mod.rs:259-266`

---

### 描画パイプライン

- **毎フレーム `Vec` アロケーション（描画インスタンス）** `-2`
  > `update_instances` 内で `Vec::with_capacity(...)` を毎フレーム生成している。`Renderer` 構造体に `instances: Vec<SpriteInstance>` フィールドを持ち再利用することで、ホットパスのアロケーションを排除できる。将来の拡張を阻害する。  
  > 対象ファイル: `native/game_render/src/renderer/mod.rs:744`

- **レンダーグラフ・明示的パス依存宣言がない** `-2`
  > スプライトパス → egui HUD パスの依存関係が暗黙的。Bevy の `RenderGraph` や wgpu の `RenderPass` 依存宣言に相当する明示的な管理がなく、パスの追加・変更時に依存関係を手動で管理する必要がある。将来の拡張を阻害する。

- **フラスタムカリングがない** `-2`
  > カメラビューポート外のエンティティもスナップショットに含まれ、GPU に転送される。敵数が増加した場合のパフォーマンス劣化を引き起こしうる。  
  > 対象ファイル: `native/game_nif/src/render_snapshot.rs`

- **egui HUD ロジックがレンダリングバックエンドと結合** `-2`
  > `ui.rs` の egui ウィジェットロジックが `renderer/mod.rs` の wgpu バックエンドと直接結合している。HUD レイアウトの変更がレンダラーの変更を要求する。将来の拡張を阻害する。

---

### オーディオ

- **ボイスリミット・優先度システムがない** `-2`
  > SE が大量に発生するとシンクオブジェクトが無制限に生成される。ゲームプレイ中の爆発・敵撃破 SE が大量発生した際のパフォーマンス劣化を引き起こしうる。  
  > 対象ファイル: `native/game_audio/src/audio.rs:53-60`

- **BGM ファイルがリポジトリに存在しない** `-2`
  > `AssetId::Bgm` に対応する BGM ファイルが `assets/` ディレクトリに存在しない。BGM なしのゲームプレイが現状の実態であり、コンテンツの充実度が低い。

- **空間オーディオが未実装** `-1`
  > SE の発生位置に基づく距離減衰がない。ゲームプレイの没入感を向上させる機能として軽微な欠如。

---

### 物理層

- **ARM NEON の SIMD 実装がない** `-2`
  > x86_64 専用 SIMD の問題と同じ。ARM 環境でのパフォーマンスが rayon フォールバックに依存する。

- **広域フェーズに BVH / AABB ツリーがない** `-2`
  > 空間ハッシュは実装されているが、動的オブジェクトの広域フェーズ衝突検出に BVH（Bounding Volume Hierarchy）がない。エンティティ数が増加した場合の衝突検出コストが線形増加する。将来の拡張を阻害する。

- **物理ステップ実行順序が暗黙的でドキュメントがない** `-1`
  > `physics_step.rs` の実行順序（プレイヤー移動 → 障害物押し出し → Chase AI → 敵分離 → 衝突 → 武器 → パーティクル → アイテム → 弾丸 → ボス）がコードにのみ存在し、ドキュメント化されていない。改善提案 IP-11 で対応予定だが未着手。  
  > 対象ファイル: `native/game_physics/src/game_logic/physics_step.rs`

---

### NIF 設計

- **`set_hud_state` が毎フレーム write lock を取得** `-1`
  > HUD 状態（スコア・キルカウント）が変化しないフレームでも write lock を取得している。改善提案 IP-10 で対応予定だが未着手。  
  > 対象ファイル: `apps/game_content/lib/game_content/vampire_survivor/level_component.ex:177-186`

- **Rust → Elixir メールボックスへのバックプレッシャーがない（Rust 側）** `-1`
  > IP-04 で Elixir 側のバックプレッシャーは実装されたが、Rust 側から Elixir へのフレームイベント送信レートを制御する仕組みがない。Elixir 側がドロップした場合でも Rust は 60Hz で送信し続ける。軽微な改善余地。

- **`decode_fire_pattern` のサイレントフォールバック** `-1`
  > 未知のパターン文字列が `FirePattern::Aimed` にフォールバックするため、設定ミスが検出されない。  
  > 対象ファイル: `native/game_nif/src/nif/world_nif.rs:259-270`

---

## コンポーネント層

- **`on_physics_process` が実質 `on_process` と同一レート** `-1`
  > `on_physics_process` は毎フレーム呼び出されており、Godot の `_physics_process`（固定レート）と `_process`（可変レート）の区別がない。将来的に物理レートと描画レートを分離する際に設計変更が必要になる。

- **コンポーネント依存性注入・サービスロケーターがない** `-2`
  > コンポーネント間の依存関係が `GameEngine.NifBridge` への直接呼び出しで解決されており、テスト時のモック差し替えが `Application.get_env` 経由に依存している。Unity の `GetComponent<T>()` や Bevy の `Res<T>` に相当する依存性注入がない。将来の拡張を阻害する。

---

## ユーザー層

- **ゲーム内設定 UI がない** `-2`
  > BGM 音量・SE 音量・フルスクリーン切り替え等の設定を変更する UI がない。改善提案 IP-02 で対応予定だが未着手。

- **セーブ形式が Erlang バイナリ term（非ポータブル）** `-2`
  > `:erlang.term_to_binary / :erlang.binary_to_term` を使用しているため、Elixir バージョン間・プラットフォーム間でのセーブデータ互換性が保証されない。改善提案 IP-09 で JSON/MessagePack 移行が提案されているが未着手。  
  > 対象ファイル: `apps/game_engine/lib/game_engine/save_manager.ex`

- **決定論的乱数があるにもかかわらずリプレイが未実装** `-1`
  > LCG 乱数による決定論的物理が実装されているにもかかわらず、リプレイ録画・再生システムが存在しない。改善提案 IP-03 で対応予定だが未着手。

---

## プロジェクト全体設計

- **`visual-editor-architecture.md` が存在しないシステムを記述** `-1`
  > ビジュアルエディタは実装されていないにもかかわらず、詳細なアーキテクチャドキュメントが存在する。ドキュメントとコードの乖離が生じている。

- **`improvement-plan.md` の完了済み項目管理** `-1`
  > 前回評価時に指摘した「完了済みと進行中の混在」は IP-13 対応で改善されたが、`docs/evaluation/completed-improvements.md` がまだ作成されていない。完了済み項目のアーカイブ先が存在しない。

- **Elixir → Rust フルラウンドトリップのベンチマークがない** `-2`
  > `game_physics` の Rust ユニットベンチマークは存在するが、`set_hud_state → physics_step → drain_frame_events` のフルサイクルを計測するベンチマークがない。NIF オーバーヘッドの定量的把握ができない。改善提案 IP-08 で対応予定だが未着手。

- **`LevelComponent` のアイテムドロップ重複ロジック（潜在バグ）** `-3`
  > `on_event({:entity_removed, ...})` と `on_frame_event({:enemy_killed, ...})` の両方でアイテムドロップが発生する可能性がある。1回の敵撃破でアイテムが2個ドロップするバグが潜在している。バグ・クラッシュを引き起こしうる設計上の欠陥。  
  > 対象ファイル: `apps/game_content/lib/game_content/vampire_survivor/level_component.ex:80-96` と `:285-298`

- **プロセス辞書によるダーティフラグ管理（テスト困難）** `-1`
  > `LevelComponent` と `BossComponent` が `Process.put/get` でダーティフラグを管理している。プロセス辞書はデバッグが困難で、テストでの状態リセットが必要になる。  
  > 対象ファイル: `apps/game_content/lib/game_content/vampire_survivor/level_component.ex:177-186`、`boss_component.ex:83-87`
