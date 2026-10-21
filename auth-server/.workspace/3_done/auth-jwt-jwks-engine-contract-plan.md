# 実施計画: auth-engine JWT / JWKS 契約整理

> 作成日: 2026-07-04
> ステータス: 完了
> 出典: [fable-specific-weaknesses.md](../../../engine/.workspace/0_docs/evaluation/fable/archive/2026-07-31/fable-specific-weaknesses.md)

---

## 1. 目的

- `auth` が発行する JWT を `engine` が検証できる前提を整える。
- claim、`iss` / `aud` / `kid`、JWKS 公開、失効モデルを文書化し、後続実装の契約面を先に固定する。

---

## 2. 対象

- `auth/lib/auth/token/keys.ex`
- `auth/lib/auth/token.ex`
- `auth/config/config.exs`
- `auth/config/runtime.exs`
- `auth/README.md` または `auth/.workspace/` 配下の設計メモ

---

## 3. この計画で決めること

- JWT の必須 claim
- `engine` が検証時に見るべき項目
- `kid` の付与規則
- JWKS の複数鍵併存方針
- logout / revoke / key rotation と resource server 側検証の関係

---

## 4. タスク

- [x] 現行 JWT の claim と不足項目を棚卸しする
- [x] `engine` 向けの検証契約を 1 枚のメモにまとめる → [jwt-jwks-engine-contract.md](../0_docs/jwt-jwks-engine-contract.md)
- [x] `kid` 前提の鍵表現へ拡張する設計を決める
- [x] JWKS を単一鍵固定から複数鍵併存可能な形へ設計する
- [x] access token 短命化と外部検証の関係を明記する

---

## 5. 非目標

- `engine` 側の実装そのもの
- RoomToken や UDP / Zenoh 認証の最終仕様確定

---

## 6. 受け入れ条件

- [x] JWT / JWKS 契約が文書として参照可能
- [x] `iss` / `aud` / `kid` の方針が決まっている
- [x] 鍵ローテーション時に旧トークン検証を継続できる前提が整理されている

---

## 7. 実装メモ

- 契約文書: `auth/.workspace/0_docs/jwt-jwks-engine-contract.md`
- 複数鍵: `jwt_verification_key_paths` / `JWT_VERIFICATION_KEY_PATHS`
- `Auth.Token.Keys.signer_for_kid/1` で kid ベース検証
- `Auth.Token.verify/1` はヘッダ `kid` から署名鍵を解決
