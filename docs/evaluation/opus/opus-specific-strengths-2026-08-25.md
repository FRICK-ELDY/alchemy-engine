# Opus 評価 — プラス点詳細一覧

評価日: 2026-08-25 / 評価者: Claude Opus 5（第1評価者）
対象: `engine/`（umbrella 4 アプリ + `rust/nif` + `rust/client` 10 クレート）+ `auth/`（認証サービス）+ `assets/`（アセット・永続化サービス、今回から評価対象）
検証対象コミット: engine `8f35a57`（main、作業ツリークリーン）
前回評価: Fable 5 / 2026-07-31（`docs/evaluation/fable/archive/2026-07-31/`）— プラス 68 項目 / +185 点

実行確認: `elixir -S mix alchemy.ci` = **ALL PASSED**（exit 0、23 秒）。`mix test` 180 tests / 0 failures（core 46 / network 102 / contents 32）。Rust `#[test]` は 58 件（nif 6 / shared 18 / network 6 / render_frame_proto 2 / audio 2 / auth_client 8 / system_ui 16）。

## 採点基準

| 点数 | 基準 |
|:---:|:---|
| +1 | 正しく実装されている。問題はないが特筆するほどではない |
| +2 | 業界の一般的なベストプラクティスに沿った、良い設計判断 |
| +3 | 同規模・同種プロジェクトの平均を明確に上回る実装 |
| +4 | プロダクションレベルのゲームエンジン・OSS と比較しても遜色ない実装 |
| +5 | このクラスの個人プロジェクトでは見たことがないレベルの卓越した実装 |

上限・下限なし。同一観点内で複数項目を合算する。

---

## プロジェクト全体（アーキテクチャ）

前回はこの大分類にプラス項目を置いていなかった（マイナスのみ -9）。今回は「アーキテクチャ上の意思決定そのもの」を独立して評価する。

### 権威と境界の設計

- **二層 SSoT の明文化と実装の一致** `+3`
  > 「ドメインの正本は Elixir、ワイヤの正本は経路・形式ごとに別」という二層構造を README で宣言し（`README.md:45-48`）、実装がそのとおりになっている。Zenoh の `RenderFrame` は submodule `3rdparty/alchemy-protocol/proto` を正本として Elixir・Rust の双方に生成し（`.github/workflows/ci.yml:84-89`, `rust/client/network/build.rs:57-75`）、UDP の外枠は `Network.UDP.Protocol` が唯一の定義（`apps/network/lib/network/udp/protocol.ex:9-47`）、Phoenix はチャネルごとの JSON。「SSoT はひとつ」と言い切らずに層ごとに正本を分けて明示する設計は、分散システムの現実に即しており、同規模の個人プロジェクトではまず見ない整理である。
  > 対象ファイル: `engine/README.md`, `engine/apps/network/lib/network/udp/protocol.ex`

- **NIF をゲームロジックから撤退させた判断** `+4`
  > サーバ側 NIF は `run_formula_bytecode/3` の 1 関数のみで（`rust/nif/src/nif/formula_nif.rs:26-32`、`#[rustler::nif]` は全クレートで 1 箇所）、`load.rs:1` は「リソース型（GameWorld 等）は登録しない」と明記する。以前あった ECS・SoA・SIMD 物理の NIF を撤去し、権威状態を Elixir に戻した意思決定である。NIF を増やす方向に進むプロジェクトは多いが、逆方向に削って BEAM の耐障害性と可観測性を取り戻した例は稀で、`ResourceArc` 使用箇所ゼロ・`unsafe` が OpenXR 由来 2 箇所のみという結果に直結している。撤去に伴い性能上の武器（SIMD 物理）を失った一方で、ロック競合と GC 連動ライフタイムという NIF 最大の危険源を構造ごと消した。
  > 対象ファイル: `engine/rust/nif/src/nif/formula_nif.rs`, `engine/rust/nif/src/nif/load.rs`

- **レイヤ逆転を「注入」で一貫して解消する手法** `+3`
  > 下位（core / engine 層）が上位（contents / network）を参照してしまう問題に対し、同じ形の解法を横断的に適用している。コンテンツ本体は `config :server, :current` から実行時解決（`apps/core/lib/core/config.ex:15-24`）、Zenoh publish は `{Network.ZenohBridge, :publish_frame, []}` の MFA を config 経由で `apply/3`（`config/config.exs:104-108`, `apps/contents/lib/events/game.ex:534-538`）、`FormulaStore` の broadcast も `{Network.Distributed, :broadcast, []}` の MFA（`apps/core/lib/core/formula_store.ex:14-19`, `config/config.exs:98-102`）。ばらばらのアドホックな回避策ではなく 1 つのパターンとして定着しており、読み手が次の逆転をどう解くか予測できる。
  > 対象ファイル: `engine/config/config.exs`, `engine/apps/core/lib/core/formula_store.ex`

### サービス分割

- **engine / auth / assets の 3 サービス分割と責務境界** `+2`
  > 認証（`auth/`）とアセット永続化（`assets/`）を engine から切り離し、境界を JWT / JWKS という標準契約で結んでいる。engine 側は JWKS を取得して RS256 検証するだけで revocation DB を参照しない設計を文書と実装の両方で固定し（`auth/docs/jwt-jwks-engine-contract.md:10-61`, `apps/network/lib/network/auth_verifier.ex:174-212`）、Rust クライアントは auth と HTTPS で直接話し Zenoh を経由しない（`rust/client/auth_client/src/lib.rs:1-5`）。「連合として他運営者にサーバを配る」という構想に対して、単一 umbrella に全部詰めない選択は妥当である。
  > 対象ファイル: `auth/docs/jwt-jwks-engine-contract.md`, `engine/rust/client/auth_client/src/lib.rs`

**プロジェクト全体プラス小計: +12**（前回 —）

---

## auth（認証サービス）

2026-08-01 以降の auth コミットはドキュメント 2 件のみで `lib/` は無変更。前回プラス 19 項目を現ソースで再確認し、すべて存続を確認した。契約文書を 1 項目として追加している。

### トークン・暗号設計

- **RS256 非対称 JWT + マルチ鍵 JWKS** `+5`
  > `Auth.Token.Keys` が RSA 2048 のアクティブ鍵と `jwt_verification_key_paths` による検証専用鍵を同時に保持し、JWKS の各鍵に thumbprint 由来の `kid` / `"use":"sig"` / `"alg":"RS256"` を付けて公開する（`auth/lib/auth/token/keys.ex:54-99,124-125`）。検証側は `kid` を peek して該当 signer を選ぶ（`auth/lib/auth/token.ex:37-125`）。つまり鍵ローテーション中も旧 kid の署名を検証し続けられる。個人プロジェクトの認証は HS256 共有秘密で済ませるのが通例で、engine / assets の 2 サービスが検証鍵を持たずに JWKS だけで独立検証できる構成まで作り込んでいるのは水準が違う。
  > 対象ファイル: `auth/lib/auth/token/keys.ex`, `auth/lib/auth/token.ex`

- **リフレッシュトークンのローテーション + family 再利用検知** `+5`
  > refresh は使用ごとに revoke して同じ `family_id` で再発行し（`auth/lib/auth/accounts.ex:307-318,354-357`）、失効済みトークンが再提示された場合は `refresh_token_reuse_grace_seconds`（10 秒）を超えていれば family 全体を失効させる（`auth/config/config.exs:21`, `auth/lib/auth/accounts.ex:104-126`）。ネットワーク再送による正当な二重使用を grace で許し、盗用は family ごと切るという線引きで、OAuth 2.1 の refresh token rotation 推奨をそのまま実装している。テストも存在する（`auth/test/auth/accounts_test.exs:151-157`）。
  > 対象ファイル: `auth/lib/auth/accounts.ex`, `auth/config/config.exs`

- **Argon2id + 体系的なタイミング攻撃対策** `+4`
  > ハッシュは `Argon2.hash_pwd_salt/1`、検証は `Argon2.verify_pass/2`、ユーザー不在時は `Argon2.no_user_verify/0` を呼んで応答時間を揃える（`auth/lib/auth/password.ex:1-36`）。ハッシュ処理は Ash の change として登録され、登録アクションから外れない（`auth/lib/auth/accounts/changes/hash_password.ex:13-14`, `auth/lib/auth/accounts/user.ex:125`）。
  > 対象ファイル: `auth/lib/auth/password.ex`

