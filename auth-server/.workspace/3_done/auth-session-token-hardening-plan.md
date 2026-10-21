# 実施計画: セッショントークン運用強化

> 作成日: 2026-07-04
> ステータス: 実施済み
> 出典: [fable-specific-weaknesses.md](../../../engine/.workspace/0_docs/evaluation/fable/archive/2026-07-31/fable-specific-weaknesses.md)

---

## 1. 目的

- refresh token 使い回し、24 時間 access token、認証テーブルの GC 不足をまとめて解消し、セッション管理を継続運用可能な形にする。

---

## 2. 対象

- `auth/lib/auth/accounts.ex`
- `auth/lib/auth/accounts/refresh_token.ex`
- `auth/lib/auth/accounts/token_revocation.ex`
- `auth/config/config.exs`
- `auth/test/`

---

## 3. 実装スコープ

1. refresh token ローテーション
2. 再利用検知
3. access token TTL 短縮
4. 期限切れ token 系レコードの GC

---

## 4. タスク

- [x] refresh token の保存モデルを見直し、token family または親子関係を持てるようにする
- [x] refresh 成功時に新しい refresh token を返す
- [x] 旧 token の再利用を検知したときの失効方針を決める
- [x] access token TTL を短命化し、クライアント影響を洗い出す
- [x] `token_revocations` と期限切れ refresh token の GC 方針を決める
- [x] 正常ローテーション、再利用検知、期限切れ、GC 条件のテストを足す

---

## 5. 依存

- `auth-jwt-jwks-engine-contract-plan.md` の方針と整合させる

---

## 6. 受け入れ条件

- [x] refresh 時に同じ token を使い回さない
- [x] 盗難 token の再利用を検知できる
- [x] access token TTL が短命化されている
- [x] 古い revocation / refresh token を掃除する運用が定義されている
