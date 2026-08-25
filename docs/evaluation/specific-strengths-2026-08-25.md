# プラス点 統合一覧 — 2026-08-25

評価日: 2026-08-25
検証対象コミット: engine `8f35a57`（PR #347 マージ後、作業ツリークリーン）
統合元:
- 第1評価者（Claude Opus 5）: `opus/opus-specific-strengths-2026-08-25.md`（97 項目 / **+257**）
- 第2評価者（GPT-5.6 Sol）: `gpt/gpt-specific-strengths-2026-08-25.md`（**+215**）

両評価者は互いの当日文書を参照せずに独立して採点した。本文書は両者の評価を突き合わせ、**採用点**を決めたものである。出典は **両者**（独立に同じ実装を評価）／**Opus**／**GPT** で示す。

## 採点基準

| 点数 | 基準 |
|:---:|:---|
| +1 | 正しく実装されている。問題はないが特筆するほどではない |
| +2 | 業界の一般的なベストプラクティスに沿った、良い設計判断 |
| +3 | 同規模・同種プロジェクトの平均を明確に上回る実装 |
| +4 | プロダクションレベルのゲームエンジン・OSS と比較しても遜色ない実装 |
| +5 | このクラスの個人プロジェクトでは見たことがないレベルの卓越した実装 |

---

## 最上位 — 両評価者がともに最高評価を与えた実装

- **`SnapshotInterpolator`（適応遅延バッファ + 補間）** `+5` — **両者**（Opus +5 / GPT +5）
  > 権威 20Hz と描画 60fps の差を埋める補間器。到着間隔を EMA（α=0.1）で推定し、遅延バッファを推定間隔の 2 倍・80〜250ms にクランプして追従させる（`rust/client/shared/src/interp.rs:13-36,528-571`）。`render_time = now - delay` で 2 枚を選んで補間し（`:581-616`）、バースト到着（受信間隔 5ms 未満）を検出して再生タイムラインの先走りを防ぐ。エンティティ対応は距離 3.0 以内の近傍マッチで行い、新規スポーンは `t < 1.0` の間は非表示、デスポーンは prev 座標で維持する（`:41,311-410`）。18 件の `#[test]` が仕様を凍結しており、テスト名（`interpolate_matches_by_nearest_not_index_when_bullet_despawns`、`playback_timeline_does_not_go_backwards_when_ahead_cap_shrinks`）がそのまま仕様書になっている。
  > **採用判断**: 両者一致で **+5**。商用ネットコードの論点をこの粒度で扱った個人プロジェクトはまず見ない。なお GPT は同じ実装の「安定 ID を使わない」点をマイナス -2 として別途計上しており、まとめでもその両立を採用した（マイナス点文書参照）。
  > 対象ファイル: `engine/rust/client/shared/src/interp.rs`

- **auth の暗号・トークン設計（RS256 マルチ鍵 JWKS + refresh family 再利用検知）** `+5` — **両者**（Opus +5 ×2 / GPT +5）
  > `Auth.Token.Keys` が RSA 2048 のアクティブ鍵と検証専用鍵を同時に保持し、thumbprint 由来の `kid` / `use` / `alg` 付きで JWKS を公開する（`auth/lib/auth/token/keys.ex:54-99,124-125`）。検証側は `kid` を peek して signer を選ぶため（`auth/lib/auth/token.ex:37-125`）、鍵ローテーション中も旧署名を検証できる。refresh は使用ごとに revoke して同一 `family_id` で再発行し（`auth/lib/auth/accounts.ex:307-318,354-357`）、失効済みトークンの再提示は grace 10 秒を超えれば family 全体を失効させる（`:104-126`, `auth/config/config.exs:21`）。engine と assets の 2 サービスが検証鍵を持たず JWKS だけで独立検証できる構成まで作り込まれている。
  > 対象ファイル: `auth/lib/auth/token/keys.ex`, `auth/lib/auth/accounts.ex`

---

## プロジェクト全体（アーキテクチャ）

- **NIF をゲームロジックから撤退させた判断** `+4` — **Opus**
  > サーバ側 NIF は `run_formula_bytecode/3` の 1 関数のみで（`rust/nif/src/nif/formula_nif.rs:26-32`）、`load.rs:1` は「リソース型（GameWorld 等）は登録しない」と明記する。ECS・SoA・SIMD 物理の NIF を撤去して権威状態を Elixir に戻した意思決定であり、結果が `ResourceArc` 使用ゼロ・`unsafe` 2 箇所（どちらも OpenXR API 由来）として測定できる。NIF を増やす方向に進むプロジェクトは多いが、逆方向に削って BEAM の耐障害性を取り戻した例は稀である。
  > 対象ファイル: `engine/rust/nif/src/nif/formula_nif.rs`, `engine/rust/nif/src/nif/load.rs`

- **二層 SSoT（ドメインは Elixir、ワイヤは経路ごと）の明文化と実装の一致** `+3` — **Opus**
  > README で宣言し（`README.md:45-48`）、実装がそのとおりになっている。Zenoh の `RenderFrame` は submodule `3rdparty/alchemy-protocol/proto` を正本に Elixir・Rust 双方へ生成、UDP 外枠は `Network.UDP.Protocol` が唯一の定義（`apps/network/lib/network/udp/protocol.ex:9-47`）、Phoenix はチャネルごとの JSON。「SSoT はひとつ」と言い切らずに層ごとに正本を分けて明示する整理は、同規模の個人プロジェクトではまず見ない。
  > 対象ファイル: `engine/README.md`, `engine/apps/network/lib/network/udp/protocol.ex`