- **jti 失効 + verify 時のユーザー状態再確認** `+3`
  > access JWT は `jti` を持ち（`auth/lib/auth/token.ex:14-31`）、logout で `TokenRevocation` に記録される（`auth/lib/auth/accounts/token_revocation.ex:16-34`）。検証は署名だけで終わらせず、失効表と DB 上の `status == :active` を毎回見る（`auth/lib/auth/token.ex:37-125`）。ステートレス JWT の弱点（失効できない・凍結が効かない）を、失効表 + 状態再確認という最小コストで塞いでいる。
  > 対象ファイル: `auth/lib/auth/token.ex`

- **リフレッシュ・アカウントトークンの SHA-256 ハッシュ保存** `+3`
  > refresh も `AccountToken`（メール検証・パスワードリセット）も平文を保存せず SHA-256 の hex を保存し、識別も unique identity で行う（`auth/lib/auth/accounts.ex:399-402,506-507`, `auth/lib/auth/accounts/refresh_token.ex:1-89`, `auth/lib/auth/accounts/account_token.ex:5-6`）。DB 流出時に「トークンがそのまま使える」状態を作らない基本を全トークン種で守っている。
  > 対象ファイル: `auth/lib/auth/accounts.ex`, `auth/lib/auth/accounts/refresh_token.ex`

- **access token の TTL 15 分** `+1`
  > `jwt_ttl_seconds: 900`（`auth/config/config.exs:16`）。短命 access + 長命 refresh の教科書的な組み合わせで、失効表の肥大も抑えられる。
  > 対象ファイル: `auth/config/config.exs`

### セキュリティ・レート制限

- **多軸レート制限（12 バケット + 429 + Retry-After + telemetry）** `+4`
  > login / register / refresh / resend / forgot / reset / verify の各アクションを IP・識別子・メール・トークン family の軸で 12 バケットに分けて定義し（`auth/lib/auth/rate_limit.ex:12-25`）、超過時は `[:auth, :rate_limit, :throttle]` を `action` / `axis` / `bucket` 付きで emit（`auth/lib/auth/rate_limit.ex:93-97`）、HTTP は `Retry-After` を返す（`auth/lib/auth_web/plugs/rate_limit.ex:38-42`）。refresh は IP に加えてトークン family 軸でも絞る（`auth/lib/auth_web/plugs/rate_limit.ex:177-185`）。認証サービスで実際に効く軸（識別子・family）を選べているのが良い。
  > 対象ファイル: `auth/lib/auth/rate_limit.ex`, `auth/lib/auth_web/plugs/rate_limit.ex`

- **Authenticate プラグの防御深度** `+3`
  > `Bearer ` の前置と `byte_size(token) > 0` を要求してから検証に入り、失敗時は必ず `halt()` する（`auth/lib/auth_web/plugs/authenticate.ex:15-36`）。assign は `current_user` / `current_user_id` / `token_claims` に分離され、後段が claims を再パースしなくて済む。
  > 対象ファイル: `auth/lib/auth_web/plugs/authenticate.ex`

- **列挙安全な応答設計** `+2`
  > 登録失敗は `Accounts.generic_register_failure()`、ログイン失敗は `Accounts.invalid_credentials_message()` に統一され、「メールが存在するか」を応答差から推測できない（`auth/lib/auth_web/controllers/auth_controller.ex:46,68-71,85,204-207`）。メッセージ文言をドメイン層の関数に集約しているため、経路が増えても揺れない。
  > 対象ファイル: `auth/lib/auth_web/controllers/auth_controller.ex`

- **ClientIp + trusted proxies** `+2`
  > `X-Forwarded-For` を無条件に信じず、peer が信頼プロキシに含まれるときだけ `RemoteIp.from/2` で解決する（`auth/lib/auth_web/client_ip.ex:6-26`）。既定は空リスト（`auth/config/config.exs:32`）で、prod は環境変数から注入（`auth/config/runtime.exs:125-132`）。レート制限の IP 軸が偽装で無効化される典型的な穴を塞いでいる。
  > 対象ファイル: `auth/lib/auth_web/client_ip.ex`

### アカウントライフサイクル

- **パスワードリセット・変更・退会 API** `+4`
  > `forgot-password` / `reset-password` / `change_password` / `deactivate` が実装され、Ash のアクションとして状態遷移が定義されている（`auth/lib/auth_web/router.ex:22-25`, `auth/lib/auth/accounts/user.ex:6-166`）。認証サービスとして「作る」だけでなく「直す・やめる」経路まで揃っているのは、MVP を名乗るサービスとしては明確に平均以上である。
  > 対象ファイル: `auth/lib/auth_web/router.ex`, `auth/lib/auth/accounts/user.ex`

- **メール検証フロー** `+3`
  > `AccountToken` に `purpose`（`:email_verification` / `:password_reset`）・`expires_at`・`used_at` を持たせ、ワンタイム消費と期限を表現している（`auth/lib/auth/accounts/account_token.ex:1-85`）。`verify-email` / `resend-verification` のエンドポイントも実装済み（`auth/lib/auth_web/router.ex:22-25`）。フロー自体の作りは丁寧である（ただしログインのゲートに繋がっていない点はマイナス側に計上した）。
  > 対象ファイル: `auth/lib/auth/accounts/account_token.ex`

### ドメイン・データ設計

- **Ash リソースによる多層バリデーション** `+3`
  > `Auth.Accounts.User` に属性制約・identities（`unique_email` / `unique_username`）・カスタムバリデーション（`PasswordComplexity` / `BirthdayInPast`）をリソース定義として集約している（`auth/lib/auth/accounts/user.ex:6-166`）。コントローラに散らばりがちな検証がドメイン 1 箇所に寄っており、API 経路が増えても検証が抜けない。
  > 対象ファイル: `auth/lib/auth/accounts/user.ex`

- **TOS 同意の時刻・バージョン記録** `+3`
  > `tos_*` 属性で同意時刻と同意バージョンを永久記録する（`auth/lib/auth/accounts/user.ex:6-166`）。VRSNS として不可避の法的要件を、後付けが難しいスキーマ側で先に押さえている。
  > 対象ファイル: `auth/lib/auth/accounts/user.ex`

### 運用・テスト・配布

- **テスト 107 件（14 モジュール）** `+4`
  > `auth/test/` 配下に 15 ファイル・`test` ブロック 107 件。内訳も偏っておらず、accounts 28 / auth_controller 21 / account_lifecycle 13 / rate_limit（本体 5 + plug 7）/ keys 6 / token 4 / token_cleanup 4 / error_json 3 と、セキュリティの要所に集まっている。認証サービスとしてテストすべき対象を選べている。
  > 対象ファイル: `auth/test/`

- **本番 release + multi-stage Dockerfile（非 root）** `+3`
  > `dev` / `build` / `release` の 3 ステージで、release ステージは Alpine 上の非 root ユーザー `auth` で `bin/auth start`（`auth/Dockerfile:5-71`）。マイグレーションは `Auth.Release.migrate/0` としてリリース内に持つ（`auth/lib/auth/release.ex:6-12`）。engine 側に release 定義がないことと対照的に、こちらは配布形態が確定している。
  > 対象ファイル: `auth/Dockerfile`, `auth/lib/auth/release.ex`

- **prod secrets + DB SSL の fail-fast** `+2`
  > `runtime.exs` の 2 箇所で `raise` により必須設定の欠落を起動時に落とす（`auth/config/runtime.exs:74,229`）。デプロイ時の「設定を入れ忘れたまま起動して静かに脆弱」を防いでいる。
  > 対象ファイル: `auth/config/runtime.exs`

- **TokenCleanup 定期 GC** `+2`
  > OTP 子プロセスとして 1 時間ごとに、期限切れ `TokenRevocation` と失効済み・非アクティブ `refresh_tokens` を削除し、完了を構造化ログに残す（`auth/lib/auth/token_cleanup.ex:50-96`, `auth/config/config.exs:20-23`）。失効表がある設計に GC を最初から組み込んでいるのが良い。
  > 対象ファイル: `auth/lib/auth/token_cleanup.ex`

