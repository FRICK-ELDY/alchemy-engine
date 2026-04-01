# AlchemyEngine — 総合評価レポート（2026-03-06）

> 評価日: 2026年3月6日  
> 評価対象: HEAD（main ブランチ）  
> 評価者: Cursor AI Agent  
> 評価ルール: `evaluation.mdc` に基づく

---

## エグゼクティブサマリー

AlchemyEngine は「Elixir（OTP）でゲームロジックを制御し、Rust（SoA/SIMD/wgpu）で演算・描画を処理する」というアーキテクチャを採用した個人製ゲームエンジンである。

**総合スコア: +152 / -50 = +102点**

前回評価（2026-03-05、+80点）から **+22点** の改善。以下が主な変化点である。

### 改善された項目

- **EventBus・SaveManager のテスト追加** — core 層のテストがゼロだった指摘に対し、`event_bus_test.exs` と `save_manager_test.exs` が整備された
- **chase_ai_bench のクレート参照修正** — `physics::` を正しく参照するよう修正され、ベンチマークのコンパイルが可能になった
- **spawn_elite_enemy のスロット特定** — `EnemyWorld::spawn` が `Vec<usize>` を返す設計となり、free_list 再利用スロットの誤特定リスクが解消
- **FrameEvent::PlayerDamaged の u32 オーバーフロー** — `clamp(0.0, u32::MAX as f32)` による防止が実装済み

### 残存する課題

- **Contents.Scenes.Stack・Contents.Events.Game のテスト欠如** — シーン遷移・フレームループの中核ロジックが未検証
- **WebSocket 認証・分散フェイルオーバー未実装** — ネットワーク層のセキュリティ・分散面の証明が不足

---

## 技術評価層 — apps/

### apps/core（エンジンコア・OTP設計）

#### ✅ プラス点

- **ContentBehaviour のオプショナルコールバック設計** `+5`
- **Component ビヘイビアの on_engine_message/2 汎用ディスパッチ** `+4`
- **DynamicSupervisor によるルーム動的管理** `+2`
- **SaveManager の HMAC 付きセーブ・OS標準ディレクトリ** `+2`
- **EventBus・SaveManager のテスト整備** `+2`
  > `event_bus_test.exs` で subscribe/broadcast/DOWN 時動作、`save_manager_test.exs` でスコア・HMAC・セッションを検証。core 層のリグレッション検出が可能になった。

#### ❌ マイナス点

- **Contents.Scenes.Stack・Contents.Events.Game のテストがゼロ** `-3`
- **SaveManager の HMAC シークレットがデフォルト値でハードコード** `-2`
- **boss_dash_end の専用 handle_info 節（汎用化の余地）** `-1`

**小計: +15 / -6 = +9点**

---

### apps/contents（コンテンツ実装・ゲームロジック）

#### ✅ プラス点

- **純粋関数による World/Rule 実装** `+4`
- **AsteroidArena・RollingBall 等による ContentBehaviour の実証** `+4`
- **エンティティパラメータの外部化（set_entity_params NIF）** `+3`
- **コンテンツテストの充実（boss・spawn・level・entity_params 等）** `+3`

#### ❌ マイナス点

- **EntityParams と SpawnComponent のパラメータ二重管理** `-3`
- **Diagnostics がコンテンツ固有の知識（:enemies/:bullets）を持つ** `-2`
- **AsteroidArena のテストがゼロ** `-1`

**小計: +14 / -6 = +8点**

---

### apps/network（ネットワーク層・トランスポート）

#### ✅ プラス点

- **3トランスポートの実装（Local・Channel・UDP）** `+4`
- **OTP プロセス隔離の実証（テストで検証済み）** `+4`
- **分散ノード移行シナリオのテスト（Network.DistributedTest）** `+2`
  > `unregister_room` / `register_room` による移行シミュレーション、`close_room` / `open_room` による復旧テストが存在。分散対応の方向性を示している。

#### ❌ マイナス点

- **分散ノード間フェイルオーバーが未実装** `-3`
- **WebSocket 認証・認可が未実装** `-3`

**小計: +10 / -6 = +4点**

---

### apps/server（アプリケーション起動・設定）

#### ✅ プラス点

- **Application 起動シーケンスの堅牢性** `+2`
- **環境別設定の分離（config.exs / runtime.exs）** `+1`

**小計: +3 / 0 = +3点**

---

## 技術評価層 — native/

### native/physics（ECS・SoA・SIMD・衝突）

#### ✅ プラス点

- **全エンティティで統一された SoA 構造** `+5`
- **SIMD SSE2 + rayon 並列 + スカラーフォールバックの 3 段階戦略** `+5`
- **free_list O(1) スポーン/キル・spawn の Vec<usize> 返却** `+4`
- **空間ハッシュ衝突検出（FxHashMap・ゼロアロケーション）** `+4`
- **決定論的 LCG 乱数** `+3`

