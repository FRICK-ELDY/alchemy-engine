# Fable 改善提案書 — マイナス点に基づく改善計画

作成日: 2026-07-04 / 作成者: Fable 5
根拠: `docs/evaluation/fable-specific-weaknesses.md`（総合評価 +37、マイナス合計 -116）

マイナス点 55 項目を「即修正すべきバグ」「セキュリティ」「価値命題の配線」「品質基盤」「整理・負債返済」の 5 フェーズに再編し、依存関係と費用対効果の順に並べた。各項目に解消されるマイナス点数を付記する。

---

## フェーズ 1: 実バグ修正（数時間〜1日、-8 点解消）

### 1-1. Formula VM の除算バグ修正 `-3 解消`

`binary_div` が `as_i32()` の「F32 も truncate して Some を返す」仕様により常に整数除算になる。加減乗と同じ型分岐（両方 I32 → I32、それ以外 → F32 昇格）に揃える。

```rust
// engine/rust/nif/src/formula/vm.rs — 修正イメージ
fn binary_div(a: Value, b: Value) -> Result<Value, VmError> {
    match (a, b) {
        (Value::I32(x), Value::I32(y)) => {
            if y == 0 { return Err(VmError::DivisionByZero); }
            Ok(Value::I32(x.checked_div(y).unwrap_or(i32::MAX))) // MIN/-1 も封じる
        }
        _ => {
            let (x, y) = (a.as_f32()?, b.as_f32()?);
            if y == 0.0 { return Err(VmError::DivisionByZero); }
            Ok(Value::F32(x / y))
        }
    }
}
```

同時に `i32::MIN / -1` パニック（`-2 解消`）を `checked_div` で封じ、**回帰テストを Rust 側に追加**する（フェーズ 4-1 の先行分）。

### 1-2. Authenticate プラグの未処理エラー経路 `-3 解消`

`AuthWeb.Plugs.Authenticate` の `else` にキャッチオール節を追加し、未知のエラー（Joken 構造体エラー等）を 401 `invalid_token` に落とす。細工トークンで 500 が返る現状を解消。

対象: `auth/lib/auth_web/plugs/authenticate.ex`

---

## フェーズ 2: セキュリティ防御線（1〜2週間、-24 点解消）

**優先原則: 「一番弱い経路」から塞ぐ。** auth の作り込みは UDP/Zenoh の無認証経路がある限り無意味になる。

### 2-1. engine SECRET_KEY_BASE の fail-fast `-3 解消`

auth と同じ方式で `runtime.exs` に prod 時の raise を追加。dev/test 固定値での本番起動（= RoomToken 偽造可能状態）を封じる。数行の変更で -3 が消える最高効率の修正。

対象: `engine/config/runtime.exs`

### 2-2. auth レート制限の導入 `-4 解消`

Hammer または PlugAttack を導入し、login: IP あたり 5 回/分、register: IP あたり 3 回/時、refresh: token あたり 10 回/分 程度から開始。429 応答と Retry-After ヘッダを返す。

対象: `auth/lib/auth_web/router.ex`, `auth/mix.exs`

### 2-3. auth ↔ engine の接続（room token の認証発行） `-3 解消`

engine に JWKS クライアント（起動時取得 + kid キャッシュ + 失敗時リトライ）を実装し、`POST /api/room_token` を「auth の access token を Bearer 必須」に変更する。これで auth のアカウント体系がゲームサーバの入場管理に初めて接続される。

対象: `engine/apps/network/lib/network/router.ex`（新規: `engine/apps/network/lib/network/auth_verifier.ex`）

### 2-4. UDP JOIN / Zenoh 入力への RoomToken 適用 `-5 解消（-3 + -2）`

JOIN パケットに room token フィールドを追加し検証。Zenoh の client_info にも同トークンを載せ、ZenohBridge で検証してから入室登録する。3 トランスポートの認証強度を対称にする。

対象: `engine/apps/network/lib/network/udp/protocol.ex`, `udp/server.ex`, `zenoh_bridge.ex`

### 2-5. zlib 展開の上限設定 `-3 解消`

`:zlib.uncompress/1` を streaming API（`:zlib.safeInflate` 相当）に置き換え、展開後 64KB 上限で打ち切る。上限超過は不正パケットとして破棄。

対象: `engine/apps/network/lib/network/udp/protocol.ex`

### 2-6. UDP セッションタイムアウト `-2 解消`

最終受信時刻を記録し、30 秒無通信のクライアントを定期スイープで除去。LEAVE パケットも追加。