- **CI 品質ゲート + precommit エイリアス** `+2`
  > CI は Postgres サービス付きで format → compile（`--warnings-as-errors`）→ credo --strict → ecto → test の順に実行し（`auth/.github/workflows/ci.yml:10-55`）、同じ内容をローカルで走らせる `precommit` エイリアスもある（`auth/mix.exs:87-93`）。engine 側が CI を無効化していた期間も、auth の CI は有効なままだった。
  > 対象ファイル: `auth/.github/workflows/ci.yml`, `auth/mix.exs`

- **engine 向け JWT / JWKS 契約文書** `+2`
  > `auth/docs/jwt-jwks-engine-contract.md:10-61` が iss / aud / kid 必須・RS256 固定・「engine は revocation DB を参照しない」までを明示し、engine 側の `AuthVerifier` の実装がそれに一致している（`engine/apps/network/lib/network/auth_verifier.ex:174-212`）。サービス間契約を文書として固定してから両側を書く順序が守られている。
  > 対象ファイル: `auth/docs/jwt-jwks-engine-contract.md`

- **Ash エラーの構造化 HTTP 整形** `+1`
  > `AuthWeb.Controllers.ErrorJSON` が Ash のエラー構造を HTTP レスポンス形へ整形し、専用テストを持つ（`auth/lib/auth_web/controllers/error_json.ex`, `auth/test/auth_web/controllers/error_json_test.exs`）。
  > 対象ファイル: `auth/lib/auth_web/controllers/error_json.ex`

**auth プラス小計: +61**（前回 +56）

---

## assets（アセット・永続化サービス）

今回から評価対象。リポジトリルート `assets/` に 2026-08-07 の 1 コミット（`600b985`）で追加。lib 22 ファイル / テスト 3 ファイル・12 ケース。

### 権限・パス設計

- **パスポリシーの正規化とトラバーサル拒否** `+3`
  > `Assets.PathPolicy` が trim・連続スラッシュ圧縮・空文字・`./`・`..`・NUL の拒否を経てから（`assets/lib/assets/path_policy.ex:56-86`）、`users/{user_id}/private/...` のプレフィックスを強制する（`:5-8,48`）。BLOB を受けるサービスで最初に壊れる箇所を、独立モジュールとして切り出し専用テスト（4 件）で固定している（`assets/test/assets/path_policy_test.exs`）。文字列連結でパスを組んで終わりにしていない。
  > 対象ファイル: `assets/lib/assets/path_policy.ex`

- **所有権の二重強制** `+2`
  > 入口の `PathPolicy.authorize/2` で「呼び出し者の user_id とパスのプレフィックスが一致するか」を見た上で（`assets/lib/assets/path_policy.ex:17-22,89-96`）、データ層でも `ensure_owner/2` が `owner_type: :user` と `owner_id` を照合し、既存メタデータの upsert でも owner 一致を要求する（`assets/lib/assets/objects.ex:83-90,120-122`）。パス検証を通り抜けても DB 側で止まる二段構えになっている。
  > 対象ファイル: `assets/lib/assets/objects.ex`, `assets/lib/assets/path_policy.ex`

- **auth と同型の JWKS 検証 + 契約の明示** `+2`
  > `Assets.Token.Jwks` が `AUTH_JWKS_URL` から 5 分間隔で鍵を更新し、`Verifier` は RS256・iss / aud・`sub` / `jti` の UUID 形式・`status == "active"`・`exp` を検証する（`assets/lib/assets/token/jwks.ex:98-121`, `assets/lib/assets/token/verifier.ex:3-6,48-74`）。「revocation DB は参照しない」を moduledoc に明記しており、engine 側 `AuthVerifier` と同じ契約を独立実装で守っている。テスト用に静的 JWK を差し込める作りで、外部 auth なしにテストが回る（`assets/README.md:143`）。
  > 対象ファイル: `assets/lib/assets/token/verifier.ex`, `assets/lib/assets/token/jwks.ex`

### 実装の完成度

- **初回コミットで Docker Compose / CI / release まで揃えた** `+2`
  > Postgres 16 + healthcheck 付き compose（`assets/docker-compose.yml:2-49`）、auth と同一構成の CI（`assets/.github/workflows/ci.yml:1-55`）、3 ステージ Dockerfile と `bin/assets start`（`assets/Dockerfile:5-69`）が最初から入っている。骨格コミットの時点で運用形態まで決めておく進め方は、後から足す場合より安い。
  > 対象ファイル: `assets/docker-compose.yml`, `assets/Dockerfile`

- **オブジェクトサイズ上限と 413 の一貫した扱い** `+1`
  > `max_object_bytes`（既定 1 MiB、環境変数で上書き）を超えたら `{:error, :too_large}` を返し、コントローラが 413 に変換する（`assets/config/config.exs:14`, `assets/config/runtime.exs:72-74`, `assets/lib/assets/objects.ex:20-22`, `assets/lib/assets_web/controllers/object_controller.ex:110-114`）。ドメインのエラー原子と HTTP ステータスの対応が 1 箇所で閉じている。
  > 対象ファイル: `assets/lib/assets/objects.ex`, `assets/lib/assets_web/controllers/object_controller.ex`

**assets プラス小計: +10**（前回 —）

---

## engine — apps/core

### Formula エンジン

- **FormulaGraph コンパイラ（グラフ → バイトコード）** `+4`
  > ノードグラフを Kahn のトポロジカルソートで評価順に並べ、レジスタ 64 本の制約下でバイトコードに落とす（`apps/core/lib/core/formula_graph.ex:139,198-200`）。「ユーザーがノードを繋いでルールを書く」という VRSNS の要求に対して、インタプリタで済ませずコンパイラを書いている。循環検出がソートの副産物として得られる構造も素直である。
  > 対象ファイル: `engine/apps/core/lib/core/formula_graph.ex`

- **Formula バイトコード契約（Elixir エンコーダ ↔ Rust VM）** `+4`
  > OpCode 0–13 を Elixir 側（`apps/core/lib/core/formula.ex:13-20`）と Rust 側（`rust/nif/src/formula/opcode.rs:7-36`）で同じ番号・同じ意味に固定し、境界を「バイト列 1 本」に絞っている。標準入力として `dt` / `timer` を推奨する規約まで moduledoc にある（`apps/core/lib/core/formula.ex:8-11`）。言語境界を跨ぐ契約として最小かつ検証しやすい形を選べている。
  > 対象ファイル: `engine/apps/core/lib/core/formula.ex`, `engine/rust/nif/src/formula/opcode.rs`

- **FormulaStore の 3 スコープ + MFA ブロードキャスト** `+3`
  > `:synced` / `:local` / `:context` の 3 スコープで「どこまで共有される値か」を型として表し（`apps/core/lib/core/formula_store.ex:5-8`）、同期は config 注入の MFA 経由で network に投げる（`:14-19`）。core が network を知らずに分散同期できる。
  > 対象ファイル: `engine/apps/core/lib/core/formula_store.ex`

### エンジン抽象

- **`Core.Component` ビヘイビア（7 コールバックすべて optional）** `+3`
  > `on_ready` / `on_process` / `on_physics_process` / `on_event` / `on_frame_event` / `on_nif_sync` / `on_engine_message` を定義し、全件を `@optional_callbacks` にしている（`apps/core/lib/core/component.ex:54-70`）。「必要なものだけ実装する」を型で許しているため、コンポーネントの粒度を小さく保てる。context に注入されるフィールド（`world_ref` / `now` / `elapsed` / `frame_count` / `tick_ms` / `start_ms`）とシーン遷移クロージャも moduledoc で列挙されている（`:20-33`）。
  > 対象ファイル: `engine/apps/core/lib/core/component.ex`