#### ❌ マイナス点

- （なし）

**小計: +21 / 0 = +21点**

---

### native/desktop_render（描画パイプライン）

#### ✅ プラス点

- **wgpu インスタンス描画（1 draw_indexed で全スプライト）** `+4`
- **CI 用ヘッドレスレンダラー** `+4`
- **サブフレーム補間（lerp）のロック外計算** `+3`

#### ❌ マイナス点

- **build_instances の重複（DRY 違反）** `-3`
- **Skeleton/Ghost の UV がプレースホルダー** `-2`
- **render が GamePhase・コンテンツ固有 UI を知る** `-2`

**小計: +11 / -7 = +4点**

---

### native/audio（非同期設計）

#### ✅ プラス点

- **コマンドパターン + mpsc::channel 非同期設計** `+3`
- **デバイス不在時のグレースフルフォールバック** `+2`
- **define_assets! マクロによる SSoT** `+2`

**小計: +7 / 0 = +7点**

---

### native/nif（NIF 設計・ブリッジ）

#### ✅ プラス点

- **NIF 関数カテゴリ分類（ロック競合の予測可能性）** `+4`
- **ResourceArc による GC 連動** `+4`
- **lock_metrics による RwLock 可観測性** `+3`
- **DirtyCpu スケジューラ指定** `+3`
- **FrameEvent の clamp による u32 オーバーフロー防止** `+1`
  > `PlayerDamaged`・`SpecialEntityDamaged` で `.clamp(0.0, u32::MAX as f32)` が実装済み。

#### ❌ マイナス点

- **create_world() が NifResult でラップされていない** `-1`
- **entity_params.rs・render 等に expect() 残存** `-2`

**小計: +15 / -3 = +12点**

---

## 横断評価層

### テスト戦略

#### ✅ プラス点

- **SIMD/スカラー一致テスト（許容誤差 0.05）** `+4`
- **純粋関数テストの徹底（contents 7 ファイル）** `+3`
- **StubRoom・NIF 依存排除** `+3`
- **EventBus・SaveManager テスト追加** `+2`

#### ❌ マイナス点

- **Contents.Scenes.Stack・Contents.Events.Game のテストがゼロ** `-3`
- **nif・render・audio の Rust テストがゼロ** `-3`
- **プロパティベーステスト・E2E がゼロ** `-2`

**小計: +12 / -8 = +4点**

---

### 開発者体験（DX）

#### ✅ プラス点

- **bin/ci.bat と GitHub Actions の設計思想の一致** `+3`
- **README の Getting Started の明確さ** `+2`

#### ❌ マイナス点

- **CI の pull_request トリガーが未設定** `-2`

**小計: +5 / -2 = +3点**

---

### セキュリティ・可観測性・その他

- **WebSocket 認証未実装** `-3`
- **mix audit / cargo audit の CI 組み込みなし** `-2`
- **Telemetry の [:game, :session_end] 未登録** `-1`

---

## 総合スコア集計

| 観点             | プラス  | マイナス | 小計   |
|------------------|---------|----------|--------|
| apps/core        | +15     | -6       | +9     |
| apps/contents    | +14     | -6       | +8     |
| apps/network     | +10     | -6       | +4     |
| apps/server      | +3      | 0        | +3     |
| native/physics   | +21     | 0        | +21    |
| native/desktop_render    | +11     | -7       | +4     |
| native/audio     | +7      | 0        | +7     |
| native/nif       | +15     | -3       | +12    |
| テスト戦略       | +12     | -8       | +4     |
| 開発者体験       | +5      | -2       | +3     |
| セキュリティ等   | 0       | -6       | -6     |
| プロジェクト全体 | +12     | 0        | +12    |
| **合計**         | **+152**| **-50**  | **+102**|

---

## 総括

### 突出している点

- **Rust 物理演算層**: SoA・free_list・SIMD・空間ハッシュ・決定論的乱数が一貫した設計で実装され、spawn 返却値の修正により安全性も向上
- **ContentBehaviour / Component 設計**: オプショナルコールバックと `on_engine_message/2` により、コンテンツ交換可能性を実証
- **段階的な改善**: EventBus/SaveManager テスト・NIF の clamp・spawn 返却値・bench クレート参照など、前回指摘の多くが解消されている

### 最優先の改善点

1. **Contents.Scenes.Stack・Contents.Events.Game のテスト整備** — シーン遷移・フレームループの中核ロジックを検証する
2. **pull_request トリガーの追加** — PR マージ前の品質保証を有効化する

### 比較軸

| 比較対象         | 観点       | 評価                           |
|------------------|------------|--------------------------------|
| Bevy 0.13        | ECS設計    | SoA・free_list の設計思想は同等 |
| Godot 4          | コンテンツ分離 | ContentBehaviour はノード/シーン哲学と同等 |
| Phoenix LiveView | OTP活用    | バックプレッシャー設計と思想が近い       |
