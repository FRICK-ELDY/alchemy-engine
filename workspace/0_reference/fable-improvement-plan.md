# Fable 改善提案書 — マイナス点に基づく改善計画

作成日: 2026-07-07 / 作成者: Fable 5
根拠: `docs/evaluation/fable-specific-weaknesses.md`（総合評価 +77、マイナス合計 -98）
前回版: `docs/evaluation/archive/2026-07-04/fable-improvement-plan.md`

---

## 完了済み（auth 強化 — 2026-07-04〜07）

`auth/.workspace/3_done` に基づき実装・検証済み。前回計画から **-18 点解消**。

| 項目 | 解消点数 | 実装 |
|:---|:---:|:---|
| レート制限 | -4 | `Auth.RateLimit` + `AuthWeb.Plugs.RateLimit` |
| Authenticate 500 経路 | -3 | `classify_failure/1` + rescue |
| refresh ローテーション | -2 | family_id + rotate + reuse detection |
| JWT TTL 24h | -2 | 900 秒 |
| 鍵ローテーション | -2 | multi-key JWKS |
| token GC | -2 | `Auth.TokenCleanup` |
| アカウント運用機能 | -2 | lifecycle API 一式 |
| auth CI | -2 | format / credo / warnings-as-errors |
| 本番デプロイ | -2 | release + Dockerfile + MailConfig |
| register 列挙 | -1 | 汎用失敗応答 |
| DB SSL | -1 | `DATABASE_SSL` env |

---

## フェーズ 1: 即修正すべきバグ（数時間〜1日、-8 点解消）

### 1-1. Formula VM の除算バグ修正 `-3 解消`

`binary_div` の型分岐を加減乗と揃え、`checked_div` で `i32::MIN / -1` も封じる。Rust 単体テストを同時追加。

対象: `engine/rust/nif/src/formula/vm.rs`

### 1-2. ~~Authenticate プラグの未処理エラー経路~~ ✅ 完了（auth 強化）

---

## フェーズ 2: セキュリティ防御線（1〜2週間、-24 点解消）

**優先原則: 「一番弱い経路」から塞ぐ。**

### 2-1. engine SECRET_KEY_BASE の fail-fast `-3 解消`

auth と同じ方式で `runtime.exs` に prod 時の raise を追加。

対象: `engine/config/runtime.exs`

### 2-2. ~~auth レート制限の導入~~ ✅ 完了（auth 強化）

### 2-3. auth ↔ engine の接続（room token の認証発行） `-3 解消`

engine に JWKS クライアントを実装し、`POST /api/room_token` を Bearer JWT 必須に変更。**auth 強化の効果をゲームサーバに接続する最重要タスク。**

対象: `engine/apps/network/lib/network/router.ex`（新規: `auth_verifier.ex`）

### 2-4. UDP JOIN / Zenoh 入力への RoomToken 適用 `-5 解消（-3 + -2）`

対象: `engine/apps/network/lib/network/udp/`, `zenoh_bridge.ex`

### 2-5. zlib 展開の上限設定 `-3 解消`

対象: `engine/apps/network/lib/network/udp/protocol.ex`

### 2-6. UDP セッションタイムアウト `-2 解消`

対象: `engine/apps/network/lib/network/udp/server.ex`

### 2-7. auth 残セキュリティ項目 `-4 解消`

- ログイン時のメール検証必須化 `-2`
- account_tokens GC 追加 `-1`
- CORS 設定 `-1`

---

## フェーズ 3: 価値命題の配線（2〜6週間、-25 点解消）

### 3-1. マルチルームのゲームループ駆動 `-7 解消（-4 + -3）`

対象: `engine/apps/contents/lib/events/game.ex`

### 3-2. スナップショット補間の配線 `-4 解消`

対象: `engine/rust/client/network/src/network_render_bridge.rs`, `shared/src/interp.rs`

### 3-3. Zenoh publisher の再利用 + 再接続 `-5 解消（-3 + -2）`

対象: `engine/rust/client/network/src/platform/desktop.rs`

### 3-4. OpenXR 最小実装 `-4 解消`

対象: `engine/rust/client/xr/`

### 3-5. 連合層の第一歩（read-only S2S） `-4 は段階解消`

### 3-6. engine の永続化層 `-2 解消`

---

## フェーズ 4: 品質基盤（2〜3週間、-16 点解消）

### 4-1. Rust テストの整備 `-6 解消`

CI の `cargo test -p nif` → `cargo test --workspace` に変更（1 行）。

### 4-2. ~~auth CI の品質ゲート統一~~ ✅ 完了（auth 強化）

### 4-3. contents のテスト補強 `-3 解消`

### 4-4. NifBridge の DI 配線 `-2 解消`

### 4-5. プロパティテスト・監査の導入 `-3 解消（-2 + -1）`

auth にも hex.audit / dialyzer を追加（残 -1 解消）。

### 4-6. VM の資源上限 `-1 解消`

### 4-7. auth 運用仕上げ `-3 解消`

- `/health` に DB 疎通チェック `-1`
- 最低年齢バリデーション `-1`
- 分散レート制限（Redis 等）検討 `-1`

---

## フェーズ 5: 整理・負債返済（随時）

engine 側の負債返済（core→contents 分離、死にコード削除、render テスト等）は前回計画を踏襲。auth 関連の完了項目は除外済み。

---

## 実施順序サマリ

```
完了    : auth 強化（レート制限・lifecycle・CI・release 等）── -18 ✅
フェーズ1 : Formula 除算バグ ─────────────────────────────── -8
フェーズ2 : SECRET_KEY_BASE → auth↔engine 接続 → UDP/Zenoh ── -24
フェーズ3 : マルチルーム → 補間 → OpenXR → S2S ──────────── -25
フェーズ4 : cargo test --workspace → contents テスト ──────── -16
フェーズ5 : 負債返済（随時）──────────────────────────────── -14+
```

auth 強化完了により総合スコアは **+37 → +77**。次の +20 点は **auth ↔ engine 接続 + engine セキュリティ 3 件**（フェーズ 2 前半）が最も費用対効果が高い。
