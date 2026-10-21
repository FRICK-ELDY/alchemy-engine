# JWT / JWKS — engine 検証契約

> auth が発行する access token を、alchemy-engine 等の外部リソースサーバが検証するための契約。
> auth 内部 API（`/me`, `/logout`）の検証仕様も含む。

---

## 1. 概要

| 項目 | 値 |
|:---|:---|
| 署名方式 | RS256（RSA + SHA-256） |
| 発行者（`iss`） | `alchemy-auth`（環境変数 `JWT_ISSUER` で上書き可） |
| 受信者（`aud`） | `alchemy-platform`（環境変数 `JWT_AUDIENCE` で上書き可） |
| JWKS URL | `GET {auth_base_url}/.well-known/jwks.json` |
| `kid` 導出 | RFC 7638 JWK thumbprint（`JOSE.JWK.thumbprint/1`） |

外部 verifier（engine 等）は auth の秘密鍵を保持せず、JWKS の公開鍵のみで署名を検証する。

---

## 2. JWT ヘッダ（必須）

| フィールド | 要件 |
|:---|:---|
| `alg` | `RS256` のみ許可 |
| `kid` | 必須。JWKS `keys[].kid` のいずれかと完全一致 |

---

## 3. JWT クレーム（Payload）

### 3.1 必須クレーム

| クレーム | 型 | engine の検証 |
|:---|:---|:---|
| `sub` | UUID 文字列 | ユーザー識別子。`Ecto.UUID` 形式 |
| `iss` | 文字列 | 期待する issuer と完全一致 |
| `aud` | 文字列 or 文字列配列 | 期待する audience と一致（配列の場合は包含） |
| `iat` | Unix 秒（整数） | 発行時刻。clock skew ±60 秒を許容推奨 |
| `exp` | Unix 秒（整数） | 失効時刻。`exp` 超過は拒否。clock skew ±60 秒を許容推奨 |
| `jti` | UUID 文字列 | トークン一意 ID。engine は **失効 DB を参照しない** |
| `status` | 文字列 | 発行時スナップショット。`active` / `suspended` / `deleted` のいずれか |

### 3.2 engine 推奨検証手順

1. Bearer トークンを抽出
2. ヘッダをデコードし `alg == "RS256"` かつ `kid` 存在を確認
3. JWKS を取得（キャッシュ推奨: 5〜15 分）
4. `kid` に一致する JWK を選択。未ヒット時は JWKS を再取得して再試行
5. 署名を検証
6. `iss`, `aud`, `iat`, `exp`, `sub`, `jti`, `status` を検証
7. `status != "active"` は拒否（発行時スナップショットの防御層）

### 3.3 auth 内部 API の追加検証

`Auth.Token.verify/1`（`/me`, `/logout` 等）は engine 契約に加え:

- `jti` が `token_revocations` に存在しないこと
- `sub` のユーザーが DB 上で `status == :active` であること

---

## 4. JWKS 応答

### 4.1 エンドポイント

```
GET /.well-known/jwks.json
```

認証不要。`Content-Type: application/json`。

### 4.2 応答形式

```json
{
  "keys": [
    {
      "kty": "RSA",
      "kid": "<thumbprint>",
      "use": "sig",
      "alg": "RS256",
      "n": "...",
      "e": "AQAB"
    }
  ]
}
```

- `keys` は 1 件以上（鍵ローテーション時は複数鍵を併載）
- 各鍵: `kty=RSA`, `use=sig`, `alg=RS256`, `kid` 必須

### 4.3 キャッシュ方針（engine 実装向け）

- 起動時に JWKS を取得し `kid → JWK` をキャッシュ
- トークンの `kid` がキャッシュに無い場合は JWKS を再取得
- 定期的な再取得（5〜15 分間隔）でローテーション後の新鍵を取り込む

---

## 5. `iss` / `aud` / `kid` 方針

| 項目 | 方針 |
|:---|:---|
| `iss` | `config :auth, :jwt_issuer` が SSoT。本番は `JWT_ISSUER` で上書き可 |
| `aud` | `config :auth, :jwt_audience` が SSoT。本番は `JWT_AUDIENCE` で上書き可 |
| `kid` | 鍵ごとに RFC 7638 thumbprint。ローテーション = 新鍵 = 新 `kid` |

