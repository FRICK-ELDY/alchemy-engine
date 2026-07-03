# バックログ: セキュリティ・運用リスク（コードレビュー起点）

> 作成日: 2026-07-03  
> 目的: 2026-07-03 時点の engine コードレビューで洗い出したリスクを、優先度付きバックログとして整理する。  
> 対象: Elixir Server（`apps/core`, `apps/contents`, `apps/network`）/ Rust Client（`rust/client`）/ Formula NIF（`rust/nif`）  
> 関連: [login-register-ui-plan.md](./login-register-ui-plan.md)（auth クライアント UI）、[network-scalability-priority-issues.md](./network-scalability-priority-issues.md)（性能系）

[← README](./README.md)

---

## 優先度サマリ

| 優先度 | リスク | 主な影響 | 状態 |
|:---|:---|:---|:---|
| P0 | リアルタイム入力経路（UDP / Zenoh）の無認証 | 任意クライアントからの入力注入・スパム | 未対応 |
| P0 | `room_token` 発行・検証モデルの未確定 | Channel 認証の実効性が設計次第で大きく変わる | **要再検討** |
| P0 | Logout 未実装（refresh token のサーバ側 revoke なし） | セッション失効不能・トークン漏洩時の影響拡大 | WIP（Phase 4） |
| P1 | `ui_action` 名の無制限注入 | 内部アクションの不正トリガー | 未対応 |
| P1 | 動的ルーム参加とルーム起動ポリシーの未整理 | 存在しないルームへの参加試行・リソース枯渇 | 未対応 |
| P1 | auth セッションとゲーム接続の未統合 | ログインしてもゲーム入力は無認証のまま | 計画済み（将来） |
| P2 | `/health` による `room_ids` 列挙 | 本番での情報漏洩・偵察 | 未対応 |
| P2 | Formula bytecode のリソース上限なし | NIF 経由の DoS | 未対応 |
| P2 | `FrameEncoder` 未知コマンドでの `raise` | 本番フレームループの GenServer クラッシュ | 未対応 |
| P3 | トークン・パスワードの平文メモリ保持 | プロセスダンプ・デバッガ露出 | Phase 4 以降 |

---

## P0 — リアルタイム入力経路（UDP / Zenoh）に認証がない

### 現状

| 経路 | 認証 | 実装 |
|:---|:---|:---|
| Phoenix Channel | `Network.RoomToken.verify/2` で join 時検証 | `apps/network/lib/network/channel.ex` |
| Zenoh movement / action | なし | `apps/network/lib/network/zenoh_bridge.ex` |
| UDP JOIN / INPUT / ACTION | なし | `apps/network/lib/network/udp/server.ex`, `protocol.ex` |

Zenoh はトピック名（`room_id`）を知っていれば誰でも publish 可能。デコード後、そのまま `Events.Game` へ `send` される。

```elixir
# zenoh_bridge.ex（抜粋）
send(pid, {:move_input, dx, dy})
send(pid, {:ui_action, name})
```

UDP も同様に、パケットを送れる相手から任意 `room_id` への参加・入力が可能。

### 懸念

- 本番公開後、**ゲーム整合性を破る入力**（移動・アクションのスパム）を第三者が注入できる
- Channel だけ認証しても、Zenoh / UDP が開いていれば迂回できる
- レート制限・異常頻度検知も入力経路全体では未整備（`client_info` 側の room 数上限は別問題）

### 着手の方向性（確定ではない）

1. **経路ごとの認証方式を一覧化**する（Zenoh ACL、共有シークレット、JWT 付きメタデータ、入力パケットへの HMAC 等）
2. **Channel と同じ trust モデルに揃える**か、**auth JWT をゲーム接続にも使う**かを `room_token` 再検討とセットで決める
3. room / client 単位のレート制限（[network-scalability-priority-issues.md](./network-scalability-priority-issues.md) P2 と連携）

### 受け入れ条件（案）

- [ ] 本番想定の入力経路すべてについて、認証方式と失敗時の挙動（drop / disconnect / ログ）が文書化されている
- [ ] 未認証入力がゲームループに到達しない（または明示的に許可された開発モードのみ例外）
- [ ] 回帰テスト（不正ペイロード・未登録 room・トークン欠落）がある