- **レイヤ逆転を「注入」で一貫して解消する手法** `+3` — **両者**（Opus +3 / GPT が MFA 注入として +2）
  > コンテンツ本体は `config :server, :current` から実行時解決（`apps/core/lib/core/config.ex:15-24`）、Zenoh publish は `{Network.ZenohBridge, :publish_frame, []}` の MFA を `apply/3`（`config/config.exs:104-108`, `apps/contents/lib/events/game.ex:534-538`）、`FormulaStore` の broadcast も `{Network.Distributed, :broadcast, []}` の MFA（`apps/core/lib/core/formula_store.ex:14-19`）。アドホックな回避策ではなく 1 つのパターンとして定着しているため、読み手が次の逆転をどう解くか予測できる。
  > 対象ファイル: `engine/config/config.exs`, `engine/apps/core/lib/core/formula_store.ex`

- **engine / auth / assets の 3 サービス分割と契約の明示** `+2` — **両者**
  > 認証とアセット永続化を engine から切り離し、境界を JWT / JWKS という標準契約で結ぶ。engine 側は JWKS で検証し revocation DB を参照しない設計を文書と実装の両方で固定し（`auth/docs/jwt-jwks-engine-contract.md:10-61`, `apps/network/lib/network/auth_verifier.ex:174-212`）、Rust クライアントは auth と HTTPS で直接話し Zenoh を経由しない（`rust/client/auth_client/src/lib.rs:1-5`）。
  > 対象ファイル: `auth/docs/jwt-jwks-engine-contract.md`

**プロジェクト全体 小計: +12**（Opus +12 / GPT は本分類にプラスを計上せず +0。GPT は同内容を各アプリ側に分散計上している）

---

## auth（認証サービス）

`lib/` は 3.5 週間無変更。両評価者が独立に高評価を維持した。

- **Argon2id + 体系的なタイミング攻撃対策** `+4` — **両者**
  > `hash_pwd_salt` / `verify_pass` に加え、ユーザー不在時は `no_user_verify/0` で応答時間を揃える（`auth/lib/auth/password.ex:1-36`）。ハッシュ処理は Ash の change として登録され登録アクションから外れない（`auth/lib/auth/accounts/changes/hash_password.ex:13-14`）。
  > 対象ファイル: `auth/lib/auth/password.ex`

- **多軸レート制限（12 バケット + 429 + Retry-After + telemetry）** `+4` — **両者**
  > login / register / refresh / resend / forgot / reset / verify を IP・識別子・メール・トークン family の軸で 12 バケットに分割（`auth/lib/auth/rate_limit.ex:12-25`）。超過時は `[:auth, :rate_limit, :throttle]` を `action` / `axis` / `bucket` 付きで emit し（`:93-97`）、HTTP は `Retry-After` を返す（`auth/lib/auth_web/plugs/rate_limit.ex:38-42`）。refresh は IP に加えトークン family 軸でも絞る（`:177-185`）。
  > 対象ファイル: `auth/lib/auth/rate_limit.ex`

- **アカウントライフサイクルの完備（リセット・変更・退会・検証）** `+4` — **両者**
  > `forgot-password` / `reset-password` / `change_password` / `deactivate` / `verify-email` / `resend-verification` が実装され、Ash のアクションとして状態遷移が定義されている（`auth/lib/auth_web/router.ex:22-25`, `auth/lib/auth/accounts/user.ex:6-166`）。「作る」だけでなく「直す・やめる」経路まで揃っている。
  > 対象ファイル: `auth/lib/auth_web/router.ex`

- **jti 失効 + verify 時のユーザー状態再確認** `+3` — **両者**
  > access JWT は `jti` を持ち、logout で `TokenRevocation` に記録される（`auth/lib/auth/accounts/token_revocation.ex:16-34`）。検証は署名だけで終わらせず失効表と DB 上の `status == :active` を毎回見る（`auth/lib/auth/token.ex:37-125`）。ステートレス JWT の弱点を最小コストで塞いでいる。
  > 対象ファイル: `auth/lib/auth/token.ex`

- **全トークン種の SHA-256 ハッシュ保存** `+3` — **両者**
  > refresh も `AccountToken` も平文を保存せず SHA-256 hex で保存し unique identity で識別する（`auth/lib/auth/accounts.ex:399-402,506-507`）。DB 流出時に「トークンがそのまま使える」状態を作らない基本を全種で守っている。
  > 対象ファイル: `auth/lib/auth/accounts/refresh_token.ex`

- **Ash リソースによる多層バリデーションと TOS 記録** `+3` — **両者**
  > 属性制約・identities・カスタムバリデーション（`PasswordComplexity` / `BirthdayInPast`）をリソース定義に集約し、`tos_*` で同意時刻とバージョンを永久記録する（`auth/lib/auth/accounts/user.ex:6-166`）。後付けが難しいスキーマ側で法的要件を先に押さえている。
  > 対象ファイル: `auth/lib/auth/accounts/user.ex`

- **列挙安全な応答・ClientIp の trusted proxies・Authenticate プラグの防御深度** `+5`（3 項目合算） — **両者**
  > 登録・ログイン失敗をドメイン層の共通メッセージに統一して存在推測を防ぎ（`auth/lib/auth_web/controllers/auth_controller.ex:46,68-71,85,204-207`）、`X-Forwarded-For` は peer が信頼プロキシのときだけ採用し（`auth/lib/auth_web/client_ip.ex:6-26`、既定は空リスト）、Bearer プラグは前置と非空を確認してから検証し失敗時は必ず `halt()` する（`auth/lib/auth_web/plugs/authenticate.ex:15-36`）。レート制限の IP 軸が偽装で無効化される穴も塞がれている。
  > 対象ファイル: `auth/lib/auth_web/client_ip.ex`, `auth/lib/auth_web/plugs/authenticate.ex`

- **テスト 107 件 + CI 品質ゲート + precommit** `+5`（2 項目合算） — **両者**
  > `test` ブロック 107 件が accounts 28 / auth_controller 21 / account_lifecycle 13 / rate_limit 12 / keys 6 とセキュリティの要所に集まる。CI は Postgres 付きで format → compile（`--warnings-as-errors`）→ credo --strict → ecto → test（`auth/.github/workflows/ci.yml:10-55`）、同内容の `precommit` alias もある（`auth/mix.exs:87-93`）。engine が CI を無効化していた期間も auth の CI は有効だった。
  > 対象ファイル: `auth/test/`, `auth/.github/workflows/ci.yml`

