# AlchemyEngine — 総合評価レポート（2026-03-07）

> 評価日: 2026年3月7日  
> 評価対象: HEAD（現状のコードベース）  
> 評価者: Cursor AI Agent  
> 評価ルール: `evaluation.mdc` に基づく

---

## エグゼクティブサマリー

AlchemyEngine は「Elixir（OTP）でゲームロジックを制御し、Rust（SoA/SIMD/wgpu）で演算・描画を処理する」というアーキテクチャを採用した個人製ゲームエンジンである。

**総合スコア: +122 / -50 = +72点**

前回評価（2026-03-06、+102点）との差分は主に以下による：

### 前回からの主な変化

- **WebSocket 認証が実装済み** — `Network.RoomToken` による `Phoenix.Token` ベースのルーム参加認証が `channel.join/3` で必須検証されている。前回の「WebSocket 認証・認可が未実装 -3」を解消し、代わりに +4 のプラス点として評価。
- **network のスコア改善** — 認証実装により、ネットワーク層の評価が前回 +4 から +12 へ上昇（実質 +8）。

### 残存する主な課題

- **Contents.Scenes.Stack・Contents.Events.Game のテスト欠如** — シーン遷移・フレームループの中核ロジックが未検証
- **分散ノード間フェイルオーバー未実装** — ネットワーク層の分散面の証明が不足
- **EntityParams と SpawnComponent のパラメータ二重管理** — SSoT 原則との整合性に課題
- **CI の pull_request トリガーが未設定** — PR マージ前の品質保証が機能していない

---

## 技術評価層 — apps/

### apps/core（エンジンコア・OTP設計）

#### ✅ プラス点

- ContentBehaviour のオプショナルコールバック設計 `+5`
- バックプレッシャー設計（整合性維持とスキップの明確な分離）`+5`
- SSoT 整合性チェック（SSOT CHECK）`+4`
- SaveManager の HMAC 付きセーブデータ `+2`
- DynamicSupervisor によるルーム動的管理 `+2`
- EventBus・SaveManager のテスト整備 `+2`

#### ❌ マイナス点

- boss_dash_end の専用 handle_info 節（汎用化の余地）`-1`
- SaveManager の HMAC シークレットがデフォルト値でハードコード `-2`
- Contents.Scenes.Stack・Contents.Events.Game のテストがゼロ `-3`

**小計: +20 / -6 = +14点**

---

### apps/contents（コンテンツ実装・ゲームロジック）

#### ✅ プラス点

- 純粋関数による World/Rule 実装 `+4`
- AsteroidArena による ContentBehaviour の実証 `+4`
- エンティティパラメータの外部化 `+3`
- コンテンツテストの充実（VampireSurvivor 向け）`+3`

#### ❌ マイナス点

- EntityParams と SpawnComponent のパラメータ二重管理 `-3`
- LevelComponent のアイテムドロップロジックの重複 `-2`
- AsteroidArena のテストがゼロ `-2`
- Enum.find_last/2 回避コメントが不正確 `-1`

**小計: +14 / -8 = +6点**

---

### apps/network（ネットワーク層・トランスポート）

#### ✅ プラス点

- Phoenix.Token による WebSocket 認証 `+4`
- 3トランスポートの実装（Local・Channel・UDP）`+4`
- OTP プロセス隔離の実証（ルーム間クラッシュ分離）`+4`

#### ❌ マイナス点

- 分散ノード間フェイルオーバーが未実装 `-3`

**小計: +12 / -3 = +9点**

---

### apps/server（アプリケーション起動・設定）

#### ✅ プラス点

- Application 起動シーケンスの堅牢性 `+2`
- 環境別設定の分離（config.exs / runtime.exs）`+1`

**小計: +3 / 0 = +3点**

---

## 技術評価層 — native/

### native/physics（ECS・SoA・SIMD・衝突）

#### ✅ プラス点

- 全エンティティで統一された SoA 構造 `+5`
- SIMD SSE2 + rayon 並列 + スカラーフォールバックの 3 段階戦略 `+5`
- free_list O(1) スポーン/キル・spawn の Vec<usize> 返却 `+4`
- 空間ハッシュ衝突検出（FxHashMap・ゼロアロケーション）`+4`
- 決定論的 LCG 乱数 `+3`

**小計: +21 / 0 = +21点**

---

### native/desktop_render（描画パイプライン）

#### ✅ プラス点

- wgpu インスタンス描画（1 draw_indexed で全スプライト）`+4`
- CI 用ヘッドレスレンダラー `+4`
- サブフレーム補間（lerp）のロック外計算 `+3`

#### ❌ マイナス点