対象: `engine/apps/network/lib/network/udp/server.ex`

### 2-7. auth の残セキュリティ項目 `-4 解消（-2 + -1 + -1）`

- refresh token ローテーション + 再利用検知（旧トークン使用時に全セッション失効）`-2`
- register エラーの汎用化（列挙対策）`-1`
- runtime.exs の DB SSL 有効化 `-1`

---

## フェーズ 3: 価値命題の配線（2〜6週間、-25 点解消）

**優先原則: 「作ってあるのに繋がっていないもの」から。** 新規開発より配線の方が費用対効果が高い。

### 3-1. マルチルームのゲームループ駆動 `-7 解消（-4 + -3）`

- `:elixir_frame_tick` のスケジュールを全ルームで行う（`room_id == :main` 条件の撤廃）
- `content.flow_runner(:main)` ハードコード 2 箇所を `flow_runner(room_id)` に変更し、コンポーネント state に room_id を伝搬
- `Core.FrameCache` / `Core.Stats` をルーム ID キー付き ETS に変更（フェーズ 5 と共通）
- 受け入れ条件: `start_room(:room2)` 後に両ルームのフレームが独立に進むテスト

対象: `engine/apps/contents/lib/events/game.ex`, `components/category/rendering/render.ex`, `components/category/device/helpers.ex`

### 3-2. スナップショット補間の配線 `-4 解消`

既存の `shared/src/interp.rs` を `network_render_bridge` に接続し、直近 2 フレームの位置を描画時刻で線形補間する（100ms 程度の描画遅延バッファ）。20Hz 配信のまま 60fps の滑らかさを得る、クライアント体験上の最重要改善。

対象: `engine/rust/client/network/src/network_render_bridge.rs`, `shared/src/interp.rs`

### 3-3. Zenoh publisher の再利用 + 再接続 `-5 解消（-3 + -2）`

`ClientSession` に `HashMap<String, Publisher>` を持たせ、`declare_publisher` を key ごとに 1 回だけ実行。session エラー検知時の指数バックオフ再接続も追加。

対象: `engine/rust/client/network/src/platform/desktop.rs`

### 3-4. OpenXR 最小実装 `-4 解消（長期）`

openxr クレートで HMD ポーズ取得 → 既存の head_pose 送信経路（サーバ側受け口は実装済み）に接続する最小ループから始める。レンダリングのステレオ化は第二段階でよい。まず「HMD の頭の動きがサーバに届く」を成立させる。

対象: `engine/rust/client/xr/`

### 3-5. 連合層の第一歩（read-only S2S） `-4 は段階解消`

改善計画としては (1) インスタンス設定（ドメイン・公開鍵）のリソース化、(2) 署名付き `GET /api/s2s/worlds`（他インスタンスのワールド一覧取得）、(3) 訪問トークン（ホーム auth の JWT を訪問先が JWKS 検証）の 3 段階を提案。フル ActivityPub は目標到達点とし、まず 2 インスタンス間の相互参照を成立させる。

対象: 新規 `engine/apps/network/lib/network/s2s/`, `auth/`

### 3-6. engine の永続化層 `-2 解消`

FormulaStore synced とルーム状態のスナップショットを定期永続化（初期は DETS/SQLite で十分）し、ルーム再起動時に復元する。

対象: `engine/apps/core/lib/core/formula_store.ex`, `engine/apps/contents/lib/events/game.ex`

---

## フェーズ 4: 品質基盤（2〜3週間、-16 点解消）

### 4-1. Rust テストの整備 `-6 解消（nif -3 + CI 未実行 -3）`

1. `nif` クレートに decode 境界条件・VM 型昇格・除算の単体テスト（フェーズ 1-1 の回帰テスト含む）
2. **CI の `cargo test -p nif` を `cargo test --workspace` に変更**（1 行変更で既存 29 テストが回帰検出に参加する。最高効率の改善）
3. `mix alchemy.ci` 側も同様に変更

対象: `engine/rust/nif/src/`, `engine/.github/workflows/ci.yml:50-51`, `engine/apps/core/lib/mix/tasks/alchemy.ci.ex:99`

### 4-2. auth CI の品質ゲート統一 `-2 解消`

engine と同じく `mix format --check-formatted`・`compile --warnings-as-errors` を追加し、credo を導入。モノレポ内の品質基準を統一する。

対象: `auth/.github/workflows/ci.yml`

### 4-3. contents のテスト補強 `-3 解消`