---

## P0 — `room_token` のセキュリティモデル（要再検討）

> **本項目は設計を改めて検討する前提で記録する。** 具体的な実装方針（JWT 必須化、auth 連携等）はここでは確定しない。

### 現状

| 要素 | 挙動 | 実装 |
|:---|:---|:---|
| 発行 | `POST /api/room_token` — **無認証**、任意の非空 `room_id` で署名 | `apps/network/lib/network/router.ex` |
| 検証 | Channel join 時に署名・スコープ・期限を検証 | `apps/network/lib/network/room_token.ex`, `channel.ex` |
| 有効期限 | 署名時に設定（現行は短寿命想定） | `room_token.ex` |

```elixir
# router.ex（抜粋）— 発行側に認証・レート制限・room_id 形式検証なし
post "/api/room_token" do
  %{"room_id" => room_id} -> {:ok, token} = Network.RoomToken.sign(room_id)
```

[login-register-ui-plan.md](./login-register-ui-plan.md) では「engine サーバでの JWT 検証」はスコープ外とし、将来計画に回している。

### 懸念

- **発行権限の欠如**: トークンは「形式として正しい」だけで、「その room に参加する権利がある」ことは証明しない
- **無制限発行**: レート制限がなく、任意 `room_id` のトークンを量産できる
- **経路間の不整合**: Channel は token 必須だが Zenoh / UDP は無認証 → token の意味が入力全体の trust 境界になっていない
- **auth MVP との関係**: alchemy-auth の JWT / refresh と room 参加権をどう結びつけるか未決定

### 検討すべき問い（チェックリスト）

設計レビュー時に以下を順に決める。

1. **room_token の役割は何か**
   - Channel 専用の短命 join トークンか
   - auth セッションの派生クレデンシャルか
   - Zenoh / UDP にも載せる共通セッションか
2. **誰が発行できるか**
   - 匿名（現状）でよいか
   - auth ログイン済みユーザーのみか
   - サーバ内部（ルーム作成時）のみか
3. **room_id と権限の対応**
   - 任意 room への参加を許すか
   - 事前登録・招待・ロールベースか
4. **他経路との統一**
   - 同じ token / JWT を Zenoh metadata や UDP ペイロードに載せるか
   - 経路ごとに別 credential にするか
5. **失効・ローテーション**
   - logout / kick / ban 時にゲーム接続も切るか
   - refresh token revoke と room 参加の連動

### 着手の方向性（確定ではない）

- 専用の短い設計メモ（または ADR）を `workspace/1_backlog` または `docs/architecture` に追加し、上記チェックリストに回答を書く
- [login-register-ui-plan.md](./login-register-ui-plan.md) Phase 4 以降の「auth ↔ engine 連携」と一体で決める
- 実装前に **現状の `/api/room_token` を本番で公開しない**運用ルールを明文化してもよい

### 受け入れ条件（案）

- [ ] room 参加の trust 境界（誰が・どの経路で・何を持って参加できるか）が 1 枚の図または表で説明できる
- [ ] 発行 API の認証・レート制限方針が決まっている
- [ ] Channel / Zenoh / UDP の認証要否が方針として揃っている（例外があれば理由付き）

---

## P0 — Logout 未実装（refresh token のサーバ側 revoke なし）

### 現状

- Rust `AuthClient::logout` は実装済み（`rust/client/auth_client/src/api.rs`）
- UI の Logout は `sys.clear_session()` のみで、auth `/logout` を呼ばない

```rust
// menu.rs（抜粋）
// Phase 4 でログアウト処理（auth /logout + トークン破棄）を接続する
if menu_button(ui, "Logout", BUTTON_NEUTRAL) {
    sys.clear_session();
}
```

### 懸念

- クライアント側でトークンを消しても、**サーバ上の refresh token は有効なまま**
- Remember Me 実装後はディスク上の資格情報と組み合わせてリスクが増える

### 着手案

