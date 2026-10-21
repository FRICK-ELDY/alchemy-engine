# alchemy-auth

[AlchemyEngine](https://github.com/FRICK-ELDY/alchemy-engine) 向けの **ユーザー認証 API** サービス。

登録・ログイン・セッション検証・ログアウトを担い、ゲームエンジン本体やアセット管理サービスから **認証責務を分離** する。

## 目的

| 責務 | 説明 |
|:---|:---|
| ユーザーアイデンティティ | UUID ベースのユーザー ID（JWT `sub`） |
| 登録 / ログイン | ユーザー名 or メール + パスワード（Argon2） |
| セッション | JWT（Bearer）の発行・検証 |
| Remember Me | opaque リフレッシュトークン（7 日非アクティブで失効・スライディング） |
| ログアウト | トークン失効（`jti` + リフレッシュトークン） |

**本リポジトリが担わないもの**

- ゲームロジック・ルーム管理（[alchemy-engine](https://github.com/FRICK-ELDY/alchemy-engine)）
- アセットメタデータ・BLOB 管理（将来の alchemy-assets）
- ログイン UI（alchemy-engine クライアント側）

## アーキテクチャ上の位置

```
┌─────────────────┐     JWT (Bearer)      ┌─────────────────┐
│  alchemy-engine │ ◄──────────────────── │  alchemy-auth   │
│  (ゲーム/UI)    │     JWKS 公開鍵参照    │  (本リポ)        │
└─────────────────┘                       └─────────────────┘
        │                                         │
        │ 将来                                    │ 将来
        ▼                                         ▼
┌─────────────────┐                       ┌─────────────────┐
│ alchemy-assets  │ ◄── JWT sub = owner ──│   PostgreSQL    │
│ (Ash + メタ)    │                       │   (users 等)    │
└─────────────────┘                       └─────────────────┘
```

- **User の SSoT** は本サービスのみ。他サービスは JWT の `sub`（ユーザー UUID）だけを参照する。
- ルーム参加用の短命トークン（Room Token）は alchemy-engine 側が発行する（User Session → Room Token の 2 段階）。

## 技術スタック

| 項目 | バージョン |
|:---|:---|
| Elixir | ~> 1.19 |
| Erlang/OTP | 28 |
| Phoenix | ~> 1.8 |
| Ash + ash_postgres | ~> 3.0 / ~> 2.0 |
| PostgreSQL | 16+ |
| パスワードハッシュ | Argon2 |
| セッション | JWT（RS256） |

## MVP スコープ

### 含む

1. `users` テーブル（`id` UUID, `username`, `email`, `password_hash`, `status`, `birthday`, `promo_code`, `tos_agreed_at`, `tos_version`）
2. ユーザー登録（username / email 一意制約、パスワード複雑性、利用規約同意、生年月日）
3. ユーザー名 or メール + パスワードログイン
4. JWT セッション発行
5. Remember Me（リフレッシュトークン。7 日非アクティブで失効、`POST /refresh`）
6. 認証済み API ガード（`GET /me`）
7. ログアウト（アクセストークン失効 + リフレッシュトークン失効）

### 含まない（後フェーズ）

- メール確認・パスワードリセット
- OAuth / OIDC
- alchemy-engine / alchemy-assets との本番統合
- 管理画面

## API（v1）

| Method | Path | 認証 | 説明 |
|:---|:---|:---|:---|
| `POST` | `/api/v1/auth/register` | なし | ユーザー登録 → セッション発行 |
| `POST` | `/api/v1/auth/login` | なし | ログイン(username or email)→ セッション発行 |
| `POST` | `/api/v1/auth/refresh` | なし | リフレッシュトークン → 新規アクセストークン |
| `POST` | `/api/v1/auth/logout` | Bearer | ログアウト(リフレッシュトークンも失効可) |
| `GET` | `/api/v1/auth/me` | Bearer | 認証済みユーザー情報 |
| `GET` | `/health` | なし | ヘルスチェック |
| `GET` | `/.well-known/jwks.json` | なし | JWT 検証用公開鍵 |

### リクエスト / レスポンス例

**Register**

```http
POST /api/v1/auth/register
Content-Type: application/json

{
  "username": "frick",
  "email": "user@example.com",
  "password": "Secret123",
  "birthday": "2000-01-31",
  "promo_code": "ABC123",
  "tos_agreed": true,
  "remember_me": true
}
```

- `username`: 3〜20 文字、英数字とアンダースコアのみ(大文字小文字非区別で一意)
- `password`: 8 文字以上、数字・小文字・大文字を各 1 以上
- `birthday`: `YYYY-MM-DD`(過去日付)
- `promo_code`: 任意
- `tos_agreed`: `true` 必須(同意時刻と規約バージョンを記録)
- `remember_me`: 任意。`true` でリフレッシュトークンを発行

```json
HTTP/1.1 201 Created

{
  "access_token": "eyJ...",
  "token_type": "Bearer",
  "expires_in": 86400,
  "refresh_token": "opaque...",
  "user": {"user_id": "550e8400-...", "username": "frick", "email": "user@example.com"}
}
```

バリデーションエラーはフィールド別に返す:

```json
HTTP/1.1 422 Unprocessable Entity

{"errors": {"detail": "validation failed", "fields": {"password": ["must contain at least 1 uppercase letter"]}}}
```

**Login**

```http
POST /api/v1/auth/login
Content-Type: application/json

{"identifier": "frick", "password": "Secret123", "remember_me": true}
```

- `identifier`: username または email(`@` の有無で判定)

```json
HTTP/1.1 200 OK

{
  "access_token": "eyJ...",
  "token_type": "Bearer",
  "expires_in": 86400,
  "refresh_token": "opaque...",
  "user": {"user_id": "550e8400-...", "username": "frick", "email": "user@example.com"}
}
```

**Refresh(Remember Me)**

```http
POST /api/v1/auth/refresh
Content-Type: application/json

{"refresh_token": "opaque..."}
```

- 最終使用から 7 日以内なら新しいアクセストークンを発行し、使用時刻を更新(スライディング)
- 7 日超過・失効済みは `401`

**Logout**

```http
POST /api/v1/auth/logout
Authorization: Bearer eyJ...
Content-Type: application/json

{"refresh_token": "opaque..."}
```

- アクセストークン(`jti`)を失効。`refresh_token` を渡すとそれも失効(任意)

**Me**

```http
GET /api/v1/auth/me
Authorization: Bearer eyJ...
```

```json
HTTP/1.1 200 OK

{"user_id": "550e8400-...", "username": "frick", "email": "user@example.com", "status": "active"}
```

## JWT クレーム

ログイン成功時に発行する Payload の固定項目:

| クレーム | 説明 | 例 |
|:---|:---|:---|
| `sub` | ユーザー UUID（他サービスの `owner_user_id` と一致） | `"550e8400-..."` |
| `status` | ユーザー状態 | `"active"` |
| `iss` | 発行者 | `"alchemy-auth"` |
| `aud` | 受信者 | `"alchemy-platform"` |
| `iat` | 発行時刻（Unix 秒） | `1719148167` |
| `exp` | 失効時刻（Unix 秒） | `1719234567` |
| `jti` | トークン一意 ID（ログアウト失効用） | `"7c9e6679-..."` |

- 署名方式: **RS256**（本サービスのみ秘密鍵を保持）
- 他サービス（alchemy-engine, alchemy-assets）は `/.well-known/jwks.json` の公開鍵で検証する
- **パスワード・password_hash は JWT に含めない**
- engine 等の外部 verifier 向け検証契約: [jwt-jwks-engine-contract.md](.workspace/0_docs/jwt-jwks-engine-contract.md)

## セキュリティ方針

- パスワードは Argon2 ハッシュのみ保存（平文禁止）
- ログイン失敗時は常に同じエラーメッセージ（ユーザー列挙の防止）
- ログイン / 登録にレート制限（目標: 5 回 / 15 分 / IP）
- `status` が `suspended` / `deleted` のユーザーはログイン・JWT 検証の両方で拒否

## ローカル開発

### 前提

- Elixir 1.19 / OTP 28
- Docker（PostgreSQL 用）

### 起動（Docker 一式）

PostgreSQL と Phoenix をまとめて起動する場合:

```bash
docker compose up -d --build
```

初回はイメージビルドと `mix ash.setup` / `ecto.create` / `ecto.migrate` が走るため、数分かかることがあります。`http://localhost:4002/health` で確認できます。

ソースはコンテナに bind mount されるため、コード変更はホスト側で保存すれば `mix phx.server` が再コンパイルします（`deps` / `_build` は名前付きボリュームで永続化）。

### 起動（ホストで Elixir を実行）

PostgreSQL のみ Docker、Elixir は WSL / ローカルで動かす場合:

```bash
# PostgreSQL のみ
docker compose up -d postgres

# 依存関係・DB
mix deps.get
mix ecto.create
mix ecto.migrate

# サーバー起動（デフォルト port 4002）
mix phx.server
```

### スモークテスト

```powershell
curl -X POST http://localhost:4002/api/v1/auth/register `
  -H "Content-Type: application/json" `
  -d '{"username":"tester","email":"test@example.com","password":"Secret123","birthday":"2000-01-31","tos_agreed":true}'

curl -X POST http://localhost:4002/api/v1/auth/login `
  -H "Content-Type: application/json" `
  -d '{"identifier":"tester","password":"Secret123"}'
```

Docker 起動時はシード（`priv/repo/seeds.exs`）によりデバッグ用アカウント（`alice` / `bob` / `carol` / `admin`、パスワードはいずれも `Password1`）が自動作成される。

## 環境変数

| 変数 | 説明 | 例 |
|:---|:---|:---|
| `DATABASE_URL` | PostgreSQL 接続 URL | ホスト: `...@localhost:5433/...` / Docker 内: `...@postgres:5432/...` |
| `SECRET_KEY_BASE` | Phoenix 秘密鍵 | （`mix phx.gen.secret` で生成） |
| `JWT_PRIVATE_KEY_PATH` | RS256 秘密鍵 PEM パス | `priv/jwt_private.pem` |
| `JWT_VERIFICATION_KEY_PATHS` | ローテーション猶予用の追加検証鍵 PEM（カンマ区切り） | （空） |
| `JWT_ISSUER` | JWT `iss` クレーム | `alchemy-auth` |
| `JWT_AUDIENCE` | JWT `aud` クレーム | `alchemy-platform` |
| `PORT` | HTTP ポート | `4002` |
| `BIND_ALL` | `0.0.0.0` で待ち受け（Docker 用） | `true` |
| `PHX_SERVER` | サーバープロセスを起動 | `true` |
| `DATABASE_SSL` | PostgreSQL 接続を SSL/TLS で行う | `true` |
| `DATABASE_SSL_CA_CERT` | DB サーバー CA 証明書のパス（peer 検証 + ホスト名検証を有効化） | `/etc/ssl/certs/ca.pem` |
| `PHX_HOST` | 本番 URL のホスト名 | `auth.example.com` |

## 本番デプロイ

本番起動は **`mix release` ビルド + `bin/auth start`** を正とする。ローカル開発用の `mix phx.server` や `docker compose up`（dev ターゲット）は本番向けではない。

### ビルド

```bash
MIX_ENV=prod mix deps.get --only prod
MIX_ENV=prod mix compile
MIX_ENV=prod mix release
```

成果物は `_build/prod/rel/auth/` に出力される。

### 起動

必須の環境変数:

- `DATABASE_URL`
- `SECRET_KEY_BASE`
- `JWT_PRIVATE_KEY_PATH`（release 同梱の `priv/jwt_private.pem` 以外を使う場合）
- `PHX_SERVER=true`

マネージド PostgreSQL では `DATABASE_SSL=true` を設定する。CA 検証とホスト名検証が必要な場合は `DATABASE_SSL_CA_CERT` に証明書パスを指定する（`verify_peer` とホスト名一致チェックが有効になる）。

```bash
export PHX_SERVER=true
export DATABASE_URL=ecto://USER:PASS@HOST:5432/alchemy_auth_prod
export SECRET_KEY_BASE=...
export DATABASE_SSL=true

_build/prod/rel/auth/bin/auth start
```

### DB マイグレーション（release 実行時）

Mix が無い本番環境では release eval でマイグレーションを実行する:

```bash
_build/prod/rel/auth/bin/auth eval "Auth.Release.migrate()"
```

### Docker（本番 release イメージ）

`Dockerfile` の `release` ターゲットで本番イメージをビルドする:

```bash
docker build --target release -t alchemy-auth:release .
```

起動例:

```bash
docker run --rm -p 4002:4002 \
  -e PHX_SERVER=true \
  -e DATABASE_URL=ecto://USER:PASS@HOST:5432/alchemy_auth \
  -e SECRET_KEY_BASE=... \
  -e DATABASE_SSL=true \
  alchemy-auth:release
```

ローカル開発は従来どおり `docker compose up`（`Dockerfile` の `dev` ターゲット）を使う。

## ヘルスチェック

| Method | Path | 認証 | 説明 |
|:---|:---|:---|:---|
| `GET` | `/health` | なし | プロセス生存確認（liveness） |

**レスポンス（200 OK）**

```json
{
  "status": "ok",
  "service": "alchemy-auth",
  "version": "0.1.0"
}
```

- `status`: 常に `"ok"`（アプリが応答可能なとき）
- `service`: サービス識別子
- `version`: release / アプリバージョン（`mix.exs` の `version`）

ロードバランサやオーケストレータの liveness probe に利用する。DB 到達性は別途監視する（本エンドポイントは DB 接続を検証しない）。

## ポート方針

| サービス | ポート |
|:---|:---|
| alchemy-auth（本サービス） | **4002** |
| alchemy-engine | 4000 |

## テスト

```powershell
mix test
```

PR 前のローカル品質ゲート:

```powershell
mix precommit
```

CI では PostgreSQL 16 サービスコンテナ上で次を順に実行する:

1. `mix format --check-formatted`
2. `mix compile --warnings-as-errors`
3. `mix credo --strict`
4. `mix ecto.create` → `mix ecto.migrate` → `mix test`

## 関連リポジトリ

| リポジトリ | 関係 |
|:---|:---|
| [alchemy-engine](https://github.com/FRICK-ELDY/alchemy-engine) | ゲームエンジン。JWT 検証後に Room Token を発行 |
| [alchemy-protocol](https://github.com/FRICK-ELDY/alchemy-protocol) | ゲームワイヤ契約（Protobuf） |
| alchemy-assets（予定） | アセットメタデータ。JWT `sub` を `owner_user_id` として参照 |

## ライセンス

（alchemy-engine と同じライセンスを適用予定）

## ステータス

🚧 **初期開発中** — Ash リソース・JWT・認証 API まで実装済み。CI 品質ゲートと release 本番起動経路を整備済み。
