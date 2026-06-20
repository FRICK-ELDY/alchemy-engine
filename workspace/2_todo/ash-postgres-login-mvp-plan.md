# 実施計画: Ash + PostgreSQL ログイン基盤（MVP）

> 作成日: 2026-05-28  
> ステータス: 着手前（Definition of Ready 満たしたら `3_Inprogress` へ）

---

## 1. 目的

- Elixir Server に認証の土台を作り、以降の `User / Group / Asset` 管理の前提を固める。
- `Ash Framework + PostgreSQL` で、最小のログイン機能（登録/ログイン/検証/ログアウト）を動かす。
- 認可（policy）を早期に導入し、後続機能での権限実装の二重化を避ける。

---

## 2. 前提・非目標

### 2.1 前提

- サーバー側の公式状態管理は Elixir が担う（認証情報の最終判断もサーバー側）。
- リアルタイム通信（Zenoh）と認証/メタデータ（HTTP + DB）は責務を分離する。
- DB は PostgreSQL を使用する。

### 2.2 非目標（この計画で明示的にやらないこと）

- OAuth/OIDC（Google, GitHub など）連携
- MFA（TOTP/WebAuthn）
- パスワードリセットのメール配送本実装
- 課金・プラン管理

---

## 3. MVP のスコープ

- ユーザー登録（email + password）
- メール + パスワードログイン
- セッション発行（トークンまたは cookie）
- 認証済み API のガード
- ログアウト（セッション無効化）
- 凍結/退会ユーザーのログイン拒否

---

## 4. データモデル（最小）

| エンティティ | 主なカラム | 備考 |
|:---|:---|:---|
| `users` | `id`, `email`, `password_hash`, `status`, `inserted_at`, `updated_at` | `email` は一意。`status` は `active/suspended/deleted` など |
| `sessions` | `id`, `user_id`, `token_hash`, `expires_at`, `revoked_at`, `inserted_at` | 生トークンを保存せず hash を保存 |

---

## 5. フェーズ構成

### フェーズ 0: Definition of Ready

- [ ] Ash + PostgreSQL の依存関係と接続設定方針を決める。
- [ ] `apps/server`（または認証を置く app）で境界（Domain）を決める。
- [ ] セッション方式（Bearer token / Secure cookie）を決める。
- [ ] 既存 API で認証が必要な入口を棚卸しする（最小 1 エンドポイントで可）。

**完了条件**: 接続先 DB、保存方式、MVP 対象 API が決まっている。

---

### フェーズ 1: User リソース作成

- [ ] `users` テーブルの migration 作成（`email` unique index 含む）。
- [ ] Ash Resource / Action（create/read）を作成。
- [ ] パスワードは hash のみ保存（平文禁止）。
- [ ] `status` による利用可否判定をリソースに反映。

**完了条件**: 登録 API（または Action）で user 作成が可能、重複 email は拒否される。

---

### フェーズ 2: ログインとセッション

- [ ] ログイン Action を作成（email + password 検証）。
- [ ] `sessions` テーブルと Resource を作成。
- [ ] セッション発行・検証ロジックを実装（期限付き）。
- [ ] ログアウトでセッションを失効できるようにする。

**完了条件**: ログイン後に認証情報が発行され、ログアウトで再利用不可になる。

---

### フェーズ 3: 認証ガードと policy

- [ ] 認証済み API 入口に共通ガードを適用。
- [ ] Ash policy で「本人のみ」アクセス可能な最小ルールを定義。
- [ ] `suspended/deleted` ユーザーの拒否を共通化。

**完了条件**: 未認証・失効済み・停止ユーザーは保護 API にアクセスできない。

---

### フェーズ 4: セキュリティ最低ライン

- [ ] ログイン試行のレート制限を追加（IP または account 単位）。
- [ ] 監査ログ（成功/失敗/失効）を記録。
- [ ] セッション TTL と更新方針（固定/スライディング）を確定。

**完了条件**: ブルートフォース耐性と追跡可能性の最低要件を満たす。

---

## 6. テスト・検証観点

- [ ] 登録成功/失敗（重複 email）テスト
- [ ] ログイン成功/失敗（誤パスワード）テスト
- [ ] 期限切れセッション拒否テスト
- [ ] ログアウト後の再利用拒否テスト
- [ ] `status != active` ユーザー拒否テスト

---

## 7. Assets 管理への接続（次フェーズ）

- `users` が安定したら `groups` と `memberships(role)` を追加する。
- `assets` は `owner_type(user/group)` と `owner_id` で所有境界を持つ。
- 認可は Ash policy を SSoT とし、API 層での重複判定を避ける。

---

## 8. 関連ドキュメント

- [network-scalability-priority-issues.md](../1_backlog/network-scalability-priority-issues.md)
- [README.md](./README.md)

---

## 9. 次のアクション

1. フェーズ 0 の 4 項目を埋める。  
2. フェーズ 1 の migration と Resource から着手する。  
3. フェーズ 2 完了時点で一度レビューし、Assets 連携の設計入力に回す。
