# バックログ: スケーラビリティ向け優先課題（ソースコード起点）

> 作成日: 2026-05-28  
> 目的: `workspace` 配下の計画文書を参照せず、現行ソースコードから「今すぐ手を付けると効果が高い課題」を優先度付きで整理する。  
> 対象: Elixir Server / Zenoh / Rust Client の現行実装

[← README](./README.md)

---

## 優先度サマリ

| 優先度 | 課題 | 主な影響 |
|:---|:---|:---|
| P0 | Rust クライアントの Publisher 再利用 | 入力送信ホットパスの CPU/遅延削減 |
| P1 | `Events.Game` の同期呼び出し密度の削減 | フレーム安定性・スループット |
| P1 | ネットワーク観測指標の拡張 | ボトルネック検知速度の向上 |
| P2 | Zenoh 入力経路の防御強化 | 公開後の耐障害性・耐悪用性 |
| P3 | descriptor 系 stub の最小契約固定 | 将来機能の再設計コスト低減 |

---

## P0 — Rust: Publisher を毎送信で再宣言しない

**現状**:

- `rust/client/network/src/platform/desktop.rs` の `ClientSession.put/2` と `put_drop/2` が、毎回 `declare_publisher(key)` を実行してから `put` している。
- 入力送信は高頻度で呼ばれるため、宣言コストと割り込みが積み上がる。

**懸念**:

- 入力送信のレイテンシ上振れ
- クライアント側 CPU 負荷上昇
- 高接続時の無駄なオブジェクト生成

**着手案**:

1. `ClientSession` に key ごとの publisher キャッシュを追加。
2. `movement` と `action` を先行対応（影響範囲が狭い）。
3. エラーハンドリングを「再宣言リトライ」へ統一。

---

## P1 — Elixir: `Events.Game` の同期境界を減らす

**現状**:

- `apps/contents/lib/events/game.ex` のフレーム処理内で `GenServer.call` が複数回登場する（runner 参照、更新、遷移等）。
- 1 tick のクリティカルパスに同期呼び出しが多い構造。

**懸念**:

- tick ごとの処理時間がシーン/遷移条件で揺れやすい
- 高負荷時に `message_queue_len` が増えやすい
- バックプレッシャー時の回復が遅くなる

**着手案**:

1. 1フレーム内で必要な runner 情報を先読みして再利用。
2. `call` 必須箇所と非必須箇所を分離。
3. 副作用は可能な範囲で非同期化し、tick 内同期数を固定化。

---

## P1 — 観測性の不足（ネットワーク起点の指標）

**現状**:

- `apps/core/lib/core/telemetry.ex` には `frame_dropped` などがあるが、ネットワーク運用に直結する指標が不足している。
- `apps/contents/lib/events/game/diagnostics.ex` では `physics_ms` が固定値（`@tick_ms`）相当で、実測としては弱い。

**懸念**:

- 帯域/遅延問題の発生点が追いにくい
- 「20Hzは安定、60Hzは不安定」の根拠が数値化されにくい

**着手案**:

1. 送信フレームサイズ（bytes）を計測・集計。
2. publish 失敗率、入力 decode 失敗率、room 未解決率を Telemetry 化。
3. queue depth の p95/p99 相当を可視化できる集計を追加。

---

## P2 — Zenoh 入力経路の防御を強化

**現状**:

- `apps/network/lib/network/zenoh_bridge.ex` は decode 失敗や room 未存在時にログ + drop する実装が中心。
- DoS 観点では room_id 検証など一部対策はあるが、入力連打・異常頻度に対する制御は限定的。

**懸念**:

- 公開後に悪性/不正クライアントでログ洪水
- 正常トラフィックの遅延誘発

**着手案**:

1. room/client 単位のレート制限を導入。
2. 警告ログのサンプリング化（同一原因の抑制）。
3. 異常率が閾値超過した送信元の一時隔離フックを追加。

---

## P3 — descriptor 実行基盤の stub 契約を先に固定

**現状**:

- `apps/contents/lib/contents/content_runner.ex`
- `apps/contents/lib/contents/component_registry.ex`
- `apps/contents/lib/contents/content_loader.ex`

上記が「将来実装」の stub。

**懸念**:

- 後続実装時に責務境界が曖昧になりやすい
- 実装ごとに API が揺れ、統合コストが上がる

**着手案**:

1. 最低限の契約（入力・出力・失敗時保証）だけ先に定義。
2. 実行層と定義層の境界を `@behaviour` と型で固定。
3. stub でもテスト可能な空実装（契約テスト）を追加。

---

## 最短実行順（提案）

1. **P0** Publisher 再利用（クライアントホットパス）
2. **P1** Telemetry 拡張（効果測定基盤を先に作る）
3. **P1** `Events.Game` 同期境界削減（測りながら実施）
4. **P2** 防御強化（公開前に最低限）
5. **P3** stub 契約固定（中期）

---

## 別軸バックログ: Ash + PostgreSQL ログイン基盤（MVP）

> 目的: Assets 管理（ユーザー/グループ所有）の前提となる認証・認可の土台を先に固める。

### 目標

- `Ash Framework + PostgreSQL` で、登録/ログイン/セッション検証/ログアウトを最小構成で動かす。

### 最小スコープ

1. `users`（`email`, `password_hash`, `status`）
2. ユーザー登録（email 一意制約）
3. メール + パスワードログイン
4. セッション発行（トークン or cookie）
5. 認証済み API ガード
6. ログアウト（トークン失効）

### 先に固定するセキュリティ方針

- パスワード平文保存禁止（hash のみ）
- 失敗ログインのレート制限
- セッション有効期限と更新方針
- 凍結/退会ユーザーの扱い（認証拒否・既存セッション失効）

### Assets 管理との接続ポイント（次フェーズ）

- `user` / `group` 所有の境界を Ash policy で定義
- `membership(role)` を導入して group 権限を段階化
- Asset 実体（BLOB）とメタデータ（DB）を分離する前提で進める

---

## 改訂履歴

| 日付 | 内容 |
|:---|:---|
| 2026-05-28 | 初版 |
| 2026-05-28 | Ash + PostgreSQL ログイン基盤（MVP）バックログを追記 |