- **`RoomSupervisor` + `Registry` によるマルチルーム基盤** `+2`
  > `DynamicSupervisor` + `Registry`（`keys: :unique`）でルームを分離し、`start_room/1` は既存ルームに `{:error, :already_started}` を返し、`stop_room/1` は `Core.FrameCache.delete/1` まで面倒を見る（`apps/core/lib/core/room_supervisor.ex:15-45`, `apps/core/lib/core/room_registry.ex:1-12`）。全ルームで tick が回るようにもなった（`apps/contents/lib/events/game.ex:46,321-324`、テスト `game_multi_room_tick_test.exs:24-31`）。ルーム停止時に付随 ETS を掃除する規律は、リソースリークを構造で防いでいる。基盤としての作りは良いが、シーン状態が単一 `Contents.Scenes.Stack` に集約されたままのためマルチルームとしては未完成であり（マイナス側 -4 に計上）、初稿で付けた加点は取り消して前回どおり +2 とする。
  > 対象ファイル: `engine/apps/core/lib/core/room_supervisor.ex`

- **権威 tick の設定化（`Core.Config` + `TICK_HZ`）** `+2`
  > `tick_hz` は許容値 `[10, 20, 30, 60]` のホワイトリスト検証を通り、`tick_ms` / `dt` に展開されてコンテンツへ注入される（`apps/core/lib/core/config.ex:12-13,32-40`）。任意の数値を受けずに列挙で縛る判断が良い。コンテンツ未設定時は起動時に `raise` する fail-fast（`:15-18`）。
  > 対象ファイル: `engine/apps/core/lib/core/config.ex`

- **`FrameCache` のエンジン語彙化** `+2`（新規）
  > ルーム別 ETS（`read_concurrency: true`）で、必須キーは `:physics_ms` のみ、`:label` / `:counters` / `:meta` は任意という契約に整理された（`apps/core/lib/core/frame_cache.ex:5-7,16,42,56-57,66-69`）。前回「BulletHell 固有スキーマ」と指摘した箇所が、エンジン層に置くべき語彙だけを残す形に直っている。
  > 対象ファイル: `engine/apps/core/lib/core/frame_cache.ex`

- **`StressMonitor` の独立プロセス設計** `+2`
  > 1 秒間隔で `physics_ms > tick_ms` を判定する監視を独立 GenServer に置き、moduledoc に「クラッシュしてもゲームは継続（one_for_one）」と設計意図を書いている（`apps/core/lib/core/stress_monitor.ex:3-5,16,65-67`）。観測系がゲーム本体を落とさない配置になっている。
  > 対象ファイル: `engine/apps/core/lib/core/stress_monitor.ex`

- **`EventBus` の monitor による購読者クリーンアップ** `+1`
  > 購読者を monitor し、落ちた購読者を購読表から外す（`apps/core/lib/core/event_bus.ex:11-17`）。pub/sub を自作するときに最初に忘れる後始末が入っている。
  > 対象ファイル: `engine/apps/core/lib/core/event_bus.ex`

**core プラス小計: +23**（前回 +21）

---

## engine — apps/contents

### ゲームループ・耐障害設計

- **バックプレッシャー設計（メールボックス深度 + 副作用の切り分け）** `+4`
  > メールボックス長が `max(tick_hz * 2, 120)` を超えたら throttled と判定し（`apps/contents/lib/events/game.ex:329-331`）、Zenoh publish や診断キャッシュ更新を落とす一方でゲーム状態の更新は続ける（`:348-349,428-430`）。「落としてよい副作用」と「落としてはいけない権威更新」を設計として分けているのが要点で、単にフレームをスキップする実装より一段上である。`[:game, :frame_dropped]` を telemetry に出して観測もできる。
  > 対象ファイル: `engine/apps/contents/lib/events/game.ex`

- **dt ベースのゲームロジック** `+2`
  > `dt = tick_ms / 1000.0` を context に注入し（`apps/contents/lib/events/game.ex:575-581`）、各コンテンツが `speed * dt` で移動を計算する（`bullet_hell_3d/playing.ex:298-305`, `canvas_test/playing.ex:136,151-153`）。tick_hz を 10 / 20 / 30 に変えてもゲーム速度が変わらない。フレーム数ベタ書きから移行済みという点で、設定化と実装が噛み合っている。
  > 対象ファイル: `engine/apps/contents/lib/contents/bullet_hell_3d/playing.ex`

- **Zenoh publish の MFA 注入** `+3`（新規）
  > 以前は `Network.ZenohBridge.publish_frame` を直呼びしていた箇所が、config の MFA を `apply/3` する形になり（`config/config.exs:104-108`, `apps/contents/lib/events/game.ex:534-538`）、lib 内の直接呼び出しは 0 件になった。`FrameBroadcaster` による段階的有効化も添えられている。専用テスト（`zenoh_frame_publish_mfa_test.exs`）で契約を固定しているのも良い。
  > 対象ファイル: `engine/apps/contents/lib/events/game.ex`, `engine/config/config.exs`

- **VR 入力のガード + malformed フォールバック** `+2`
  > 想定外の入力ペイロードで GenServer を落とさず、既定値へフォールバックする経路が用意されている（`apps/contents/lib/events/game.ex` の入力処理群）。外部から任意のバイト列が届く前提の層として妥当な姿勢である。
  > 対象ファイル: `engine/apps/contents/lib/events/game.ex`

### コンテンツシステム

- **コンテンツ差し替えアーキテクチャ（5 コンテンツで実証）** `+3`
  > `Content.CanvasTest` / `BulletHell3D` / `FormulaTest` / `Tetris` / `SampleOsc` の 5 実装が同じ `Contents.Behaviour.Content` を満たし、`config :server, :current` の 1 行で入れ替わる（`apps/contents/lib/contents.ex:8-13`, `config/config.exs:90`）。「エンジンとコンテンツの分離」は主張するだけなら簡単だが、2D パズル・3D 弾幕・OSC 連携・UI デバッグという性質の違う 5 例で成立させているのは実証として強い。
  > 対象ファイル: `engine/apps/contents/lib/contents.ex`

- **`ContentBehaviour` の契約設計（必須 12 + optional 18）** `+3`
  > `components/0` / `flow_runner/1` / `scene_*` / `initial_scenes/0` / `physics_scenes/0` / `context_defaults/0` などを必須、`build_frame/2` / `zenoh_audio_cues/1` / `entity_registry/0` などを optional として明確に分けている（`apps/contents/lib/behaviour/content.ex:18-86,197-216`）。「最低限これだけ書けばコンテンツになる」境界が型で読める。
  > 対象ファイル: `engine/apps/contents/lib/behaviour/content.ex`

- **`FrameEncoder` による protobuf 描画パイプライン** `+3`
  > DrawCommand 11 種を protobuf に変換する処理を、種別ごとに 11 ファイルへ分割している（`apps/contents/lib/contents/frame_encoder.ex:17-22,37-48,61-71`, `frame_encoder/draw_commands/`）。1 つの巨大 case 文にせず、コマンド追加時の変更範囲を 1 ファイルに閉じ込めている。
  > 対象ファイル: `engine/apps/contents/lib/contents/frame_encoder.ex`

- **シーンスタックによる遷移管理** `+2`
  > `push_scene` / `pop_scene` / `replace_scene` の 3 操作をスタック API として定義し（`apps/contents/lib/scenes/stack.ex:46-56`）、シーンは `{:transition, {:replace, Mod, arg}, ...}` を返すだけでよい（`tetris/title.ex:18`, `bullet_hell_3d/playing.ex:125`）。遷移の解釈は `Events.Game` の 1 箇所（`:616-640`）に集約されている。
  > 対象ファイル: `engine/apps/contents/lib/scenes/stack.ex`

- **`Nodes` / `Structs` の型体系** `+2`
  > `Contents.Behaviour.Nodes` を実装するノードが 20 モジュール、`nodes/` 全体で 26 ファイル。ノードグラフの各要素が同じビヘイビアで揃っているため、FormulaGraph 側が一様に扱える。
  > 対象ファイル: `engine/apps/contents/lib/nodes/`

- **パラメータ外部化と doc honesty** `+2`
  > ゲーム定数がシーンモジュールの `@` 属性として先頭に並び（`bullet_hell_3d/playing.ex:50-55`, `tetris/playing.ex:7-13`）、値の意味と単位が読める。マジックナンバーがロジック中に埋まっていないため、バランス調整の変更点が 1 箇所で済む。
  > 対象ファイル: `engine/apps/contents/lib/contents/bullet_hell_3d/playing.ex`

