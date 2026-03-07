# AlchemyEngine — マイナス点に基づく改善提案書

> 評価日: 2026-03-07  
> 出典: [evaluation-2026-03-07.md](../evaluation/evaluation-2026-03-07.md)  
> 参照: [specific-weaknesses.md](../evaluation/specific-weaknesses.md)

---

## 優先度別 改善項目一覧

### 🔴 最優先（設計上の明確な欠陥・-3点）

| # | 項目 | 影響 | 改善方針 |
|:---:|:---|:---|:---|
| 1 | Contents.SceneStack・GameEvents のテストがゼロ | リファクタリングの安全網がない。シーン遷移・フレームループの回帰リスク | `ExUnit` で SceneStack の push/pop 遷移、GameEvents の frame_events 受信→dispatch をテスト。StubRoom 同様に NIF 依存を排除したテスト設計 |
| 2 | EntityParams と SpawnComponent のパラメータ二重管理 | 3箇所（entity_params / spawn_component / Rust）に同期漏れリスク | entity_params.ex を唯一の SSoT とし、spawn_component は EntityParams を呼ぶだけに。Rust は set_entity_params NIF で受け取るのみ |
| 3 | build_instances 関数の重複（render/headless） | スプライト種別追加時に両方修正が必要。同期漏れ | `pub(crate)` の共通関数（例: `sprite_uv_and_size`）を抽出し、renderer/mod.rs と headless.rs の両方から利用 |
| 4 | 分散ノード間フェイルオーバーが未実装 | 「なぜ Elixir + Rust か」の分散面の証明が不足 | libcluster によるクラスタリング・ルームのノード間移動のシナリオを実装。`pending-issues.md` 課題10・11 と連携 |
| 5 | プロパティベーステスト・ファジングがゼロ | 境界条件・不変条件の自動検証が未整備 | StreamData で LevelSystem / BossSystem / SpawnSystem の不変条件を検証。cargo-fuzz で decode 関数にファズターゲット追加 |
| 6 | nif・render・audio の Rust テストがゼロ | デコードロジック・ヘッドレス描画の回帰リスク | decode_enemy_params 等の GPU 不要なデコードロジックをテスト。headless.rs を活用した描画パス検証 |

---

### 🟠 高優先（重要な機能・設計の欠如・-2点）

| # | 項目 | 影響 | 改善方針 |
|:---:|:---|:---|:---|
| 7 | SaveManager の HMAC シークレットがデフォルト値でハードコード | 本番環境でセーブ改ざん検証が実質無効化 | `runtime.exs` で `System.fetch_env!("SAVE_HMAC_SECRET")` を使うか、未設定時に起動を拒否する強制機構を追加 |
| 8 | LevelComponent のアイテムドロップロジックの重複 | 同一撃破で二重ドロップの可能性 | enemy_killed と entity_removed の対応関係を明確化。単一のドロップ判定パスに集約 |
| 9 | AsteroidArena のテストがゼロ | SplitComponent・SpawnSystem の動作が未検証 | VampireSurvivor と同様に純粋関数・ロジック部分の ExUnit テストを追加 |
| 10 | Skeleton/Ghost の UV がプレースホルダー | 視覚的に区別不可。ゲーム完成度を損なう | アトラスに専用スプライトを追加し、UV マッピングを更新 |
| 11 | Vertex/VERTICES 等の重複定義 | 構造体・定数の二重管理 | `pub(crate)` で共通モジュールに集約 |
| 12 | [:game, :session_end] が metrics/0 に未登録 | セッション終了統計が可観測性ツールに流れない | telemetry.ex の metrics/0 に `[:game, :session_end]` 用の summary/counter を追加 |
| 13 | :telemetry.attach がゼロ | 外部監視ツール（Prometheus 等）への接続口なし | phoenix_live_dashboard や Prometheus 用の attach を追加（提案として specific-proposals に記載済み） |
| 14 | CI の pull_request トリガーが未設定 | PR マージ前の品質保証が機能しない | `.github/workflows/ci.yml` に `pull_request: branches: ["**"]` を追加 |
| 15 | E2E テストがゼロ | ゲームループ完結性（開始→終了→リトライ）が未検証 | headless.rs を活用した E2E テストを追加 |
| 16 | 視覚的完成度（Skeleton/Ghost） | 同上 #10 | 同上 |
| 17 | mix audit / cargo audit の CI 組み込みなし | 脆弱性検出が手動依存 | CI に mix_audit と cargo audit ジョブを追加 |
| 18 | ビルド成果物の配布手順が未整備 | エンドユーザー向け配布形態が未定義 | Windows/macOS/Linux 向けのパッケージング手順を docs に記載 |

---

### 🟡 中優先（改善余地あり・-1点）

| # | 項目 | 改善方針 |
|:---:|:---|:---|
| 19 | boss_dash_end の専用 handle_info 節 | 汎用ディスパッチ `{:engine_message, tag, payload}` に統一。新規メッセージ追加時に GameEvents の変更が不要に |
| 20 | Enum.find_last/2 回避コメントが不正確 | Elixir 1.19 で使える旨にコメントを修正。または実際に Enum.find_last/2 を使用してコードを簡潔化 |
| 21 | Stats GenServer の二重集計リスク | EventBus 経由か record_* API のどちらか一方に統一。または「record_* は内部用、EventBus が外部用」と役割を明記 |
| 22 | lock_metrics 閾値が constants.rs に未集約 | lock_metrics.rs の定数を physics/constants.rs または nif 内の constants モジュールに移す |
| 23 | bench-regression のローカル実行スクリプトなし | `bin/bench.bat` 等を追加し、ローカルで `cargo bench -p physics` を実行可能に |
| 24 | README Contributing がプレースホルダー | コントリビューションの流れ（PR 作成→レビュー→マージ）を簡潔に記載 |

---

## 関連タスク

| タスク | 説明 | 計画書 |
|:---|:---|:---|
| P5-2 MessagePack バイナリ形式 | push_render_frame の MessagePack 化による転送効率化 | [p5-2-messagepack-execution-plan.md](p5-2-messagepack-execution-plan.md) |

---

## 推奨実施順序

```mermaid
graph TD
    A["1. pull_request トリガー追加\n（CI 強化・即効性高）"]
    B["2. SceneStack・GameEvents テスト\n（中核ロジックの安全網）"]
    C["3. EntityParams SSoT 化\n（設計原則の徹底）"]
    D["4. build_instances 共通化\n（render の DRY 解消）"]
    E["5. HMAC シークレット強制\n（セキュリティ）"]
    A --> B
    B --> C
    C --> D
    D --> E
```

1. **即時**: pull_request トリガー追加（1行変更で効果大）
2. **短期**: SceneStack・GameEvents テスト、EntityParams SSoT 化
3. **中期**: build_instances 共通化、HMAC 強制、AsteroidArena テスト
4. **長期**: 分散フェイルオーバー、プロパティ/E2E テスト、mix/cargo audit