優先順: (1) `Events.Game` の frame_event 処理・バックプレッシャー・VR 入力ガード、(2) FrameEncoder の DrawCommand 変換、(3) シーンスタック遷移。ゲームルール自体より「エンジンとの境界」を先にテストする。

対象: `engine/apps/contents/test/`

### 4-4. NifBridge の DI 配線 `-2 解消`

`Application.compile_env(:core, :nif_bridge, Core.NifBridge)` で Behaviour 実装を注入可能にし、テストで Mox を使えるようにする。

対象: `engine/apps/core/lib/core/formula.ex`

### 4-5. プロパティテスト・監査の導入 `-3 解消（-2 + -1）`

- StreamData で FormulaGraph roundtrip、UDP Protocol encode/decode 対称性
- CI に `cargo audit` + `mix hex.audit` + dependabot 設定

対象: `engine/mix.exs`, `.github/`

### 4-6. VM の資源上限 `-1 解消`

`decode_bytecode` に `MAX_INSTRUCTIONS`（例: 4096）を導入。将来の重いグラフに備え `#[rustler::nif(schedule = "DirtyCpu")]` への切替も検討。

対象: `engine/rust/nif/src/formula/decode.rs`

### 4-7. auth の運用機能 `-9 解消`

- メール検証フロー `-2`・パスワードリセット/変更/退会 `-2`
- JWT TTL を 15 分に短縮（refresh 前提化）`-2`
- token_revocations / 期限切れ refresh_tokens の定期 GC（Oban）`-2`
- 最低年齢バリデーション `-1`

---

## フェーズ 5: 整理・負債返済（随時、-14 点解消）

| 項目 | 内容 | 点数 |
|:---|:---|:---:|
| core→contents 分離 | `@default_content` を config 必須化、StressMonitor の wave_label 等をコンテンツ注入のメタデータに置換 | -3 |
| FrameCache/Stats のルーム対応・汎用化 | room_id キー + 汎用メトリクス map 化（フェーズ 3-1 と同時実施） | -2 / -1 |
| contents→network の MFA 注入化 | FormulaStore と同じパターンで ZenohBridge 直参照を除去 | -2 |
| 死にコード削除 | InputHandler、physics_ms メトリクス、features: [] 設定 | -2 |
| 命名統一 | `Content.` → `Contents.` へ寄せる | -1 |
| tick 定数統一 | `@tick_ms` を 16.67 基準に統一し換算を一元化 | -1 |
| auth 本番デプロイ構成 | `mix release` + 本番 Dockerfile + `/health`（DB 疎通込み） | -2 |
| engine リリース定義 / server テスト | `mix release` 定義、起動シーケンステスト | -2 |
| 鍵ローテーション | JWKS 複数鍵対応 + 猶予期間付きローテーション手順 | -2 |
| 可観測性の実配線 | 死にメトリクス削除 + PromEx 化（提案 15 参照） | -2 |
| UDP 断片化・seq 検証 | MTU 超過フレームの分割、入力 seq の単調性チェック | -1 |
| WASM スタブの扱い決定 | 実装するか削除するか明示（残すなら compile_error! で明示） | -2 |
| render デバイスロス・clone・カリング | SurfaceError::Lost 再構成、RenderFrame 参照渡し、簡易カリング | -3 |
| render テスト | headless golden image 回帰（提案参照） | -2 |
| CORS / health（auth） | 必要オリジン設定、DB 込みヘルスチェック | -2 |

---

## 実施順序サマリ

```
フェーズ1 (即日)      : 除算バグ / plug 500 ──────────────── -8
フェーズ2 (1-2週)     : SECRET_KEY_BASE → レート制限 → auth↔engine 接続
                        → UDP/Zenoh 認証 → zlib 上限 ─────── -24
フェーズ3 (2-6週)     : マルチルーム駆動 → 補間配線 → publisher 再利用
                        → OpenXR 最小 → S2S 第一歩 ───────── -25
フェーズ4 (並行 2-3週): cargo test --workspace(1行!) → nif テスト
                        → auth CI → contents テスト ──────── -16
フェーズ5 (随時)      : 負債返済・運用整備 ────────────────── -14+
```

フェーズ 1 と 2-1、4-1-2（CI 1 行変更）だけで -14 が数日で解消できる。全フェーズ完了時の理論値は **+37 → +120 超**（マイナスほぼ全解消 + テスト・連合実装による新規加点）であり、アーキテクチャの手戻りなしに到達可能である。