- **`LocalUserComponent` による入力統合** `+2`
  > 3 経路（Channel / Zenoh / UDP）から来る入力が `{:move_input, ...}` / `{:ui_action, ...}` に正規化され、コンポーネント側は経路を意識しない（`apps/network/lib/network/channel.ex:122-124`, `zenoh_bridge.ex:249-251`）。トランスポート追加時にゲーム側を触らない構造になっている。
  > 対象ファイル: `engine/apps/contents/lib/components/`

- **`Content.` / `Contents.` の名前空間規約** `+1`（新規）
  > ゲームコンテンツ本体を `Content.*`（14 モジュール）、エンジン側インフラ・コンポーネントを `Contents.*`（112 モジュール）に分ける規約が PR #340 で確立した。1 文字違いで紛らわしい面はあるが、モジュール名から「差し替え対象か、エンジン側か」が判別できる利点は実際にある。
  > 対象ファイル: `engine/apps/contents/lib/`

**contents プラス小計: +29**（前回 +20）

---

## engine — apps/network

### トランスポート

- **3 トランスポートの統一メッセージ収束** `+4`
  > Phoenix Channels / UDP / Zenoh の 3 経路が、最終的に `Core.RoomRegistry.get_loop` 経由の `send(pid, {:move_input, ...})` / `{:ui_action, ...}` に収束する（`apps/network/lib/network/channel.ex:122-124`, `zenoh_bridge.ex:249-251`, `udp/server.ex` moduledoc `:15-16`）。トランスポートを 3 つ持ちながらゲーム側の入力インターフェースが 1 つに保たれており、Zenoh は `:zenoh_enabled` で起動制御されるため経路の増減が supervision tree で表現される（`application.ex:43-48`）。
  > 対象ファイル: `engine/apps/network/lib/network/zenoh_bridge.ex`, `engine/apps/network/lib/network/channel.ex`

- **UDP プロトコルの明示的定義と不正パケット耐性** `+3`（前回 +2 から加点）
  > `<<type::8, seq::32, payload::binary>>` のヘッダと 9 種のパケット型を 1 モジュールに定義し（`apps/network/lib/network/udp/protocol.ex:9-47`）、`room_id` は 64 バイト上限・NUL 禁止（`:140,196-197`）。バイナリプロトコルを自作する際に必要な「形式の正本を 1 ファイルに置く」が守られている。
  > 対象ファイル: `engine/apps/network/lib/network/udp/protocol.ex`

- **zlib 展開上限による zip bomb 対策** `+3`（新規）
  > `@max_uncompressed_frame_bytes 64 * 1024` を置き、チャンク累積で上限を超えたら `:error` を返す `safe_inflate_limited/4` を実装（`apps/network/lib/network/udp/protocol.ex:49-50,242-261`）。64KB + 1 バイトのテストで境界を固定している（`network_udp_test.exs:247-251`）。前回 -3 とした指摘に対する、テスト付きの正面からの修正である。
  > 対象ファイル: `engine/apps/network/lib/network/udp/protocol.ex`

- **UDP セッションの淘汰** `+2`（新規）
  > `session_timeout_ms: 30_000` / `sweep_interval_ms: 5_000` の設定と `:sweep_sessions` による定期淘汰、PING での `touch_session` による延長（`config/config.exs:37-40`, `apps/network/lib/network/udp/server.ex:61-63,202-205,278-285,365-380`）。タイムアウトと延長の両方にテストがある（`network_udp_test.exs:422-485`）。コネクションレスな経路にセッション寿命を持ち込む定石を実装している。
  > 対象ファイル: `engine/apps/network/lib/network/udp/server.ex`

- **`ZenohBridge` の DoS 防御** `+3`
  > 受信ペイロードのサイズ・形式チェックと不正入力の破棄が入っており、外部から任意のバイト列が届く経路として妥当な防御を持つ（`apps/network/lib/network/zenoh_bridge.ex:196-236,289-310`）。
  > 対象ファイル: `engine/apps/network/lib/network/zenoh_bridge.ex`

### 認証

- **`AuthVerifier`（JWKS 取得 + RS256 限定検証）** `+3`（新規）
  > JWKS を TTL 10 分でキャッシュし、`alg` は `"RS256"` のみ許容、clock skew は ±60 秒、claims は iss / aud / exp / iat / `sub`（UUID）/ `jti`（UUID）/ `status == "active"` を検証する（`apps/network/lib/network/auth_verifier.ex:5-9,18-19,174-176,195-212`）。`alg` を固定して alg 混同攻撃を潰し、UUID 形式まで見るのは実装として硬い。Supervisor 配下で稼働し（`application.ex:55`）、専用テストもある（`network_auth_verifier_test.exs`）。
  > 対象ファイル: `engine/apps/network/lib/network/auth_verifier.ex`

- **RoomToken によるスコープ付き WebSocket 認証** `+3`
  > WebSocket 経路は `AUTH_REQUIRED` の値にかかわらず常に RoomToken を要求する（`apps/network/lib/network/room_auth.ex:8`, `channel.ex:75`）。「既定でオフ」の他経路と違い、ブラウザから届く経路だけは常時必須という線引きは合理的である。
  > 対象ファイル: `engine/apps/network/lib/network/room_auth.ex`, `engine/apps/network/lib/network/channel.ex`

### 分散・テスト

- **OTP ルーム隔離の実証テスト** `+3`
  > ルーム間のクラッシュ分離を主張だけで済ませず、テストで実証している（`apps/network/test/network_local_test.exs`, `network_distributed_test.exs`）。network は 9 テストファイル・102 ケースで、umbrella 中で最もテストが厚い（180 件中 102 件）。
  > 対象ファイル: `engine/apps/network/test/`

- **protobuf 契約テスト（Elixir 側）** `+3`
  > Elixir が生成した `RenderFrame` バイト列を golden fixture として固定し、Rust 側の契約テストと同じバイト列を共有している（`apps/network/lib/network/proto/generated/`, `rust/client/network/tests/fixtures/render_frame_elixir_golden.bin`）。CI の `proto-verify` ジョブが生成物の乖離も検出する（`.github/workflows/ci.yml:84-89`）。言語境界のワイヤ契約を、生成・golden・CI の 3 点で固定している。
  > 対象ファイル: `engine/.github/workflows/ci.yml`, `engine/apps/network/test/`

- **`Distributed` の単一ノードフォールバック** `+2`
  > 単一ノード時は `Network.Local` に委譲して RPC を回避し、異ノード間の `connect_rooms` は `{:error, :rooms_on_different_nodes}` を明示的に返す（`apps/network/lib/network/distributed.ex:8-9,136-138,175-176`）。分散化していない状態を「特別扱いしない設計」で素直に速くしている。
  > 対象ファイル: `engine/apps/network/lib/network/distributed.ex`

- **S2S read-only の第一歩** `+2`（新規）
  > `GET /.well-known/alchemy-s2s.json` による自己記述と、RS256 署名・TTL 300 秒・purpose `s2s.worlds.read` を持つ `GET /api/s2s/worlds`（`apps/network/lib/network/s2s/instance.ex:1-16`, `catalog.ex:21-31`, `client.ex:14-22`, `router.ex:32-92`）。連合の本体（訪問トークン・identity federation）はまだだが、「まず自己記述と署名付きカタログ」という順序は堅実で、テストも 15KB 分書かれている（`network_s2s_test.exs`）。
  > 対象ファイル: `engine/apps/network/lib/network/s2s/instance.ex`

**network プラス小計: +31**（前回 +20）

---

## engine — apps/server

- **起動シーケンスの fail-fast** `+2`
  > 起動は「content 設定の存在確認 → children 起動 → `:main` ルーム起動」の順で、content 未設定と `:main` ルーム起動失敗の双方で `raise` する（`apps/server/lib/server/application.ex:11-13,37-41`）。children の並び順にも意図があり、`Core.FrameCache` をルームより先に起動して ETS の所有者をアプリ寿命に固定するコメントが添えられている（`:20-31`）。「起動したが実は何も動いていない」状態を作らない。
  > 対象ファイル: `engine/apps/server/lib/server/application.ex`

