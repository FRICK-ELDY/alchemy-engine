# AlchemyEngine — 具体的なプラス点

> 評価日: 2026-03-01
> 評価対象: プロジェクト全体（Elixir + Rust 全レイヤー）
>
> 採点基準: +1（正しい）/ +2（良い判断）/ +3（平均を上回る）/ +4（プロダクション水準）/ +5（個人プロジェクトで見たことがない）

---

## Elixir の真価

### OTP Supervisor ツリーの設計

**`GameServer.Application` が `:one_for_one` で正しく構成されている** +2
Registry → SceneManager → InputHandler → EventBus → RoomSupervisor → GameEvents → StressMonitor → Stats → Telemetry の順で起動。各プロセスが独立した障害ドメインを持ち、1つが落ちても他に波及しない。起動順序の依存関係も正しく設計されている。

**`DynamicSupervisor` + `Registry` による複数ルーム設計が先行実装されている** +3
`RoomSupervisor`（DynamicSupervisor）と `RoomRegistry`（Registry）が実装済み。ネットワーク層が完成すれば即座に複数ルームを起動できる設計になっており、将来の拡張を見越した先行投資として評価できる。同規模プロジェクトでここまで先を見越した設計をしているケースは少ない。

**`StressMonitor` が独立プロセスとして存在する** +2
負荷監視を専用 GenServer に切り出している。監視ロジックがゲームループに混入しておらず、責務が明確に分離されている。

### GenServer の責務分離

**5つの独立した GenServer が明確な役割を持つ** +3
`GameEvents`（ゲームループ）、`SceneManager`（シーンスタック）、`EventBus`（pub/sub）、`InputHandler`（入力）、`Stats`（統計）がそれぞれ独立した GenServer として実装されている。1つの GenServer に複数の責務を詰め込む「神 GenServer」アンチパターンを意識的に回避しており、同規模プロジェクトの平均を上回る設計。

### Behaviour による拡張性

**`ContentBehaviour` によるコンテンツ完全交換が実証済み** +5
`config.exs` の1行変更で VampireSurvivor と AsteroidArena が切り替わる。エンジンコアを一切変更せずに全く異なるゲームが動作することを2コンテンツで実証している。「エンジンとコンテンツの分離」という思想を設計だけでなく動作する実装として証明しており、このクラスの個人プロジェクトでここまで徹底されているケースはほぼ見たことがない。

**`Component` ビヘイビアのコールバックがすべてオプショナル** +2
`@optional_callbacks` により、コンポーネントは必要なコールバックだけを実装すればよい。不要なコールバックの空実装を強制しない設計は、API 設計として正しい判断。

**`SceneBehaviour` の遷移戻り値が型安全** +2
`{:continue, state}` / `{:transition, :pop, state}` / `{:transition, {:push, mod, arg}, state}` / `{:transition, {:replace, mod, arg}, state}` という明示的なタグ付きタプルで遷移を表現。パターンマッチで網羅性が保証される。

### Elixir as SSoT の徹底

**フェーズ1〜5の SSoT 移行が完了している** +4
score / kill_count / elapsed_ms（フェーズ1）→ player_hp / player_max_hp（フェーズ2）→ level / exp / weapon_levels（フェーズ3）→ boss_hp / boss_kind_id（フェーズ4）→ render_started / UI アクション（フェーズ5）と段階的に Elixir 側へ権威を移した。Rust にゲームロジックが漏れていない。段階的移行を完遂した規律と一貫性はプロダクションレベルの設計管理に匹敵する。

**ボス AI ロジックが Elixir 側に存在する** +4
`BossSystem`（Elixir）がボスの出現スケジュール・速度・タイマーを制御し、Rust には毎フレーム速度を注入する。「Rust は演算層、Elixir は制御層」という原則が最も難しいボス AI においても守られている。SSoT 原則の最難関の適用例であり、妥協せずに実装しきった点はプロダクション水準の設計判断。

### Telemetry

**`:telemetry` によるフレーム処理時間・NIF 呼び出しレイテンシの計測** +2
`GameEngine.Telemetry` が `:telemetry` イベントを発行し、`GameEngine.Stats` が集計する。Elixir エコシステムの標準的な観測性パターンに従っており、将来 Prometheus 等への接続が容易。

---

## Rust の真価

### SoA ECS 設計