- **本番 release + 3 ステージ Dockerfile（非 root）+ prod fail-fast + TokenCleanup** `+8`（4 項目合算） — **両者**
  > release ステージは Alpine 上の非 root ユーザーで `bin/auth start`（`auth/Dockerfile:5-71`）、マイグレーションは `Auth.Release.migrate/0`（`auth/lib/auth/release.ex:6-12`）、必須設定の欠落は `runtime.exs:74,229` で `raise`、失効表と stale refresh は 1 時間ごとに GC される（`auth/lib/auth/token_cleanup.ex:50-96`）。engine 側に release 定義がないことと対照的に、配布形態が確定している。
  > 対象ファイル: `auth/Dockerfile`, `auth/lib/auth/token_cleanup.ex`

- **engine 向け JWT / JWKS 契約文書 + Ash エラーの構造化整形 + TTL 15 分** `+4`（3 項目合算） — **Opus**
  > `auth/docs/jwt-jwks-engine-contract.md:10-61` が iss / aud / kid 必須・RS256 固定・revocation 非参照までを明示し、engine 側実装が一致する。`ErrorJSON` は Ash エラーを HTTP 形へ整形し専用テストを持つ。`jwt_ttl_seconds: 900` の短命 access + 長命 refresh。
  > 対象ファイル: `auth/docs/jwt-jwks-engine-contract.md`

（暗号・トークン設計 +5 は「最上位」節に計上済み）

**auth 小計: +48**（Opus +61 / GPT +47。項目の括り方の差が主で、評価の方向は完全に一致）

---

## assets（アセット・永続化サービス）

- **所有境界の強制（JWT sub × パスプレフィックス）** `+4` — **両者**（Opus +3 / GPT +4）
  > `PathPolicy` が trim・連続スラッシュ圧縮・空文字・`./`・`..`・NUL の拒否を経て `users/{user_id}/private/...` を強制し（`assets/lib/assets/path_policy.ex:56-96`）、データ層でも `ensure_owner/2` が `owner_type` / `owner_id` を照合、既存メタデータの upsert でも owner 一致を要求する（`assets/lib/assets/objects.ex:83-90,120-122`）。BLOB を受けるサービスで最初に壊れる箇所を独立モジュール + 専用テスト（4 件）で固定している。
  > 対象ファイル: `assets/lib/assets/path_policy.ex`, `assets/lib/assets/objects.ex`

- **auth と同型の JWKS 検証と契約の明示** `+3` — **両者**
  > `Assets.Token.Jwks` が 5 分間隔で鍵を更新し、`Verifier` は RS256・iss / aud・`sub` / `jti` の UUID 形式・`status == "active"`・`exp` を検証する（`assets/lib/assets/token/jwks.ex:98-121`, `verifier.ex:3-6,48-74`）。「revocation DB は参照しない」を moduledoc に明記し、engine 側 `AuthVerifier` と同じ契約を独立実装で守っている。テスト用の静的 JWK により外部 auth なしでテストが回る。
  > 対象ファイル: `assets/lib/assets/token/verifier.ex`

- **単一コミットで Docker Compose / CI / release / README まで揃えた MVP** `+4` — **両者**（Opus +2 / GPT +4）
  > Postgres 16 + healthcheck 付き compose（`assets/docker-compose.yml:2-49`）、auth と同一構成の CI（`assets/.github/workflows/ci.yml:1-55`）、3 ステージ Dockerfile（`assets/Dockerfile:5-69`）、責務表とアーキテクチャ図を含む README。骨格コミットの時点で運用形態まで決めておく進め方は、後から足すより安い。
  > 対象ファイル: `assets/docker-compose.yml`, `assets/README.md`

- **サイズ上限と HTTP ステータスの一貫した対応** `+2` — **両者**
  > `max_object_bytes`（既定 1 MiB、環境変数で上書き可）を超えたら `{:error, :too_large}` を返し、コントローラが 413 に変換する（`assets/lib/assets/objects.ex:20-22`, `object_controller.ex:110-114`）。ドメインのエラー原子と HTTP ステータスの対応が 1 箇所で閉じている。
  > 対象ファイル: `assets/lib/assets/objects.ex`

**assets 小計: +13**（Opus +10 / GPT +16）

---

## engine — apps/core

- **FormulaGraph コンパイラ + バイトコード契約** `+8`（2 項目合算） — **両者**
  > ノードグラフを Kahn のトポロジカルソートで評価順に並べ、レジスタ 64 本の制約下でバイトコードへ落とす（`apps/core/lib/core/formula_graph.ex:139,198-200`）。OpCode 0–13 を Elixir 側（`formula.ex:13-20`）と Rust 側（`rust/nif/src/formula/opcode.rs:7-36`）で同じ番号・同じ意味に固定し、言語境界を「バイト列 1 本」に絞っている。標準入力として `dt` / `timer` を推奨する規約まで moduledoc にある。
  > 対象ファイル: `engine/apps/core/lib/core/formula_graph.ex`, `engine/apps/core/lib/core/formula.ex`

- **`Core.Component` ビヘイビア（7 コールバックすべて optional）** `+3` — **両者**
  > 必要なコールバックだけ実装すればよい設計を `@optional_callbacks` で型として表現し（`apps/core/lib/core/component.ex:54-70`）、context に注入されるフィールドとシーン遷移クロージャを moduledoc で列挙する（`:20-33`）。コンポーネントの粒度を小さく保てる。
  > 対象ファイル: `engine/apps/core/lib/core/component.ex`