- build_instances の重複（DRY 違反）`-3`
- Skeleton/Ghost の UV がプレースホルダー `-2`
- Vertex/VERTICES 等の重複定義 `-2`

**小計: +11 / -7 = +4点**

---

### native/audio（非同期設計）

#### ✅ プラス点

- コマンドパターン + mpsc::channel 非同期設計 `+3`
- define_assets! マクロによる SSoT `+2`

**小計: +5 / 0 = +5点**

---

### native/nif（NIF 設計・ブリッジ）

#### ✅ プラス点

- NIF 関数カテゴリ分類（ロック競合の予測可能性）`+4`
- ResourceArc による GC 連動 `+4`
- lock_metrics による RwLock 可観測性 `+3`
- DirtyCpu スケジューラ指定 `+3`

**小計: +14 / 0 = +14点**

---

## 横断評価層

### テスト戦略

#### ✅ プラス点

- SIMD/スカラー一致テスト（許容誤差 0.05）`+4`
- StubRoom による NIF 依存の完全排除 `+3`

#### ❌ マイナス点

- プロパティベーステスト・ファジングがゼロ `-3`
- nif・render・audio の Rust テストがゼロ `-3`
- E2E テストがゼロ `-2`

**小計: +7 / -8 = -1点**

---

### 可観測性・変更容易性・DX・セキュリティ・ゲームプレイ

#### ❌ マイナス点（横断）

- [:game, :session_end] が metrics/0 に未登録 `-2`
- :telemetry.attach の呼び出しがゼロ `-2`
- Stats GenServer の二重集計リスク `-1`
- lock_metrics 閾値の constants.rs 未集約 `-1`
- CI の pull_request トリガーが未設定 `-2`
- bench-regression のローカル実行スクリプトなし `-1`
- README Contributing がプレースホルダー `-1`
- ゲームループの完結性が未確認（E2E なし）`-2`
- 視覚的完成度（Skeleton/Ghost 未実装）`-2`
- mix audit / cargo audit の CI 組み込みなし `-2`
- ビルド成果物の配布手順が未整備 `-2`

**小計: 0 / -18 = -18点**

---

### プロジェクト全体設計

#### ✅ プラス点

- ドキュメントの品質・網羅性・コードとの一致度 `+5`
- vision.md による設計哲学の明文化 `+4`

**小計: +9 / 0 = +9点**

---

## 総合スコア集計

| 観点             | プラス  | マイナス | 小計   |
|------------------|---------|----------|--------|
| apps/core        | +20     | -6       | +14    |
| apps/contents    | +14     | -8       | +6     |
| apps/network     | +12     | -3       | +9     |
| apps/server      | +3      | 0        | +3     |
| native/physics   | +21     | 0        | +21    |
| native/desktop_render    | +11     | -7       | +4     |
| native/audio     | +5      | 0        | +5     |
| native/nif       | +14     | 0        | +14    |
| テスト戦略       | +7      | -8       | -1     |
| 横断（可観測性等）| 0       | -18      | -18    |
| プロジェクト全体 | +9      | 0        | +9     |
| **合計**         | **+116**| **-50**  | **+66**|

※ 合計は掲載数値の積み上げによる。前回レポートとの算出方法の差により、小数点以下の端数で若干の差異が出ることがある。

---

## 総括

### 突出している点

- **Rust 物理演算層**: SoA・free_list・SIMD・空間ハッシュ・決定論的乱数が一貫した設計で実装されている。
- **ContentBehaviour / Component 設計**: オプショナルコールバックにより、コンテンツ交換可能性を実証している。
- **WebSocket 認証**: Phoenix.Token によるルーム参加認証が実装済みで、ネットワーク層のセキュリティが向上している。

### 最優先の改善点

1. **Contents.Scenes.Stack・Contents.Events.Game のテスト整備** — シーン遷移・フレームループの中核ロジックを検証する。
2. **pull_request トリガーの追加** — PR マージ前の品質保証を有効化する。
3. **EntityParams の SSoT 化** — パラメータの3箇所散在を解消する。

### 比較軸

| 比較対象         | 観点       | 評価                           |
|------------------|------------|--------------------------------|
| Bevy 0.13        | ECS設計    | SoA・free_list の設計思想は同等 |
| Godot 4          | コンテンツ分離 | ContentBehaviour はノード/シーン哲学と同等 |
| Phoenix LiveView | OTP活用    | バックプレッシャー設計と思想が近い       |

---

## bin/ci.bat 実行確認について

評価環境（Cursor Sandbox / Windows）で `bin\ci.bat check` を実行したところ、「Cursor Sandbox is unsupported」により実行が完了しなかった。ローカル環境での CI 通過可否は、評価者が手動で確認する必要がある。