- **薄いエントリポイントとテスト環境の分離** `+2`
  > `server` アプリは 2 モジュール 41 行で、責務は「設定の読み取りと supervision tree の宣言」だけに留まっている（`apps/server/lib/`）。umbrella の依存もこのアプリだけが core / contents / network の 3 つを見る形で、依存の向きが 1 箇所に集約されている（`apps/server/mix.exs:25-30`）。
  > 対象ファイル: `engine/apps/server/mix.exs`

**server プラス小計: +4**（前回 +4）

---

## engine — rust/nif（Formula VM）

- **panic しないエラー境界設計** `+4`
  > エラーを 2 層に分けている。NIF 層の異常（inputs が map でない等）は `rustler::Error::Term` として返し、VM のドメインエラーは NIF 成功のまま `{:error, reason_atom, detail}` の 3 要素タプルで返す（`rust/nif/src/nif/formula_nif.rs:4-5,39-50,183-225`）。`VmError` は `Decode` / `InputNotFound` / `StoreNotFound` / `TypeMismatch` / `RegisterOutOfRange` / `DivisionByZero` の 6 種（`vm.rs:9-16`）。ユーザー作成コンテンツを実行する VM で、BEAM を落とさない境界を型として敷いているのは正しい設計である。
  > 対象ファイル: `engine/rust/nif/src/nif/formula_nif.rs`, `engine/rust/nif/src/formula/vm.rs`

- **decode の全域バウンドチェック** `+3`
  > `DecodeError` に `UnexpectedEof` / `InvalidOpCode` / `RegisterOutOfRange` / `InvalidUtf8` を持ち（`rust/nif/src/formula/decode.rs:29-34`）、レジスタ番号は `REGISTER_COUNT = 64` に対して検証される（`:26`）。任意のバイト列が来る前提で書かれている。
  > 対象ファイル: `engine/rust/nif/src/formula/decode.rs`

- **型昇格ルールの明文化と除算の境界テスト** `+2`（新規）
  > 加減乗は両辺 `I32` のとき `I32`（saturating）、それ以外は `F32` に昇格、除算は `I32/I32` のみ整数除算で `checked_div` を使い `i32::MIN / -1` を `i32::MAX` に丸める（`rust/nif/src/formula/vm.rs:123-167`）。`eq` は `F32` のみ `f32::EPSILON` 比較（`:180-196`）。前回「float 除算が整数除算に化ける」と指摘したバグが修正され、`div_f32_returns_float` / `div_i32_min_by_neg_one_does_not_panic` 等 6 件の `#[test]` で境界が固定された（`:228-306`）。指摘に対して「直す + テストで固定する」の両方をやっている。
  > 対象ファイル: `engine/rust/nif/src/formula/vm.rs`

- **saturating 算術によるオーバーフロー防御** `+2`
  > 整数演算は saturating で、オーバーフローによる panic 経路を作らない（`rust/nif/src/formula/vm.rs:123-148`）。
  > 対象ファイル: `engine/rust/nif/src/formula/vm.rs`

- **Elixir 統合テストによる失敗モード網羅** `+2`
  > `formula_test.exs`（10 テスト）が NIF 越しの失敗モードを Elixir 側から検証する。Rust 単体テストが薄い部分を、境界を跨いだ実経路で押さえている。
  > 対象ファイル: `engine/apps/core/test/core/formula_test.exs`

**rust/nif プラス小計: +13**（前回 +11）

---

## engine — rust/client

### 補間・ネットワーク

- **`SnapshotInterpolator`（適応遅延バッファ + 近傍マッチ補間）** `+5`（新規）
  > 権威 20Hz と描画 60fps の差を埋める補間器が、この 3.5 週間の最大の成果である。到着間隔を EMA（α=0.1）で推定し、遅延バッファを推定間隔の 2 倍・80〜250ms にクランプして追従させる（`rust/client/shared/src/interp.rs:13-36,528-571`）。`render_time = now - delay` で 2 枚のスナップショットを選んで補間し（`:581-616`）、バースト到着（受信間隔 5ms 未満）を検出して再生タイムラインが先走らないよう保護する（`:32,528-571`）。エンティティの突き合わせをインデックスではなく距離 3.0 以内の近傍マッチで行い、新規スポーンは `t < 1.0` の間は非表示、デスポーンは prev 座標で維持する（`:41,311-410`）。この「フライング出現・早期消滅を出さない」配慮は、素朴な lerp 実装が必ず踏む罠で、そこを設計で回避した上で 18 件の `#[test]` が退行を止めている（`:635-1075`）。テスト名（`interpolate_matches_by_nearest_not_index_when_bullet_despawns`、`playback_timeline_does_not_go_backwards_when_ahead_cap_shrinks` など）がそのまま仕様書になっているのも良い。商用のネットコードで扱う論点をこの粒度で書いた個人プロジェクトはまず見ない。
  > 対象ファイル: `engine/rust/client/shared/src/interp.rs`

- **Zenoh の publisher キャッシュ + 指数バックオフ再接続** `+4`（新規）
  > key ごとに publisher を宣言してキャッシュし（Default congestion と `CongestionControl::Drop` の 2 系統）、put のたびに declare しない（`rust/client/network/src/platform/desktop.rs:27-31,213-248`）。put 中は state ロックを持たない（`:211`）。切断時は 500ms → ×2 → 最大 8s のバックオフで再接続し、`reconnect_gate` の Mutex で多重実行を防ぎ、subscriber も再購読する（`:19-21,279-331`）。subscriber は `RingChannel::new(1)` で最新フレームのみ保持（`:458-463`）、リモート接続は `tcp/` を `udp/` に書き換えて bufferbloat を避ける（`:408-420`、判定は 5 件の `#[test]` 付き）。前回 -3 / -2 とした 2 件を、周辺の細部まで含めて仕上げている。
  > 対象ファイル: `engine/rust/client/network/src/platform/desktop.rs`

- **golden E2E protobuf 契約テスト** `+4`
  > Elixir が生成した実バイト列を fixture として Rust 側でデコードし、commands 3 件 / mesh_definitions 1 件 / ui.nodes 1 件 / `cursor_grab == Some(true)` まで検証する（`rust/client/network/tests/render_frame_e2e_contract.rs:14-98`）。`render_frame_proto` 側の契約テストは truncated / garbage の拒否も見る（`render_frame_proto/tests/decode_contract.rs`）。「言語を跨ぐワイヤ契約は実バイト列で固定する」という最も確実な方法を選んでおり、golden の SSoT がどちらかもコメントで明示されている。
  > 対象ファイル: `engine/rust/client/network/tests/render_frame_e2e_contract.rs`

### 境界・セキュリティ

- **クレート分離とセキュリティ境界** `+4`
  > 11 クレートの依存方向が意図どおりに整っている。`render_frame_proto` は wgpu / winit / egui に依存しないデコード専用クレート（`rust/client/render_frame_proto/Cargo.toml:7-10`）、イベントループの所有は `window`、描画は `render` に限定（`window/src/lib.rs:3-4`, `render/src/window.rs:4-5`）、資格情報は `auth_client` に閉じて Zenoh を通らない（`auth_client/src/lib.rs:3-5`）。「どのクレートを読めば何がわかるか」がクレート境界で表現されている。
  > 対象ファイル: `engine/rust/Cargo.toml`, `engine/rust/client/render_frame_proto/Cargo.toml`

- **`auth_client` の資格情報管理** `+4`
  > refresh token のみを OS ネイティブの資格情報ストア（Windows Credential Manager / macOS Keychain / Linux Secret Service）に保存し、access token はメモリのみに置く（`rust/client/auth_client/src/token_store.rs:6-10,22,42-52`, `Cargo.toml:17-21`）。保存・削除はバックグラウンドで行い UI をブロックしない（`token_store.rs:63-67,92-96`）。HTTP は rustls・タイムアウト 10 秒・リダイレクト無効（`api.rs:16,53-57`）。自前の平文ファイル保存で済ませていない点が明確な差である。
  > 対象ファイル: `engine/rust/client/auth_client/src/token_store.rs`