**`EnemyWorld` / `BulletWorld` / `ParticleWorld` / `ItemWorld` が完全 SoA** +4
全エンティティ種別で `positions_x: Vec<f32>`, `positions_y: Vec<f32>` のように座標・速度・HP を分離した配列で保持。CPU キャッシュラインに同種データが連続して乗るため、全敵イテレーション時のキャッシュミスが最小化される。Bevy ECS と同等の思想を手書きで実現しており、プロダクションゲームエンジンと比較しても遜色ない設計。

**`free_list: Vec<usize>` による O(1) スポーン/キル** +3
死亡エンティティのインデックスを `free_list` に積み、スポーン時に再利用する。Vec の末尾削除も再アロケーションもなく、10,000 体規模でもスポーン/キルのコストが一定。同規模プロジェクトでこの最適化を正しく実装しているケースは少ない。

### SIMD 最適化

**SSE2 SIMD による 4 体並列 Chase AI** +4
`update_chase_ai_simd` が `_mm_set1_ps` / `_mm_loadu_ps` / `_mm_rsqrt_ps` / `_mm_storeu_ps` を使い、4 体分の距離・正規化・速度更新を1ループで処理。`_mm_rsqrt_ps` による高速逆平方根はゲームエンジンの Chase AI 実装として教科書的な最適化であり、プロダクションレベルの実装。

**`alive_mask` による死亡敵の速度フィールド保護** +4
SIMD レーンに死亡敵が混入しても、`alive_mask` でブレンドして速度フィールドを上書きしない。SIMD 実装でこの保護を正しく実装しているケースは少なく、バグを埋め込みやすい箇所を正確に処理している。プロダクションゲームエンジンでも見落とされることがある細部。

**SIMD / rayon / スカラーの 3 段階適応戦略** +3
x86_64 では SIMD、非 x86_64 では rayon 並列、`RAYON_THRESHOLD = 500` 未満ではスカラーシングルスレッドと自動切り替え。プラットフォームと規模に応じて最適なコードパスを選ぶ設計は同規模プロジェクトの平均を明確に上回る。

**SIMD 版とスカラー版の一致テストが存在する** +4
`simd_and_scalar_produce_same_result` テストが `alive_mask` の速度保護も含めて検証している。SIMD 実装の正確性を自動テストで保証しているプロジェクトはプロダクションレベルでも少なく、個人プロジェクトでは極めて稀。

### 空間ハッシュ

**`FxHashMap` ベース空間ハッシュによる O(n) 衝突検出** +4
セルサイズ 80px の空間ハッシュで近傍クエリを O(1) に抑え、全体を O(n) で処理。`rustc-hash::FxHashMap` は標準 `HashMap` より 30〜50% 高速なハッシュ関数を使用。10,000 体規模で O(n²) を避けるための正しい選択であり、プロダクション水準の実装。

### 決定論的物理

**LCG 決定論的乱数（シード固定）** +5
`SimpleRng` が線形合同法（LCG）で実装されており、同じシードから同じ乱数列が再現される。スポーン位置・ドロップ・ウェーブ選択がすべてこの乱数を通る。リプレイシステムとネットワーク同期（ロールバック netcode）の正しい基盤であり、将来の機能拡張への先行投資として個人プロジェクトでここまで意識されているケースはほぼ見たことがない。

### メモリ安全性

**`ResourceArc<GameWorld>` による Elixir GC 連動ライフタイム管理** +5
Rust の `GameWorld` が `ResourceArc` でラップされ、Elixir プロセスが保持している間は解放されない。プロセス死亡時に自動解放。Rustler の最も重要なパターンを正しく使用しており、メモリリークとダングリングポインタの両方を防いでいる。Elixir/Rust 連携プロジェクトでこのパターンを正確に理解して実装しているケースは個人プロジェクトでは見たことがない。

### 観測性

**RwLock 競合時間の閾値監視（300μs / 500μs）** +3
`lock_metrics.rs` が read lock > 300μs / write lock > 500μs で `log::warn!` を発行し、5秒ごとに平均レポートを出力。本番環境でのロック競合を検出するための仕組みがゲームループに組み込まれており、同規模プロジェクトの平均を上回る観測性。

### 依存関係の最小化

**`game_physics` の依存が `rustc-hash` / `rayon` / `log` のみ** +3
物理演算クレートに重量フレームワークが入っていない。コンパイル時間が短く、WASM や組み込みへの移植可能性が高い。依存を意識的に絞る判断は同規模プロジェクトの平均を上回る長期メンテナンス性への投資。