engine はデプロイ環境の `JWT_ISSUER` / `JWT_AUDIENCE` と一致するよう設定する。

---

## 6. 失効モデル

### 6.1 auth 内部（フル検証）

```
login/register/refresh → JWT 発行
       ↓
Bearer API (/me, /logout) → 署名 + iss/aud + jti DB + user status DB
       ↓
logout → token_revocations に jti 記録 → 即時失効
```

### 6.2 外部 verifier（JWKS 検証のみ）

```
JWT 発行 → Bearer (room_token 等) → JWKS 署名 + iss/aud/exp + kid
                                          ↓
                                    jti 失効は参照不可
```

| 操作 | auth 内部 | engine 等 外部 |
|:---|:---|:---|
| logout（jti 失効） | 即時拒否 | **保証しない** |
| アカウント停止 | DB 再確認で即時拒否 | `status` claim のみ（発行時スナップショット） |
| 鍵ローテーション | 旧 kid も JWKS 併載期間は検証可 | 同左（`exp` まで有効） |

### 6.3 外部検証と TTL の関係

- 現行 access token TTL: **24 時間**（`jwt_ttl_seconds`）
- 外部 verifier は jti 失効リストにアクセスできないため、logout 後も TTL 満了までトークンが有効になりうる
- **対策**: access token を 5〜15 分に短命化する（[auth-session-token-hardening-plan](../3_done/auth-session-token-hardening-plan.md) で実施予定）
- 外部 verifier は jti 失効への依存を設計に含めてはならない

---

## 7. 鍵ローテーション手順

手動ローテーション（自動化は本契約のスコープ外）:

1. 新 RSA 2048 鍵ペアを生成
2. 稼働中の秘密鍵パスを `JWT_VERIFICATION_KEY_PATHS`（または `jwt_verification_key_paths`）に追加
3. `JWT_PRIVATE_KEY_PATH` を新鍵に切替え、auth を再起動
4. 新トークンは新 `kid` で署名され、JWKS には新旧両方の公開鍵が掲載される
5. 旧鍵で署名されたトークンの最大 `exp`（現行 TTL 24h）経過後、`JWT_VERIFICATION_KEY_PATHS` から旧鍵を削除し再起動

猶予期間中、旧 `kid` のトークンは `exp` まで検証可能。

---

## 8. 設定リファレンス

| 設定キー / 環境変数 | 説明 | デフォルト |
|:---|:---|:---|
| `jwt_issuer` / `JWT_ISSUER` | JWT `iss` | `alchemy-auth` |
| `jwt_audience` / `JWT_AUDIENCE` | JWT `aud` | `alchemy-platform` |
| `jwt_ttl_seconds` | access token TTL（秒） | `86400` |
| `jwt_private_key_path` / `JWT_PRIVATE_KEY_PATH` | 署名用秘密鍵 PEM | `priv/jwt_private.pem` |
| `jwt_verification_key_paths` / `JWT_VERIFICATION_KEY_PATHS` | 検証専用追加鍵 PEM（カンマ区切り） | `[]` |

追加鍵は秘密鍵 PEM または公開鍵 PEM のいずれも可。重複 `kid` は起動時に拒否される。

---

## 9. engine 実装チェックリスト（別 PR）

- [x] JWKS クライアント（起動時取得 + `kid` キャッシュ + miss 時再取得 + 定期更新）
- [x] `POST /api/room_token` を Bearer JWT 必須に変更（`AUTH_REQUIRED` で切替。既定オフ）
- [x] `alg`, `kid`, `iss`, `aud`, `exp`, `sub`, `status` の検証
- [x] clock skew ±60 秒の許容
- [x] auth base URL を設定可能にする（`AUTH_JWKS_URL` または `AUTH_BASE_URL`）

参照: [fable-improvement-plan.md](../../../engine/.workspace/0_reference/fable-improvement-plan.md)