- [login-register-ui-plan.md](./login-register-ui-plan.md) Phase 4 に従い、`AuthClient::logout` + ローカルトークン破棄を接続
- 失敗時 UX（オフライン時はローカルのみクリア等）を定義

### 受け入れ条件（案）

- [ ] Logout 操作で auth の revoke API が呼ばれる
- [ ] 成功・失敗いずれでも UI 上はログアウト状態に遷移する方針が決まっている
- [ ] テスト（モック auth）がある

---

## P1 — `ui_action` 名の無制限注入

### 現状

Channel / UDP / Zenoh のいずれも、アクション名文字列を検証せずゲームループへ転送する。

| 経路 | コード |
|:---|:---|
| Channel | `apps/network/lib/network/channel.ex` — `handle_in("action", %{"name" => name}, ...)` |
| Zenoh | `zenoh_bridge.ex` — `forward_ui_action/2` |
| UDP | `apps/network/lib/network/udp/protocol.ex` — `:action` デコード |

長さ上限・allowlist・コンテンツ側の拒否ポリシーは未整備。

### 懸念

- 極端に長い文字列によるメモリ・ログ負荷
- コンテンツが内部用に予約したアクション名の不正トリガー（コンテンツ次第）

### 着手案

1. ネットワーク層で共通の `validate_ui_action_name/1`（長さ・文字種）
2. コンテンツ側でシーンごとの allowlist または prefix 規約
3. 拒否時はログ + drop（ゲームループに届けない）

### 受け入れ条件（案）

- [ ] 全入力経路で同一の検証関数を通す
- [ ] 拒否ケースのテストがある

---

## P1 — 動的ルーム参加とルーム起動ポリシーの未整理

### 現状

- `Network.Local.register_room/1` は接続テーブルへの登録のみ
- `Core.RoomSupervisor.start_room/1` は JOIN 時に自動では呼ばれない
- 本番起動時は `:main` ルームのみ `Server.Application` で起動する想定
- Zenoh `client_info` は最大 100 ルーム等の防御があるが、UDP / Supervisor 側には同様の上限がない

### 懸念

- 「参加したつもりがルームが存在しない」状態と、**動的ルーム作成の有無**が仕様として曖昧
- 悪意ある JOIN 連打によるリソース消費（上限なし経路）

### 着手案

1. 製品方針を決める: **事前起動ルームのみ** vs **参加時に `open_room`**
2. `room_id` 形式検証を全経路で共通化（`zenoh_bridge` の正規表現を参考）
3. ルーム数上限・作成権限を Supervisor / Local と揃える

### 受け入れ条件（案）

- [ ] ルームライフサイクル（作成・参加・破棄）がドキュメント化されている
- [ ] 存在しない room への入力は一貫して drop され、観測可能

---

## P1 — auth セッションとゲーム接続の未統合

### 現状

- クライアントの login/register UI は auth（`:4002`）との HTTPS 通信のみ
- ゲーム接続（Zenoh）は `--room main` 等で **auth とは独立**に確立
- [login-register-ui-plan.md](./login-register-ui-plan.md) で意図的にスコープ外

### 懸念

- ユーザーは「ログインした」が、**ゲーム世界への参加権は別系統**のまま
- 将来 hub / 課金 / 年齢制限などを room 参加に結びつける際に再設計が必要

### 着手案

- `room_token` 再検討（上記 P0）とセットで「auth 後に何を発行して Zenoh に渡すか」を定義
- 段階的導入: まず Channel のみ auth 連携 → 次に Zenoh metadata

### 受け入れ条件（案）

- [ ] ログイン成功後のクライアントフロー（auth → engine 接続）がシーケンス図で説明できる
- [ ] 未ログイン時の接続可否が製品要件として明文化されている

---

## P2 — `/health` による `room_ids` 列挙

### 現状

`GET /health` が稼働中ルーム ID の一覧を JSON で返す（`apps/network/lib/network/router.ex`）。

### 懸念

- 本番でルーム名・数の偵察に使われる
- ロードバランサ用の liveness と詳細情報の混在

### 着手案

- 公開 `/health` は `status` + `rooms` 件数のみ
- `room_ids` は認証付き管理 API または内部メトリクスのみ