---

## Elixir × Rust 連携の真価

### NIF 境界の設計

**NIF 関数が 5 カテゴリに明確に分類されている** +5
`control`（write・低頻度）/ `inject`（write・毎フレーム）/ `query_light`（read・毎フレーム）/ `snapshot_heavy`（write・明示操作）/ `game_loop`（write・60Hz）という分類により、ロック競合の予測可能性が高い。NIF の境界設計としてここまで整理されているプロジェクトは個人・商用問わず見たことがない。

**60Hz Rust ループ → `OwnedEnv::send_and_clear` → Elixir** +3
Rust のゲームループが専用 OS スレッドで 60Hz 動作し、フレームイベントを `OwnedEnv::send_and_clear` で Elixir プロセスに送信。Elixir スケジューラのジッターが物理ティックに影響しない設計は同規模プロジェクトの平均を上回る。

**パラメータ注入パターン（Rust にゲームバランス値がない）** +5
エンティティの HP・速度・EXP 報酬・ボス HP がすべて `set_entity_params` NIF で Elixir から注入される。Rust コードを変更せずにゲームバランスを調整できる。「Rust は演算エンジン、Elixir はゲームデザイナー」という役割分担の完全な実現であり、個人プロジェクトでここまで徹底されているケースはほぼ見たことがない。

### テスタビリティ

**`NifBridgeBehaviour` + Mox による NIF モック** +4
`GameEngine.NifBridgeBehaviour` が NIF 契約をビヘイビアとして定義し、`test/support/mocks.ex` が Mox ベースのモックを提供。実際の NIF をロードせずに Elixir ゲームロジックの単体テストが可能。NIF を持つプロジェクトでこのモック戦略を実装しているケースはプロダクションレベルでも少ない。

---

## 物理層

### 武器システム

**7 種の `FirePattern` が正しい幾何学計算で実装されている** +4
`Aimed`（最近接敵への扇状）/ `FixedUp`（固定方向）/ `Radial`（全方向放射）/ `Whip`（扇形直接判定）/ `Aura`（周囲オーラ）/ `Piercing`（貫通弾）/ `Chain`（連鎖電撃）の 7 種。Vampire Survivor の武器アーキタイプを網羅しており、それぞれ異なる幾何学的計算が正確に実装されている。プロダクション水準の武器システム。

### 衝突・分離

**障害物押し出しが最大 5 回反復で収束保証** +2
`obstacle_resolve.rs` が最大 5 パスで押し出しを繰り返す。薄い壁へのトンネリングを防ぐ収束保証付きの実装。

**敵分離アルゴリズムによるスタック防止** +2
`separation.rs` が敵同士の重なりを解消。視認性とゲームプレイの公平性を保つ。

### ボス物理

**ボス速度・タイマーが Elixir から毎フレーム注入される** +4
`set_boss_velocity` NIF でボスの移動速度を Elixir から制御。ボス AI ロジックが Elixir（`BossSystem`）に存在し、Rust は物理積分のみを担う。SSoT 原則の最も難しい適用例をプロダクション水準で正しく実装している。

---

## 描画層

### GPU 描画

**wgpu によるスプライトインスタンス描画（最大 14,502 エントリ）** +3
スプライトをインスタンスバッファで一括 GPU 送信。ドローコール数を最小化し、10,000 体規模の描画を現実的なフレームレートで処理できる。同規模プロジェクトの平均を上回る描画設計。

**サブフレーム補間（lerp）がロック外で計算される** +4
`lerp(prev_pos, curr_pos, alpha)` を RwLock の外で計算することで、60Hz 物理ティックと任意のリフレッシュレートのデカップリングを実現。物理ティックとレンダリングの分離を正しく実装しているプロジェクトはプロダクションレベルでも少なく、これがあるとないとでは滑らかさが全く異なる。

### シェーダー

**WGSL スプライトシェーダー（レガシー GLSL なし）** +2
WebGPU 標準の WGSL を使用。将来の WASM/ブラウザ対応への移行コストが低い。良い判断。

---

## オーディオ層

### アーキテクチャ

