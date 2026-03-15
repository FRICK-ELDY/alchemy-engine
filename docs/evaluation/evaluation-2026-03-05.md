# AlchemyEngine — 総合評価レポート（2026-03-05）

> 評価日: 2026年3月5日  
> 評価対象: HEAD（main ブランチ）  
> 評価者: Cursor AI Agent  
> 評価ルール: `evaluation.mdc` に基づく

---

## エグゼクティブサマリー

AlchemyEngine は「Elixir（OTP）でゲームロジックを制御し、Rust（SoA/SIMD/wgpu）で演算・描画を処理する」というアーキテクチャを採用した個人製ゲームエンジンである。

**総合スコア: +148 / -68 = +80点**

前回評価（2026-03-01）から、`Contents.SceneStack` へのシーン管理移行・`Contents.Events.Game` へのイベント層移行・`on_engine_message/2` 汎用ディスパッチの導入により、アーキテクチャの一貫性が向上している。**Rust 物理演算層（SoA・SIMD・free_list）とContentBehaviour のオプショナルコールバック設計**は、プロダクションレベルのゲームエンジンと比較しても遜色ない。

一方で、**bin/ci.bat の未通過**（README の品質保証と実態の乖離）・**Elixir エンジンコアのテスト欠如**・**NIF の expect/unwrap 残存**が、プロジェクトの信頼性を損なう課題として残っている。

---

## 技術評価層 — apps/

### apps/core（エンジンコア・OTP設計・コンポーネント）

#### ✅ プラス点

- **ContentBehaviour のオプショナルコールバック設計** `+5`
- **Component ビヘイビアの on_engine_message/2 汎用ディスパッチ** `+4`
- **DynamicSupervisor によるルーム動的管理** `+2`
- **SaveManager の HMAC 付きセーブ・OS標準ディレクトリ** `+2`

#### ❌ マイナス点

- **Contents.SceneStack・GameEvents・EventBus・SaveManager のテストがゼロ** `-4`
- **SaveManager の HMAC シークレットがデフォルト値でハードコード** `-2`
- **boss_dash_end の専用 handle_info 節（汎用化の余地）** `-1`

**小計: +13 / -7 = +6点**

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
  > `Network.Local`（272行）が RoomSupervisor 連携・connect_rooms・broadcast を実装。Channel・UDP も Protocol 含め実装済み。
- **OTP プロセス隔離の実証（テストで検証済み）** `+4`

#### ❌ マイナス点

- **分散ノード間フェイルオーバーが未実装** `-3`
  > 複数 BEAM ノード間のルーム移動・libcluster によるクラスタリングが未実装。「なぜ Elixir + Rust か」の分散面の証明が不十分。
- **WebSocket 認証・認可が未実装** `-3`

**小計: +8 / -6 = +2点**

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
- **free_list O(1) スポーン/キル** `+4`
- **空間ハッシュ衝突検出（FxHashMap・ゼロアロケーション）** `+4`
- **決定論的 LCG 乱数** `+3`

#### ❌ マイナス点

- **bench/chase_ai_bench.rs のクレート名不一致（コンパイル不可）** `-3`
- **spawn_elite_enemy の脆弱なスロット特定ロジック** `-3`
- **FrameEvent::PlayerDamaged の u32 オーバーフローリスク** `-2`
- **#[cfg(target_arch = "x86_64")] の pub use 漏れ** `-2`

**小計: +21 / -10 = +11点**

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

#### ❌ マイナス点

- **create_world() が NifResult でラップされていない** `-1`
- **entity_params.rs・render 等に expect() 残存** `-2`

**小計: +14 / -3 = +11点**

---

## 横断評価層

### テスト戦略

#### ✅ プラス点

- **SIMD/スカラー一致テスト（許容誤差 0.05）** `+4`
- **純粋関数テストの徹底（contents 7 ファイル）** `+3`
- **StubRoom・NIF 依存排除** `+3`

#### ❌ マイナス点

- **core 層のテストがゼロ** `-4`
- **nif・render・audio の Rust テストがゼロ** `-3`
- **プロパティベーステスト・E2E がゼロ** `-2`

**小計: +10 / -9 = +1点**

---

### 開発者体験（DX）

#### ✅ プラス点

- **bin/ci.bat と GitHub Actions の設計思想の一致** `+3`
- **README の Getting Started の明確さ** `+2`

#### ❌ マイナス点

- **bin/ci.bat がエラーゼロで通過しない** `-4`
  > cargo fmt / clippy で失敗。評価ルールの DX 原則に違反。
- **CI の pull_request トリガーが未設定** `-2`

**小計: +5 / -6 = -1点**

---

### セキュリティ・可観測性・その他

- **WebSocket 認証未実装** `-3`
- **mix audit / cargo audit の CI 組み込みなし** `-2`
- **Telemetry の [:game, :session_end] 未登録** `-1`

---

## 総合スコア集計


| 観点             | プラス      | マイナス    | 小計      |
| -------------- | -------- | ------- | ------- |
| apps/core      | +13      | -7      | +6      |
| apps/contents  | +14      | -6      | +8      |
| apps/network   | +8       | -6      | +2      |
| apps/server    | +3       | 0       | +3      |
| native/physics | +21      | -10     | +11     |
| native/desktop_render  | +11      | -7      | +4      |
| native/audio   | +7       | 0       | +7      |
| native/nif     | +14      | -3      | +11     |
| テスト戦略          | +10      | -9      | +1      |
| 開発者体験          | +5       | -6      | -1      |
| セキュリティ・可観測性    | 0        | -6      | -6      |
| プロジェクト全体設計     | +12      | 0       | +12     |
| **合計**         | **+148** | **-68** | **+80** |


---

## 総括

### 突出している点

- **Rust 物理演算層**: SoA・free_list・SIMD・空間ハッシュ・決定論的乱数が一貫した設計で実装されている
- **ContentBehaviour / Component 設計**: オプショナルコールバックと `on_engine_message/2` により、コンテンツ交換可能性を実証
- **ドキュメント**: vision.md・improvement-plan による自己改善サイクル

### 最優先の改善点

1. **I-0: bin/ci.bat の完全通過** — README の保証と実態を一致させる
2. **core 層のテスト整備** — SceneStack・GameEvents・SaveManager のユニットテスト
3. **spawn_elite_enemy・FrameEvent::PlayerDamaged** — 既知のバグ修正

### 比較軸


| 比較対象             | 観点      | 評価                             |
| ---------------- | ------- | ------------------------------ |
| Bevy 0.13        | ECS設計   | SoA・free_list の設計思想は同等         |
| Godot 4          | コンテンツ分離 | ContentBehaviour はノード/シーン哲学と同等 |
| Phoenix LiveView | OTP活用   | バックプレッシャー設計と思想が近い              |