### 受け入れ条件（案）

- [ ] 本番設定で外部に不要なフィールドが出ない
- [ ] 運用チームが必要とする情報は別エンドポイントで取得できる

---

## P2 — Formula bytecode のリソース上限なし

### 現状

- `rust/nif/src/formula/decode.rs` — バイトコード長・命令数の上限なし
- Elixir 呼び出し元でもサイズ制限が見当たらない
- VM 自体は `Result` でエラーを返し panic はしない（良い点）

### 懸念

- 悪意ある・誤った巨大バイトコードによる CPU / メモリ DoS（NIF は BEAM と同一プロセス）

### 着手案

1. デコード前に最大バイト長・最大命令数を定義
2. `Core.Formula` または NIF 入口で共通適用
3. 上限値は設定可能（dev は緩く、prod は厳しく）でもよい

### 受け入れ条件（案）

- [ ] 上限超過時は `{:error, ...}` で返り、VM に入らない
- [ ] テスト（境界値・超過）がある

---

## P2 — `FrameEncoder` 未知 DrawCommand で `raise`

### 現状

`apps/contents/lib/contents/frame_encoder.ex` の `command_to_pb/1` フォールバックが `raise ArgumentError`。

### 懸念

- コンテンツと proto スキーマの不整合時に **描画フレーム処理中の GenServer クラッシュ**
- 単一フレームの bad command でルーム全体が落ちる可能性

### 着手案

- `raise` をやめ、ログ + Telemetry + 当該コマンドスキップ
- 開発ビルドのみ `raise` するコンパイルフラグも選択肢

### 受け入れ条件（案）

- [ ] 未知コマンドで `Events.Game` が落ちない
- [ ] 不整合検知がログまたはメトリクスで追える

---

## P3 — 資格情報の平文メモリ保持

### 現状

- `SystemUi.auth_session` に access / refresh token を保持（`rust/client/system_ui/src/state.rs`）
- ログイン送信時に `password.clone()`（`login_form.rs`）— フォーム reset までメモリに残る
- OS キーチェーン・Remember Me 永続化は Phase 4 待ち

### 懸念

- デバッガ・クラッシュダンプ・スワップでの露出（クライアントアプリとして一般的なトレードオフだが、方針未記載）

### 着手案

- Phase 4 で token store 設計と合わせて「メモリに載せる期間」を最小化
- 可能なら送信後すぐに password フィールドをゼロ化（完全保証は OS 次第）

---

## テスト・観測のギャップ（リスク緩和の前提）

以下はセキュリティ修正の回帰防止として優先して足すとよい。

| モジュール | ギャップ |
|:---|:---|
| `Contents.Events.Game` | バックプレッシャー・入力 dispatch の単体テストなし |
| `Network.ZenohBridge` | movement / action 転送・拒否のテストなし |
| `Network.Router` | `room_token` / `/health` のエッジケースなし |
| `Core.RoomSupervisor` | ルーム作成上限・失敗時のテストなし |
| Rust `formula/decode.rs` | 上限導入後の境界テスト |

---

## 関連ドキュメント・次のアクション

| 項目 | 参照 |
|:---|:---|
| auth クライアント UI | [login-register-ui-plan.md](./login-register-ui-plan.md) |
| 性能・入力防御（レート制限） | [network-scalability-priority-issues.md](./network-scalability-priority-issues.md) |
| 権威ある状態・入力方針 | `docs/architecture/authoritative-state-sync-policy.md` |
| Zenoh プロトコル | `docs/` 配下の zenoh 関連仕様 |

**推奨する次の一手**

1. **`room_token` 設計レビュー**（本バックログ P0「要再検討」）— 発行権限・経路統一・auth との関係を決める
2. 設計が固まるまで、本番では **Zenoh / UDP の無認証入力** と **無制限 `room_token` 発行** を露出しない
3. 並行して **Logout → auth revoke**（login-register-ui Phase 4）は依存が少なく着手しやすい

---

## 変更履歴

| 日付 | 内容 |
|:---|:---|
| 2026-07-03 | 初版（コードレビュー起点で作成） |
