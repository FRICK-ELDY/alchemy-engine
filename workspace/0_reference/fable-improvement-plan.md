# Fable 改善提案書 — マイナス点に基づく改善計画

作成日: 2026-07-31 / 作成者: Fable 5
根拠: `docs/evaluation/fable-specific-weaknesses.md`（総合評価 +89、マイナス合計 -96）
前回版: `docs/evaluation/archive/2026-07-31/`（2026-07-07 評価。総合は集計訂正後 +81）

---

## フェーズ 1: 即修正すべきバグ・些事（数時間〜1日、-7 点解消）

**実施済み。**

### 1-1. Formula VM の除算バグ修正 `-3 解消` ✅

`binary_div` の型分岐を加減乗と揃え（`matches!((I32, I32))` を先に判定）、`checked_div` で `i32::MIN / -1` も封じる（`-2` も同時解消）。Rust 単体テストを同時追加すること（フェーズ 4-1 の先行分）。

対象: `engine/rust/nif/src/formula/vm.rs`

### 1-2. i32::MIN / -1 パニック経路 `-2 解消`（1-1 と同時） ✅

### 1-3. 出荷 tick_hz とコメントの整合 `-1 解消`（新規） ✅

`config.exs:61` の `tick_hz: 10` を推奨値 20 に揃えるか、10 を選ぶ理由をコメントで明示する。1 行。

対象: `engine/config/config.exs`

---

## フェーズ 2: セキュリティ防御線（1〜2週間、-21 点解消）

**優先原則: 「一番弱い経路」から塞ぐ。2-1 / 2-2 / 2-3 / 2-4 / 2-5 は実施済み。残りは 2-6。**

### 2-1. engine SECRET_KEY_BASE の fail-fast `-3 解消` ✅

auth と同じ方式で `runtime.exs` に prod 時の raise を追加。今回 runtime.exs に TICK_HZ 対応が入ったので、同ファイルへの追記のみ。

対象: `engine/config/runtime.exs`

### 2-2. auth ↔ engine の接続（room token の認証発行） `-3 解消` ✅

engine に JWKS クライアントを実装し、`POST /api/room_token` を Bearer JWT 必須に変更。**auth 強化の効果をゲームサーバに接続する最重要タスク。** 契約は `auth/docs/jwt-jwks-engine-contract.md`。

**切替必須（デモ・ローカル向け）:** JWT 必須化は環境変数（例: `AUTH_REQUIRED`、既定はオフまたは dev オフ）で無効化できるようにする。オフ時は現行どおり無認証で room token を発行する。オン時のみ JWKS 検証を行い、失敗は 401。評価点の解消は **オン経路が本番／検証環境で有効であること** を前提とする。

背景: 2026-08-27 お披露目は Mac（Server + Router）と Windows（Client）をテザリング同一 LAN で接続し、**auth なしデモ**を本線とする。auth の Docker 運用は任意・バックアップとし、デモ当日は `AUTH_REQUIRED` オフで入場経路を auth に依存させない。

対象: `engine/apps/network/lib/network/router.ex`（新規: `auth_verifier.ex`）、`engine/config/runtime.exs`

### 2-3. UDP JOIN / Zenoh 入力への RoomToken 適用 `-5 解消（-3 + -2）` ✅

2-2 と同様、デモ前に入場を auth／RoomToken 必須へハードカットしない。適用時も `AUTH_REQUIRED`（または同等の切替）と整合させる。

- UDP JOIN: payload `room_id` または `room_id <<0>> token`。`AUTH_REQUIRED` 時のみ `Network.RoomToken` 必須
- Zenoh movement / action / client_info: `AUTH_REQUIRED` 時は `<<token_len::16, token, protobuf>>` 封筒必須（`Network.RoomAuth`）

対象: `engine/apps/network/lib/network/udp/`, `zenoh_bridge.ex`, `room_auth.ex`

### 2-4. zlib 展開の上限設定 `-3 解消` ✅

`:zlib.uncompress/1` を `safeInflate` 相当（展開後サイズ上限付き）に置換。

対象: `engine/apps/network/lib/network/udp/protocol.ex`（`decompress_frame_payload/1`）

### 2-5. UDP セッションタイムアウト `-2 解消` ✅

ping を活かしたハートビート淘汰を追加。`last_seen_ms` を JOIN / INPUT / ACTION / PING で更新し、`session_timeout_ms`（既定 30s）超過を定期スイープで除去。

対象: `engine/apps/network/lib/network/udp/server.ex`

### 2-6. auth 残セキュリティ項目 `-4 解消`

- ログイン時のメール検証必須化 `-2`
- account_tokens GC 追加 `-1`
- CORS 設定 `-1`

---