- **`FormulaStore` の 3 スコープ + MFA ブロードキャスト** `+3` — **両者**
  > `:synced` / `:local` / `:context` で「どこまで共有される値か」を型として表し（`apps/core/lib/core/formula_store.ex:5-8`）、同期は config 注入の MFA 経由で network に投げる。core が network を知らずに分散同期できる。
  > 対象ファイル: `engine/apps/core/lib/core/formula_store.ex`

- **権威 tick の設定化（許容値ホワイトリスト + fail-fast）** `+2` — **両者**
  > `tick_hz` は `[10, 20, 30, 60]` のホワイトリスト検証を通り `tick_ms` / `dt` に展開されてコンテンツへ注入される（`apps/core/lib/core/config.ex:12-13,32-40`）。任意の数値を受けずに列挙で縛り、コンテンツ未設定時は `raise` する（`:15-18`）。
  > 対象ファイル: `engine/apps/core/lib/core/config.ex`

- **`RoomSupervisor` + `Registry` によるルーム分離** `+2` — **両者**
  > `DynamicSupervisor` + `Registry`（`keys: :unique`）でルームを分離し、`start_room/1` は既存ルームに `{:error, :already_started}`、`stop_room/1` は `Core.FrameCache.delete/1` まで面倒を見る（`apps/core/lib/core/room_supervisor.ex:15-45`）。ルーム停止時に付随 ETS を掃除する規律はリソースリークを構造で防ぐ。
  > **採用判断**: Opus は初稿で +3 に加点したが、シーン状態が単一 `Contents.Scenes.Stack` に集約されたままである（マイナス -4）ことを踏まえ **+2** に戻した。
  > 対象ファイル: `engine/apps/core/lib/core/room_supervisor.ex`

- **`FrameCache` のエンジン語彙化 + `StressMonitor` の独立プロセス + `EventBus` の monitor** `+5`（3 項目合算） — **両者**
  > `FrameCache` はルーム別 ETS（`read_concurrency: true`）で必須キーは `:physics_ms` のみ、`:label` / `:counters` / `:meta` は任意という契約に整理された（`apps/core/lib/core/frame_cache.ex:5-7,16,56-57,66-69`）。`StressMonitor` は 1 秒間隔で `physics_ms > tick_ms` を判定する監視を独立 GenServer に置き「クラッシュしてもゲームは継続」と設計意図を moduledoc に書く（`stress_monitor.ex:3-5,65-67`）。`EventBus` は購読者を monitor して購読表から外す（`event_bus.ex:11-17`）。
  > 対象ファイル: `engine/apps/core/lib/core/frame_cache.ex`, `engine/apps/core/lib/core/stress_monitor.ex`

**core 小計: +23**（Opus +23 / GPT +23、完全一致）

---

## engine — apps/contents

- **バックプレッシャー設計（メールボックス深度 + 副作用の切り分け）** `+4` — **両者**
  > メールボックス長が `max(tick_hz * 2, 120)` を超えたら throttled と判定し（`apps/contents/lib/events/game.ex:329-331`）、Zenoh publish や診断キャッシュ更新を落としつつゲーム状態の更新は続ける（`:348-349,428-430`）。「落としてよい副作用」と「落としてはいけない権威更新」を設計として分けているのが要点で、単にフレームをスキップする実装より一段上である。
  > 対象ファイル: `engine/apps/contents/lib/events/game.ex`

- **コンテンツ差し替えアーキテクチャ（5 実装で実証）+ ContentBehaviour の契約設計** `+6`（2 項目合算） — **両者**
  > `CanvasTest` / `BulletHell3D` / `FormulaTest` / `Tetris` / `SampleOsc` の 5 実装が同じビヘイビアを満たし `config :server, :current` の 1 行で入れ替わる（`apps/contents/lib/contents.ex:8-13`）。必須 12 / optional 18 のコールバックが明確に分かれており（`behaviour/content.ex:18-86,197-216`）、「最低限これだけ書けばコンテンツになる」境界が型で読める。2D パズル・3D 弾幕・OSC 連携・UI デバッグという性質の違う 5 例で成立させているのは実証として強い。
  > 対象ファイル: `engine/apps/contents/lib/contents.ex`, `engine/apps/contents/lib/behaviour/content.ex`

- **`FrameEncoder` による protobuf 描画パイプライン** `+3` — **両者**
  > DrawCommand 11 種の protobuf 変換を種別ごとに 11 ファイルへ分割している（`frame_encoder.ex:17-22,61-71`, `frame_encoder/draw_commands/`）。1 つの巨大 case にせず、コマンド追加時の変更範囲を 1 ファイルに閉じ込めている。
  > 対象ファイル: `engine/apps/contents/lib/contents/frame_encoder.ex`

- **Zenoh publish の MFA 注入 + 契約テスト** `+3` — **両者**
  > 直呼びしていた箇所が config の MFA を `apply/3` する形になり lib 内の直接呼び出しは 0 件（`config/config.exs:104-108`, `game.ex:534-538`）。`FrameBroadcaster` による段階的有効化と `zenoh_frame_publish_mfa_test.exs` による契約固定が添えられている。
  > 対象ファイル: `engine/apps/contents/lib/events/game.ex`

- **dt ベースのゲームロジック** `+2` — **両者**
  > `dt = tick_ms / 1000.0` を context に注入し（`game.ex:575-581`）、各コンテンツが `speed * dt` で移動を計算する（`bullet_hell_3d/playing.ex:298-305`, `canvas_test/playing.ex:136,151-153`）。tick_hz を 10 / 20 / 30 に変えてもゲーム速度が変わらない（Tetris のみ例外でマイナス計上）。
  > 対象ファイル: `engine/apps/contents/lib/contents/bullet_hell_3d/playing.ex`