**コマンドパターン + `mpsc::channel` による完全非同期オーディオ** +3
`AudioCommand` enum を `mpsc::channel` で専用スレッドに送信。ゲームループがオーディオ処理でブロックされない。同規模プロジェクトの平均を上回る非同期設計。

**オーディオデバイス不在時のグレースフルフォールバック** +4
デバイスが利用不可（ヘッドレスサーバー、CI 環境）でも `AudioCommandSender` が返り、送信は無視される。ゲームがクラッシュしない。CI でのテスト実行を可能にするプロダクション品質の設計判断。

### アセット管理

**4 段階フォールバックのアセット探索** +2
`assets/{game_name}/...` → `assets/...` → カレントディレクトリ → `include_bytes!` コンパイル時埋め込みの順で探索。開発環境と配布ビルドの両方に対応する実用的な設計。

---

## コンポーネント層

### ライフサイクル

**Unity 相当のライフサイクルコールバック（on_ready / on_process / on_physics_process / on_event）** +3
Unity の `Start` / `Update` / `FixedUpdate` / `OnEvent` に対応するコールバックを Elixir ビヘイビアで実現。ゲームエンジン経験者が即座に理解できる設計であり、同規模プロジェクトの平均を上回る。

### シーン管理

**シーンスタック（push / pop / replace）の完全実装** +3
`SceneBehaviour` が push / pop / replace の 3 種の遷移を返せる。Godot や LibGDX と同等のシーンスタックパターン。ポーズ画面・レベルアップ選択・ボスアラートが push/pop で正しく実装されており、同規模プロジェクトの平均を上回る。

**`pause_on_push?/1` によるシーン別ポーズ制御** +2
push 時に下のシーンを停止するかどうかをコンテンツ側が制御できる。レベルアップ選択中はゲームを止め、ボスアラートは止めない、という挙動の差異をエンジン変更なしで実現。良い設計判断。

---

## ユーザー層

### セーブシステム

**HMAC 署名付きセーブデータ** +3
`:erlang.term_to_binary` でシリアライズし HMAC で署名。改ざんされたセーブファイルをロード時に検出して拒否する。セキュリティへの配慮が同規模プロジェクトの平均を上回る。

**上位 10 件のハイスコア管理** +1
`Stats` がソート済みトップ 10 リーダーボードをセッション間で永続化。正しく実装されている。

---

## プロジェクト全体設計

### ドキュメント

**11 ファイル・約 1,500 行の設計ドキュメント（Mermaid 図付き）** +5
`vision.md` / `architecture-overview.md` / `elixir-layer.md` / `rust-layer.md` / `data-flow.md` / `game-content.md` / `strengths.md` / `improvement-plan.md` / `pending-issues.md` / `visual-editor-architecture.md` が存在。起動シーケンス・ゲームループ・セーブ/ロードフローが Mermaid シーケンス図で可視化されている。個人プロジェクトでこの水準のドキュメントを維持しているケースは見たことがない。

**自己認識的な弱点管理（`improvement-plan.md` / `pending-issues.md`）** +3
既知の弱点が優先度・影響範囲・作業ステップ付きで文書化されている。完了済み課題がストライクスルーで記録されており、改善の軌跡が追える。同規模プロジェクトの平均を上回る自己管理能力。

### アーキテクチャ

**Umbrella プロジェクトによるアプリケーション境界の明確化** +2
`game_engine` / `game_content` / `game_server` / `game_network` が独立した Elixir アプリとして分離。依存方向が明示的に宣言されており、循環依存がない。良い判断。

**Rust ワークスペース + `"nif"` フィーチャーフラグ** +2
`game_physics` が `"nif"` フィーチャーなしでスタンドアロンコンパイル可能。ベンチマーク・単体テストを NIF なしで実行できる。良い判断。

### テスト

**`game_content` の純粋関数テストが `async: true` で並列実行可能** +2
NIF 依存のない純粋関数のみをテスト対象としており、テストが高速かつ安定。良い設計判断。

**Rust `chase_ai.rs` に SIMD/スカラー一致テストを含む充実した単体テスト** +4
`update_chase_moves_enemy_toward_player` / `update_chase_velocity_magnitude_equals_speed` / `find_nearest_enemy_returns_closest` / `find_nearest_enemy_ignores_dead` / `simd_and_scalar_produce_same_result` の 5 テストが `#[cfg(test)]` ブロックで実装。物理演算の正確性が自動検証されており、プロダクション水準のテスト品質。