- **`unsafe` が OpenXR API 由来の 2 箇所のみ** `+2`
  > `rust/` 全体で `unsafe` ブロックは `xr::Entry::load()` と headless `create_session` の 2 箇所だけで、後者には「Headless session has no graphics binding; create_session is unsafe in the openxr API.」と理由が書かれている（`rust/client/xr/src/openxr_loop.rs:18,64-66`）。bytemuck による Pod 変換でゼロコピーを実現しつつ（`shared/src/types.rs:33-52`）、`unsafe` を持ち込まない選択をしている。
  > 対象ファイル: `engine/rust/client/xr/src/openxr_loop.rs`

### 描画・オーディオ・入力

- **3D パイプラインの GPU バッファ戦略** `+3`
  > バッファを事前確保して `write_buffer` で上書きする方式に統一し、容量を定数として明示している（`MAX_GRID_VERTS = 404` / `MAX_MESH_VERTS = 24_000` / `MAX_MESH_INDICES = 100_000`、`rust/client/render/src/renderer/pipeline_3d/mod.rs:7-8,28-36`）。描画順（スカイボックス → グリッド → メッシュ）もコメントで固定され、`Camera3D` 以外は早期 return（`renderer/mod.rs:601-604`）。毎フレームのアロケーションを避ける定石を守っている。
  > 対象ファイル: `engine/rust/client/render/src/renderer/pipeline_3d/mod.rs`

- **2D インスタンシング + コンテンツ側 WGSL 注入** `+3`
  > `SpriteInstance` によるインスタンス描画で `MAX_INSTANCES = 14510`（内訳コメント付き）を確保し、1 回の `draw_indexed` で描く（`rust/client/render/src/renderer/mod.rs:40-48,99-104,588-596`）。シェーダーは `RendererInit.sprite_wgsl` / `mesh_wgsl` として外部から注入され、`app` が `assets/shaders/*.wgsl` を読み込む（`render/src/window.rs:12-14`, `app/src/main.rs:124-137`）。描画クレートにコンテンツ固有のシェーダーを埋め込まない構造になっている。
  > 対象ファイル: `engine/rust/client/render/src/renderer/mod.rs`

- **`AssetLoader` のパストラバーサル防御** `+3`
  > 相対パスの検証（`assets/` プレフィックス強制・親ディレクトリ拒否）を行い、拒否をログに残す（`rust/client/audio/src/asset/mod.rs:152-158`）。専用テスト 2 件（`rejects_non_assets_prefix_and_parent_dir` / `reads_player_hurt_from_repo_root`）で固定している。サーバから送られたパスでファイルを読む経路として必要な防御が入っている。
  > 対象ファイル: `engine/rust/client/audio/src/asset/mod.rs`

- **オーディオのグレースフルフォールバック + コマンドパターン** `+3`（前回 +2 から加点）
  > `AudioCommand` 8 種を `mpsc::channel` で専用スレッド `"audio-thread"` に送る構造で、送信側は `Clone` 可能なハンドルを持つ（`rust/client/audio/src/audio.rs:69-85,123-129`）。デバイスが開けない場合もハンドルは常に返し、スレッド内で warn を出してコマンドを捨てる（`:19-25,122-136`）。「音が出ない環境でゲームが起動しない」を構造的に防いでおり、Elixir が指揮者として非同期コマンドを出す設計と噛み合っている。
  > 対象ファイル: `engine/rust/client/audio/src/audio.rs`

- **`window` のイベント正規化** `+2`（新規）
  > `KeyCode` + `ElementState` を `KeyState` に正規化し、`Escape` はクライアント側で消費してサーバに送らない、`Focused(false)` でカーソルを解放、`MouseMotion` はグラブ中のみ転送、system_ui 表示中はゲーム入力を遮断する（`rust/client/window/src/desktop_loop.rs:156-198`）。Windows のみ `with_any_thread(true)` を付ける分岐も明示的（`:24-25,38-39`）。「どの入力をサーバに送らないか」を層の責務として決めているのが良い。
  > 対象ファイル: `engine/rust/client/window/src/desktop_loop.rs`

- **フレームホールド + audio_cues の再送防止** `+2`
  > フレーム未着時は直前フレームを保持し、SE キューは `take_pending_audio()` で 1 回だけ取り出して二重再生を防ぐ（`rust/client/shared/src/interp.rs:574-576`, `network/src/network_render_bridge.rs:198-205`）。`CONNECTED_TIMEOUT = 3s` で接続状態も表現する（`:19-20,246-253`）。
  > 対象ファイル: `engine/rust/client/network/src/network_render_bridge.rs`

- **ヘッドレスレンダラー** `+2`
  > feature `headless` でオフスクリーン wgpu → PNG バイト列を出力でき、スプライト構築ロジックは通常経路と共有する（`rust/client/render/src/headless.rs:1-16,394-398`）。golden image 回帰の土台としてすぐ使える形になっている。
  > 対象ファイル: `engine/rust/client/render/src/headless.rs`

- **`system_ui` の状態機械テスト** `+2`
  > ログイン・登録フォームとメニューをクライアント所有の UI として実装し（`rust/client/system_ui/src/lib.rs:1-26`）、状態遷移と入力検証に 16 件の `#[test]`（`state.rs` 9 / `validation.rs` 7、`username_rules` / `birthday_rules` / `civil_from_days_known_dates` など）を置いている。UI にテストを書く習慣がある個人プロジェクトは少ない。
  > 対象ファイル: `engine/rust/client/system_ui/src/state.rs`

- **`SurfaceError::Lost` / `Outdated` からの回復** `+1`
  > サーフェス喪失時に再構成する経路がある（`rust/client/render/src/renderer/mod.rs`）。ウィンドウ操作やデバイス変更でクラッシュしない。
  > 対象ファイル: `engine/rust/client/render/src/renderer/mod.rs`

- **OpenXR 入力ループの実装前進** `+1`（新規）
  > 前回「TODO で即 `Err`」だった `openxr_loop.rs` が、セッション状態機械（READY / STOPPING）・action set・`simple_controller` バインディング・head / controller pose とボタンの `XrInputEvent` 化まで書かれた 296 行になった（`rust/client/xr/src/openxr_loop.rs:14-259`）。`openxr` を optional feature にして既定ビルドを汚さない配慮もある（`xr/Cargo.toml:7-13`）。app への配線が未了なので加点は +1 に留める。
  > 対象ファイル: `engine/rust/client/xr/src/openxr_loop.rs`

**rust/client プラス小計: +45**（前回 +32）

---

## 横断評価層

### 開発者体験（DX）

- **`mix alchemy.ci` によるローカル CI 単一エントリ** `+4`
  > Rust fmt / clippy / test と Elixir deps / format / credo / test を 1 コマンドで通し、`check` / `rust` / `elixir` の部分実行も持つ（`apps/core/lib/mix/tasks/alchemy.ci.ex:2-4,57-145`）。2026-08-25 に `8f35a57` で実行して **ALL PASSED**（exit 0、23 秒）を確認した。23 秒で全体が回るなら実際にコミット前に走らせられる速度である。周辺の mix タスクも 11 個揃っており（`alchemy.format` / `alchemy.test` / `alchemy.setup` / `alchemy.gen.proto` / `alchemy.router` / `alchemy.client` ほか）、「開発者が覚えるコマンドは mix だけ」という状態を作っている。
  > 対象ファイル: `engine/apps/core/lib/mix/tasks/alchemy.ci.ex`

- **`proto-verify` CI ジョブ（生成物ドリフト検出）** `+3`
  > proto から Elixir コードを再生成し、`mix format` を通してから `git diff --exit-code` で差分を検出する（`.github/workflows/ci.yml:84-89`）。生成物をコミットする方式の弱点（生成し忘れ）を CI で機械的に潰している。フォーマットまで通してから比較する細部も正しい。
  > 対象ファイル: `engine/.github/workflows/ci.yml`