- **BulletHell3D / Tetris の完結したゲームループ** `+4` — **GPT**
  > Tetris は title / play / game over / retry と 3D 盤面・UI までを持ち（`apps/contents/lib/contents/tetris/frame.ex:28-155`）、BulletHell3D も入力・進行・終了・再開が成立する。Opus は「完結しているのは Tetris のみ」としてゲームプレイ側で減点したが、GPT の再検証により BulletHell3D も game over → retry 経路を持つことが確認された。**エンジンのデモとして 2 本の完結ループが動くこと自体はプラスに数えるのが妥当**と判断し採用する。
  > 対象ファイル: `engine/apps/contents/lib/contents/tetris/frame.ex`

- **シーンスタック API + Nodes 型体系 + LocalUser 入力統合 + パラメータ外部化** `+3`（4 項目合算） — **両者**
  > `push_scene` / `pop_scene` / `replace_scene` の 3 操作で遷移を表し解釈は 1 箇所に集約（`scenes/stack.ex:46-56`, `game.ex:616-640`）。`Contents.Behaviour.Nodes` 実装が 20 モジュールで揃い、3 経路の入力が `{:move_input, ...}` / `{:ui_action, ...}` に正規化される。ゲーム定数はシーンモジュール先頭の `@` 属性に並ぶ（`bullet_hell_3d/playing.ex:50-55`, `tetris/playing.ex:7-13`）。
  > 対象ファイル: `engine/apps/contents/lib/scenes/stack.ex`

**contents 小計: +25**（Opus +29 / GPT +21）

---

## engine — apps/network

- **3 トランスポートの統一メッセージ収束** `+4` — **両者**
  > Phoenix Channels / UDP / Zenoh の 3 経路が `Core.RoomRegistry.get_loop` 経由の `send(pid, {:move_input, ...})` / `{:ui_action, ...}` に収束する（`channel.ex:122-124`, `zenoh_bridge.ex:249-251`）。Zenoh は `:zenoh_enabled` で起動制御され、経路の増減が supervision tree で表現される（`application.ex:43-48`）。トランスポートを 3 つ持ちながらゲーム側の入力インターフェースが 1 つに保たれている。
  > 対象ファイル: `engine/apps/network/lib/network/zenoh_bridge.ex`

- **認証・UDP 防御の vertical slice（JWKS → RoomToken → transport 検証 → inflate 上限 → session timeout）** `+4` — **両者**（Opus は個別計上 / GPT +4）
  > JWKS を TTL 10 分でキャッシュし `alg` は RS256 のみ許容、clock skew ±60 秒、claims は iss / aud / exp / iat / `sub`（UUID）/ `jti`（UUID）/ `status` を検証する（`auth_verifier.ex:5-9,18-19,174-176,195-212`）。zlib は展開後 64KB 上限をチャンク累積で強制し境界テスト付き（`udp/protocol.ex:49-50,242-261`, `network_udp_test.exs:247-251`）。セッションは 30 秒 timeout / 5 秒 sweep / PING で延長（`config.exs:37-40`, `udp/server.ex:278-285,365-380`）。一連が 1 本の経路として通っている。
  > 対象ファイル: `engine/apps/network/lib/network/auth_verifier.ex`, `engine/apps/network/lib/network/udp/protocol.ex`

- **OTP ルーム隔離の実証テスト + protobuf 契約テスト** `+6`（2 項目合算） — **両者**
  > ルーム間クラッシュ分離をテストで実証し（`test/network_local_test.exs`, `network_distributed_test.exs`）、Elixir が生成した `RenderFrame` バイト列を golden fixture として Rust 側と共有する。CI の `proto-verify` ジョブが生成物の乖離も検出する（`.github/workflows/ci.yml:84-89`）。network は 9 テストファイル・102 ケースで umbrella 中最も厚い（180 件中 102 件）。
  > 対象ファイル: `engine/apps/network/test/`, `engine/.github/workflows/ci.yml`

- **UDP プロトコルの明示的定義 + WebSocket の常時 RoomToken 必須** `+5`（2 項目合算） — **両者**
  > `<<type::8, seq::32, payload::binary>>` と 9 種のパケット型を 1 モジュールに定義し、`room_id` は 64 バイト上限・NUL 禁止（`udp/protocol.ex:9-47,140,196-197`）。WebSocket 経路は `AUTH_REQUIRED` の値にかかわらず常に RoomToken を要求する（`room_auth.ex:8`, `channel.ex:75`）。ブラウザから届く経路だけ常時必須という線引きは合理的である。
  > 対象ファイル: `engine/apps/network/lib/network/udp/protocol.ex`, `engine/apps/network/lib/network/channel.ex`

- **S2S read-only（自己記述 + 署名付き worlds カタログ）** `+2` — **両者**
  > `GET /.well-known/alchemy-s2s.json` と、RS256 署名・TTL 300 秒・purpose `s2s.worlds.read` を持つ `GET /api/s2s/worlds`（`s2s/instance.ex:1-16`, `catalog.ex:21-31`, `router.ex:32-92`）。連合の本体は未着手だが「まず自己記述と署名付きカタログ」という順序は堅実で、テストも 15KB 分ある。
  > 対象ファイル: `engine/apps/network/lib/network/s2s/instance.ex`

- **`Distributed` の単一ノードフォールバック** `+2` — **両者**
  > 単一ノード時は `Network.Local` に委譲して RPC を回避し、異ノード間の `connect_rooms` は `{:error, :rooms_on_different_nodes}` を明示的に返す（`distributed.ex:8-9,136-138,175-176`）。分散化していない状態を特別扱いせずに素直に速くしている。
  > 対象ファイル: `engine/apps/network/lib/network/distributed.ex`

- **`ZenohBridge` の入力側 DoS 防御** `+3` — **両者**
  > 受信ペイロードのサイズ・形式チェックと不正入力の破棄（`zenoh_bridge.ex:196-236,289-310`）。外部から任意のバイト列が届く経路として妥当な防御を持つ。
  > 対象ファイル: `engine/apps/network/lib/network/zenoh_bridge.ex`

**network 小計: +26**（Opus +31 / GPT +26）

---

## engine — apps/server