## フェーズ 3: 価値命題の配線（2〜6週間、-25 点解消）

### 3-1. マルチルームのゲームループ駆動 `-7 解消（-4 + -3）` ✅

`:elixir_frame_tick` の `:main` 限定を撤廃し、コンポーネントの `flow_runner(:main)` 直書き（`render.ex:28`, `helpers.ex:15`）を room_id 引き回しに変更。`Events.Game` 本体は既に `flow_runner(state.room_id)` へ移行済みなので、残りはコンポーネント側。

対象: `engine/apps/contents/lib/events/game.ex`, `components/category/`

### 3-2. スナップショット補間の配線 `-4 解消` ✅

`interp.rs`（実装済み・未使用）をブリッジに接続。**権威 tick の 10〜20Hz 化により前回より優先度が上昇**（60fps 描画に対し 10〜20Hz スナップショット表示のため）。

対象: `engine/rust/client/network/src/network_render_bridge.rs`, `shared/src/interp.rs`

### 3-3. Zenoh publisher の再利用 + 再接続 `-5 解消（-3 + -2）`

対象: `engine/rust/client/network/src/platform/desktop.rs`

### 3-4. OpenXR 最小実装 `-4 解消`

optional feature `openxr` と `run_xr_input_loop` の枠組みは追加済み。`run_openxr_loop` の TODO（即 Err 返却）を実装に置き換える。

対象: `engine/rust/client/xr/`

### 3-5. 連合層の第一歩（read-only S2S） `-4 は段階解消`

方針ドキュメント（PR #319）は作成済み。ソースへの着地（署名付き HTTP のワールド一覧 API 等）が次の一歩。

### 3-6. engine の永続化層 `-2 解消`

---

## フェーズ 4: 品質基盤（2〜3週間、-16 点解消）

### 4-1. Rust テストの整備 `-6 解消`

- CI の `cargo test -p nif` → `cargo test --workspace` に変更（1 行、`mix alchemy.ci` も同様）。既存 29 テスト（system_ui 16 / auth_client 8 / audio 2 / render_frame_proto 2 / network 1）が回帰検出に乗る `-3`
- nif クレートに単体テスト追加（decode 境界・VM 型昇格。1-1 の除算バグはこの空白の直接的帰結） `-3`

### 4-2. contents のテスト補強 `-3 解消`

lib 119 ファイルに対しテスト 4 ファイル。dt 化のような全域変更に対する「ゲーム速度同一性」検証を含め、衝突・ウェーブ・シーン遷移・FrameEncoder を補強。

### 4-3. NifBridge の DI 配線 `-2 解消`

### 4-4. プロパティテスト・監査の導入 `-3 解消（-2 + -1）`

auth にも hex.audit / dialyzer を追加（auth 残 -1 解消）。

### 4-5. VM の資源上限 `-1 解消`

### 4-6. auth 運用仕上げ `-3 解消`

- `/health` に DB 疎通チェック `-1`
- 最低年齢バリデーション `-1`
- 分散レート制限（Redis 等）検討 `-1`

---

## フェーズ 5: 整理・負債返済（随時、-10 点強）

- FrameCache のルーム対応 `-2` ✅
- core → contents 語彙分離の完遂（`Core.Config` の `@default_content`、StressMonitor の wave_label、Core.Stats） `-3 -1`
- 死にコード削除（InputHandler、`features: []`） `-1`
- contents → network の MFA 注入化（FormulaStore と同型の解決） `-2`
- 命名統一（Content. / Contents.） `-1`
- server テスト・release 定義 `-2`
- render テスト / observability 外部化 / find_room_node キャッシュ等

---

## 実施順序サマリ

```
フェーズ1  : Formula 除算バグ + tick_hz 整合 ────────────────── -7
フェーズ2  : SECRET_KEY_BASE → auth↔engine（AUTH_REQUIRED 切替）→ UDP/Zenoh ── -21
フェーズ3  : マルチルーム → 補間 → OpenXR → S2S ─────────────── -25
フェーズ4  : cargo test --workspace → contents テスト ────────── -16
フェーズ5  : 負債返済（随時）─────────────────────────────────── -10+
```

総合スコアは **+81（訂正後）→ +89**。今回の +8 は品質の地固め（tick 設定化・CI 復活）によるもので、価値命題側の -3〜-4 帯 10 件は 3 週間前から不変。**次の +15〜20 点はフェーズ 1〜2 前半（除算バグ修正 + auth↔engine 接続 + engine セキュリティ 3 件）が最も費用対効果が高い**、という前回の結論を維持する。ただし 2026-08-27 お披露目までは 2-2 / 2-3 の必須化をデモ経路に載せない（`AUTH_REQUIRED` オフ）。