- **`protoc-gen-elixir` のバージョンピン留め** `+1`
  > `mix escript.install hex protobuf 0.16.0 --force` と、0.17+ で出力パスが変わる旨のコメント（`.github/workflows/ci.yml:79-82`）。生成物比較を行うジョブでツールを固定するのは必須の配慮である。
  > 対象ファイル: `engine/.github/workflows/ci.yml`

- **複合アクションによる CI セットアップの重複排除** `+2`（新規）
  > 5 ジョブが共通の `./.github/actions/alchemy-ci-setup` を使い、Elixir / OTP のバージョンはワークフロー先頭の `env` 1 箇所で管理される（`.github/workflows/ci.yml:8-10,25-28`）。`concurrency` で同一 ref の実行をキャンセルする設定もある（`:12-14`）。ジョブごとのコピペ列挙になっていない。
  > 対象ファイル: `engine/.github/workflows/ci.yml`, `engine/.github/actions/alchemy-ci-setup/`

### プロジェクト全体設計

- **moduledoc の文書化品質と誠実さ** `+3`
  > 「何をするか」だけでなく「なぜそうしたか」「今どこまでか」が moduledoc に書かれている。例として `Core.FrameCache` の「core は contents 語彙を持たない」（`frame_cache.ex:5-7`）、`Network.RoomAuth` の「AUTH_REQUIRED オフ時は UDP / Zenoh は無検証」（`room_auth.ex:5-8`）、`platform/web.rs` の「未実装」明示（`network/src/platform/web.rs:1-29`）、`predict.rs` の「network 連携後に追加予定」（`predict.rs:4`）。未完成を未完成と書く姿勢は、評価者にとってもコード読者にとっても信頼できる情報源になっている（`Core.Component` の 60Hz 記述はこの原則からの逸脱としてマイナス側に計上した）。
  > 対象ファイル: `engine/apps/core/lib/core/frame_cache.ex`, `engine/rust/client/network/src/platform/web.rs`

- **エラー契約の一貫性** `+3`
  > Elixir 側は `{:ok, _}` / `{:error, reason}`、Rust 側は `Result` と `{:error, atom, detail}` タプルという対応が層をまたいで揺れていない（`rust/nif/src/nif/formula_nif.rs:183-225`, `apps/network/lib/network/room_auth.ex`, `assets/lib/assets/objects.ex:20-22`）。3 リポジトリにまたがってもエラーの表現方法が予測できる。
  > 対象ファイル: `engine/rust/nif/src/nif/formula_nif.rs`

- **テストの意図的設計** `+3`
  > テストが網羅率ではなく「守りたい設計」に向けて書かれている。`refute Map.has_key?(summary, :kills_by_enemy)` で core にゲーム語彙が戻らないことを固定し（`stats_test.exs:28`）、`zenoh_frame_publish_mfa_test.exs` で MFA 注入の契約を固定し、`game_multi_room_tick_test.exs:24-31` で非 `:main` ルームの tick 駆動を固定する。リファクタの成果をテストで凍結する運用ができている。
  > 対象ファイル: `engine/apps/core/test/core/stats_test.exs`, `engine/apps/contents/test/`

- **`workspace/` のレーン運用** `+2`
  > `1_backlog` → `2_todo` → `3_Inprogress` → `4_human_review` → `6_merging` → `7_done` のレーンと差し戻し経路（`5_rework`）を定義し、「各タスクは 1 ディレクトリのみ」「人間レビューは 4 / 6」というルールを明文化している（`workspace/README.md:9-28`）。時期非依存の参照物は `0_reference/` に分けてレーンから外す（`workspace/0_reference/README.md:13-14`）。`7_done` に 30 件、`1_backlog` に 25 件が実際に積まれており、運用が形骸化していない。
  > 対象ファイル: `engine/workspace/README.md`

- **自己評価サイクルの制度化** `+2`
  > 評価観点・採点基準・出力先・アーカイブ規約をルールとして固定し（`.cursor/rules/evaluation.mdc`）、`docs/evaluation/` に 29 ファイル分の履歴を残している。今回から第1評価者（Opus）と第2評価者（GPT）が互いの当日文書を読まずに独立評価し、その後まとめるという二重化まで入った。自分のプロジェクトの弱点を継続的に文書化し、`improvement-plan.md` に落として消化する仕組みを持つ個人プロジェクトは珍しい。
  > 対象ファイル: `engine/.cursor/rules/evaluation.mdc`, `engine/workspace/0_reference/improvement-plan.md`

- **ワイヤ正本の submodule 化** `+2`（新規）
  > Zenoh 経路の protobuf 定義を `3rdparty/alchemy-protocol/proto` の submodule として外に出し、Elixir・Rust の双方がそこから生成する（`.github/workflows/ci.yml:84-89`, `rust/client/network/build.rs:57-75`, `rust/client/render_frame_proto/build.rs:22-35`）。片側のリポジトリに正本を置くと必ず起きる「どちらが正か」問題を、置き場所で解決している。
  > 対象ファイル: `engine/3rdparty/alchemy-protocol/`, `engine/rust/client/network/build.rs`

- **構造化ログプレフィックス** `+2`
  > `auth.token_cleanup.completed` のようなドット区切りのイベント名でログを出しており（`auth/lib/auth/token_cleanup.ex:50-55`）、grep で追える。telemetry イベント名も `[:game, _]` / `[:auth, :rate_limit, :throttle]` と階層が揃っている。
  > 対象ファイル: `auth/lib/auth/token_cleanup.ex`

- **技術的負債の少なさ** `+2`
  > TODO / FIXME が散在せず、残っている未実装は `objects/core/` の 4 スタブと `platform/web.rs` のように場所と理由が特定できる形に集まっている。削除した機能（GameWorld / SoA 物理）についても legacy 文書として履歴を残し（`docs/architecture/legacy_contents-to-physics-bottlenecks.md:4`）、現行文書と混ざらないよう命名で分離している。
  > 対象ファイル: `engine/docs/architecture/`

**横断プラス小計: +29**（前回 +21）

---

## 総計

| 大分類 | 項目数 | プラス小計 | 前回（Fable 2026-07-31） | 差分 |
|:---|:---:|:---:|:---:|:---:|
| プロジェクト全体（アーキテクチャ） | 4 | +12 | —（未採点） | **+12** |
| auth | 21 | +61 | +56 | **+5** |
| assets（新規対象） | 5 | +10 | — | **+10** |
| engine — apps/core | 9 | +23 | +21 | **+2** |
| engine — apps/contents | 12 | +29 | +20 | **+9** |
| engine — apps/network | 11 | +31 | +20 | **+11** |
| engine — apps/server | 2 | +4 | +4 | — |
| engine — rust/nif | 5 | +13 | +11 | **+2** |
| engine — rust/client | 16 | +45 | +32 | **+13** |
| 横断評価層 | 12 | +29 | +21 | **+8** |
| **プラス合計** | **97** | **+257** | **+185** | **+72** |

評価項目数: 97 件（前回 68 件）。

**増分 +72 の内訳**:

| 要因 | 点数 | 主な項目 |
|:---|:---:|:---|
| この 3.5 週間の新規実装 | +36 | `SnapshotInterpolator` +5、Zenoh 再接続・publisher キャッシュ +4、`AuthVerifier` +3、zlib 上限 +3、Zenoh MFA 注入 +3、S2S +2、UDP セッション淘汰 +2、window イベント正規化 +2、`FrameCache` 汎用化 +2、型昇格テスト +2、複合アクション +2、submodule 化 +2、OpenXR 前進 +1、Content/Contents 規約 +1 ほか |
| 新規に評価対象とした領域 | +22 | assets サービス +10、プロジェクト全体（アーキテクチャ）+12 |
| 既存項目の再評価・粒度の見直し | +14 | UDP プロトコル +2→+3、オーディオ +2→+3、auth 契約文書 +2、workspace 運用 +2、自己評価サイクル +2 ほか（`RoomSupervisor` は初稿で +3 に加点したが、シーンスタック共有の発見により +2 へ戻した） |

最も評価すべきは `rust/client` の +13 で、その大半（+5 と +4）が補間器と Zenoh 信頼性という「前回マイナスとして指摘した箇所」への正面からの回答である。指摘 → 実装 → テストで固定という循環が実際に回っている。