- **起動シーケンスの fail-fast** `+2` — **両者**
  > 「content 設定の確認 → children 起動 → `:main` ルーム起動」の順で、content 未設定と `:main` 起動失敗の双方で `raise` する（`apps/server/lib/server/application.ex:11-13,37-41`）。children の並び順にも意図があり、`Core.FrameCache` をルームより先に起動して ETS 所有者をアプリ寿命に固定するコメントが添えられている（`:20-31`）。「起動したが実は何も動いていない」状態を作らない。
  > 対象ファイル: `engine/apps/server/lib/server/application.ex`

- **薄いエントリポイントと依存集約** `+2` — **両者**
  > 2 モジュール 41 行で責務は「設定の読み取りと supervision tree の宣言」だけ。umbrella の依存もこのアプリだけが core / contents / network の 3 つを見る形で、依存の向きが 1 箇所に集約されている（`apps/server/mix.exs:25-30`）。
  > 対象ファイル: `engine/apps/server/mix.exs`

**server 小計: +4**（両者一致）

---

## engine — rust/nif（Formula VM）

- **panic しないエラー境界設計（2 層）** `+4` — **両者**
  > NIF 層の異常は `rustler::Error::Term`、VM のドメインエラーは `{:error, reason_atom, detail}` タプル（`formula_nif.rs:4-5,39-50,183-225`）。`VmError` は 6 種（`vm.rs:9-16`）。ユーザー作成コンテンツを実行する VM で BEAM を落とさない境界を型として敷いている（ただし境界の一貫性にはマイナス -2 を計上）。
  > 対象ファイル: `engine/rust/nif/src/nif/formula_nif.rs`

- **decode の全域バウンドチェック + saturating 算術** `+5`（2 項目合算） — **両者**
  > `DecodeError` に `UnexpectedEof` / `InvalidOpCode` / `RegisterOutOfRange` / `InvalidUtf8` を持ち、レジスタ番号は `REGISTER_COUNT = 64` に対して検証される（`decode.rs:26,29-34`）。整数演算は saturating でオーバーフロー panic の経路を作らない（`vm.rs:123-148`）。
  > 対象ファイル: `engine/rust/nif/src/formula/decode.rs`

- **Formula 実バグの修正と型昇格ルールの明文化** `+3` — **両者**（Opus +2 / GPT +4）
  > 加減乗は両辺 `I32` のとき `I32`、それ以外は `F32` に昇格、除算は `I32/I32` のみ整数除算で `checked_div` により `i32::MIN / -1` を `i32::MAX` に丸める（`vm.rs:123-167`）。`eq` は `F32` のみ EPSILON 比較（`:180-196`）。前回指摘の float 除算バグが修正され 6 件の `#[test]` で境界が固定された。**指摘に対して「直す + テストで固定する」の両方をやっている**。
  > 対象ファイル: `engine/rust/nif/src/formula/vm.rs`

**rust/nif 小計: +12**（Opus +13 / GPT +12）

---

## engine — rust/client

- **golden E2E protobuf 契約テスト** `+4` — **両者**
  > Elixir が生成した実バイト列を Rust 側でデコードし、commands 3 件 / mesh_definitions 1 件 / ui.nodes 1 件 / `cursor_grab == Some(true)` まで検証する（`rust/client/network/tests/render_frame_e2e_contract.rs:14-98`）。`render_frame_proto` 側は truncated / garbage の拒否も見る。言語を跨ぐワイヤ契約を実バイト列で固定する最も確実な方法を選んでおり、golden の SSoT がどちら側かもコメントで明示されている。
  > 対象ファイル: `engine/rust/client/network/tests/render_frame_e2e_contract.rs`

- **`auth_client` の資格情報管理（OS ネイティブストア + refresh のみ永続）** `+4` — **両者**
  > refresh token のみを Windows Credential Manager / macOS Keychain / Linux Secret Service に保存し、access token はメモリのみ（`auth_client/src/token_store.rs:6-10,22,42-52`）。保存・削除はバックグラウンドで UI をブロックせず、HTTP は rustls・タイムアウト 10 秒・リダイレクト無効（`api.rs:16,53-57`）。自前の平文ファイル保存で済ませていない。
  > 対象ファイル: `engine/rust/client/auth_client/src/token_store.rs`

- **Zenoh の publisher キャッシュ + 指数バックオフ再接続** `+4` — **両者**
  > key ごとに publisher を宣言してキャッシュし（Default / Drop congestion の 2 系統、`platform/desktop.rs:27-31,213-248`）、put 中は state ロックを持たない（`:211`）。切断時は 500ms → ×2 → 最大 8s のバックオフで再接続し `reconnect_gate` で多重実行を防ぎ subscriber も再購読する（`:19-21,279-331`）。subscriber は `RingChannel::new(1)` で最新のみ保持、リモートは `tcp/` → `udp/` に書き換えて bufferbloat を避ける（判定に 5 件の `#[test]`）。
  > 対象ファイル: `engine/rust/client/network/src/platform/desktop.rs`

- **クレート分離とセキュリティ境界** `+4` — **両者**
  > `rust/client` の 10 クレート（`rust/nif` を含めてワークスペース計 11）の依存方向が意図どおりに整っている。`render_frame_proto` は wgpu / winit / egui に依存しないデコード専用（`render_frame_proto/Cargo.toml:7-10`）、イベントループ所有は `window`、描画は `render`、資格情報は `auth_client` に閉じて Zenoh を通らない。「どのクレートを読めば何がわかるか」がクレート境界で表現されている（`network` → `render` / `audio` 依存はマイナス計上）。
  > 対象ファイル: `engine/rust/Cargo.toml`

- **3D バッファ戦略 + 2D インスタンシング + コンテンツ WGSL 注入** `+6`（2 項目合算） — **両者**
  > バッファを事前確保して `write_buffer` で上書きし容量を定数で明示（`MAX_GRID_VERTS = 404` / `MAX_MESH_VERTS = 24_000` / `MAX_MESH_INDICES = 100_000`、`pipeline_3d/mod.rs:28-36`）。2D は `SpriteInstance` で `MAX_INSTANCES = 14510` を確保し 1 回の `draw_indexed` で描く（`renderer/mod.rs:99-104,588-596`）。シェーダーは外部注入で `app` が `assets/shaders/*.wgsl` を読み込む（`render/src/window.rs:12-14`, `app/src/main.rs:124-137`）。
  > 対象ファイル: `engine/rust/client/render/src/renderer/pipeline_3d/mod.rs`

- **`AssetLoader` のパストラバーサル防御 + オーディオのグレースフルフォールバック** `+6`（2 項目合算） — **両者**
  > 相対パス検証（`assets/` プレフィックス強制・親ディレクトリ拒否）と拒否ログ（`audio/src/asset/mod.rs:152-158`）に専用テスト 2 件。`AudioCommand` 8 種を `mpsc` で専用スレッドに送り、デバイスが開けなくてもハンドルは返して warn を出しコマンドを捨てる（`audio/src/audio.rs:19-25,69-85,122-136`）。「音が出ない環境でゲームが起動しない」を構造的に防いでいる。
  > 対象ファイル: `engine/rust/client/audio/src/asset/mod.rs`, `engine/rust/client/audio/src/audio.rs`

- **ヘッドレスレンダラー + フレームホールド + audio cue 再送防止 + `unsafe` 最小化** `+6`（3 項目合算） — **両者**
  > feature `headless` でオフスクリーン wgpu → PNG を出力でき、スプライト構築ロジックは通常経路と共有（`render/src/headless.rs:1-16,394-398`）。フレーム未着時は直前を保持し SE キューは `take_pending_audio()` で 1 回だけ取り出す（`interp.rs:574-576`, `network_render_bridge.rs:198-205`）。`unsafe` は OpenXR API 由来の 2 箇所のみで理由コメント付き（`xr/src/openxr_loop.rs:18,64-66`）。
  > 対象ファイル: `engine/rust/client/render/src/headless.rs`, `engine/rust/client/xr/src/openxr_loop.rs`

- **`system_ui` の状態機械テスト + `window` のイベント正規化** `+4`（2 項目合算） — **両者**
  > クライアント所有の UI（ログイン・登録・メニュー）に 16 件の `#[test]`（`state.rs` 9 / `validation.rs` 7）。`window` は `KeyCode` + `ElementState` を正規化し、`Escape` はクライアント消費、`Focused(false)` でカーソル解放、`MouseMotion` はグラブ中のみ転送、system_ui 表示中はゲーム入力を遮断する（`window/src/desktop_loop.rs:156-198`）。「どの入力をサーバに送らないか」を層の責務として決めている。
  > 対象ファイル: `engine/rust/client/system_ui/src/state.rs`, `engine/rust/client/window/src/desktop_loop.rs`

- **`SurfaceError` 回復 + OpenXR 入力ループの実装前進** `+2`（2 項目合算） — **Opus**
  > サーフェス喪失時の再構成経路があり、`openxr_loop.rs` はセッション状態機械・action set・pose / ボタンの `XrInputEvent` 化まで書かれた 296 行になった（`xr/src/openxr_loop.rs:14-259`）。`openxr` を optional feature にして既定ビルドを汚さない配慮もある（未配線はマイナス -4 に計上）。
  > 対象ファイル: `engine/rust/client/xr/src/openxr_loop.rs`

（`SnapshotInterpolator` +5 は「最上位」節に計上済み）

**rust/client 小計: +45**（Opus +45 / GPT +37。上記 +5 を含む）

---

## 横断評価層

- **`mix alchemy.ci` によるローカル CI 単一エントリ** `+4` — **両者**
  > Rust fmt / clippy / test と Elixir deps / format / credo / test を 1 コマンドで通し、`check` / `rust` / `elixir` の部分実行も持つ（`apps/core/lib/mix/tasks/alchemy.ci.ex:2-4,57-145`）。両評価者が独立に `8f35a57` で実行し、**ALL PASSED**（exit 0、それぞれ 23 秒 / 21 秒）を確認した。周辺の mix タスクも 11 個揃い、「開発者が覚えるコマンドは mix だけ」という状態を作っている。
  > 対象ファイル: `engine/apps/core/lib/mix/tasks/alchemy.ci.ex`

- **`proto-verify` CI ジョブ + バージョンピン + 複合アクション** `+6`（3 項目合算） — **両者**
  > proto から再生成し `mix format` を通してから `git diff --exit-code` で差分を検出する（`.github/workflows/ci.yml:84-89`）。`protoc-gen-elixir` は 0.16.0 にピン留めされ理由もコメントされている（`:79-82`）。5 ジョブが共通の複合アクション `./.github/actions/alchemy-ci-setup` を使い、バージョンは `env` 1 箇所、`concurrency` で同一 ref をキャンセルする（`:8-14,25-28`）。
  > 対象ファイル: `engine/.github/workflows/ci.yml`

- **moduledoc の文書化品質と誠実さ** `+3` — **両者**
  > 「なぜそうしたか」「今どこまでか」が書かれている。`Core.FrameCache` の「core は contents 語彙を持たない」（`frame_cache.ex:5-7`）、`Network.RoomAuth` の「AUTH_REQUIRED オフ時は無検証」（`room_auth.ex:5-8`）、`platform/web.rs` の未実装明示、`predict.rs` の「network 連携後に追加予定」。未完成を未完成と書く姿勢は、評価者にとってもコード読者にとっても信頼できる情報源になっている（`Core.Component` の 60Hz 記述はこの原則からの逸脱としてマイナス計上）。
  > 対象ファイル: `engine/apps/core/lib/core/frame_cache.ex`

- **エラー契約の一貫性 + 構造化ログ** `+5`（2 項目合算） — **両者**
  > Elixir 側 `{:ok, _}` / `{:error, reason}`、Rust 側 `Result` と `{:error, atom, detail}` の対応が層をまたいで揺れない。ログとイベント名も `auth.token_cleanup.completed` / `[:game, _]` / `[:auth, :rate_limit, :throttle]` と階層が揃っている。3 リポジトリにまたがってもエラーとログの表現が予測できる。
  > 対象ファイル: `engine/rust/nif/src/nif/formula_nif.rs`, `auth/lib/auth/token_cleanup.ex`

- **テストの意図的設計** `+3` — **両者**
  > 網羅率ではなく「守りたい設計」に向けて書かれている。`refute Map.has_key?(summary, :kills_by_enemy)` で core にゲーム語彙が戻らないことを固定（`stats_test.exs:28`）、`zenoh_frame_publish_mfa_test.exs` で MFA 注入の契約を固定、`game_multi_room_tick_test.exs:24-31` で非 `:main` ルームの tick を固定。リファクタの成果をテストで凍結する運用ができている。
  > 対象ファイル: `engine/apps/core/test/core/stats_test.exs`

- **`workspace/` のレーン運用 + 自己評価サイクルの制度化** `+4`（2 項目合算） — **両者**
  > `1_backlog` → `2_todo` → `3_Inprogress` → `4_human_review` → `6_merging` → `7_done` と差し戻し経路を定義し、「各タスクは 1 ディレクトリのみ」を明文化（`workspace/README.md:9-28`）。`7_done` 30 件 / `1_backlog` 25 件が実際に積まれ形骸化していない。評価は観点・基準・出力先・アーカイブ規約をルール化し（`.cursor/rules/evaluation.mdc`）、今回から第1・第2評価者の独立二重評価に拡張された。
  > 対象ファイル: `engine/workspace/README.md`, `engine/.cursor/rules/evaluation.mdc`

- **ワイヤ正本の submodule 化 + 技術的負債の少なさ** `+4`（2 項目合算） — **両者**
  > protobuf 定義を `3rdparty/alchemy-protocol/proto` に外出しし Elixir・Rust 双方がそこから生成する（`ci.yml:84-89`, `rust/client/network/build.rs:57-75`）。「どちらが正か」問題を置き場所で解決している。削除した機能（GameWorld / SoA 物理）も legacy 文書として履歴を残し現行文書と命名で分離している（`docs/architecture/legacy_*`）。
  > 対象ファイル: `engine/3rdparty/alchemy-protocol/`, `engine/docs/architecture/`

**横断 小計: +29**（Opus +29 / GPT +17）

---

## ゲームプレイ完成度

- **3 種のデモが別々のエンジン機能の生きた検証になっている** `+4` — **GPT**（Opus は contents 側に含めて計上）
  > CanvasTest がワールド空間 UI、FormulaTest がノードグラフ → バイトコード → NIF の全経路、SampleOsc が Resonite 互換 OSC 受信を、それぞれ「動かして確かめられる形」で保持している。機能ごとに使い捨てのテストハーネスを書くのではなく、コンテンツとして常設し `config :server, :current` の 1 行で切り替えられる状態にしているため、リグレッションが手元で即座に見える。GPT はこの分類を独立させて +12 と採点した。
  > **採用判断**: GPT の +12 のうち「Tetris / BulletHell3D の完結したループ」は contents 側 +4、「5 実装によるコンテンツ交換可能性の実証」は contents 側 +6 と重複する。二重計上を避け、重複しない部分（3 デモが個別機能の常設検証になっている点）に絞って **+4** を採用する。
  > 対象ファイル: `engine/apps/contents/lib/contents/canvas_test.ex`, `engine/apps/contents/lib/contents/formula_test.ex`, `engine/apps/contents/lib/contents/sample_osc.ex`

**ゲームプレイ 小計: +4**（Opus は独立計上せず / GPT +12。差は上記の二重計上排除による）

---

## 総計

| 大分類 | 採用 | Opus | GPT |
|:---|:---:|:---:|:---:|
| プロジェクト全体（アーキテクチャ） | **+12** | +12 | +0 |
| auth | **+48** | +61 | +47 |
| assets | **+13** | +10 | +16 |
| engine — apps/core | **+23** | +23 | +23 |
| engine — apps/contents | **+25** | +29 | +21 |
| engine — apps/network | **+26** | +31 | +26 |
| engine — apps/server | **+4** | +4 | +4 |
| engine — rust/nif | **+12** | +13 | +12 |
| engine — rust/client | **+45** | +45 | +37 |
| 横断評価層 | **+29** | +29 | +17 |
| ゲームプレイ完成度 | **+4** | —（contents に含む） | +12 |
| **プラス合計** | **+241** | **+257** | **+215** |

「最上位」節の 2 項目（`SnapshotInterpolator` +5、auth の暗号・トークン設計 +5）は、それぞれ rust/client と auth の小計に含めて計上している。

### 評価者間の一致度

プラス側は**方向がほぼ完全に一致した**。両者が独立に最高評価（+5）を与えたのは `SnapshotInterpolator` と auth の暗号・トークン設計で、+4 帯（golden 契約テスト、`auth_client` の資格情報管理、Zenoh 再接続、クレート分離、バックプレッシャー、3 トランスポート収束、`mix alchemy.ci`、Argon2id、多軸レート制限、アカウントライフサイクル）も大半が共通している。core と server は小計まで一致した。

主な差は 2 点。第 1 に**分類の置き方**で、Opus は「プロジェクト全体（アーキテクチャ）」に +12 を計上し、GPT は同じ内容を各アプリへ分散した。第 2 に**ゲームプレイの扱い**で、GPT は独立分類として +12 を与え、Opus は contents の一部として +3 に留めた。この 2 点で約 +20 の差が出ており、それ以外はほぼ重なっている。

つまり「何が良いか」については 2 人の評価者がほぼ同じ絵を見ており、意見が分かれるのは「何が足りないか」の重み付けである（マイナス点文書参照）。
