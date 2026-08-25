# Opus 評価 — マイナス点詳細一覧

評価日: 2026-08-25 / 評価者: Claude Opus 5（第1評価者）
対象: `engine/`（umbrella 4 アプリ + `rust/nif` + `rust/client` 10 クレート）+ `auth/`（認証サービス）+ `assets/`（アセット・永続化サービス、今回から評価対象）
検証対象コミット: engine `8f35a57`（main = PR #347 マージ、作業ツリークリーン）
前回評価: Fable 5 / 2026-07-31（`docs/evaluation/fable/archive/2026-07-31/`）— マイナス 48 項目 / -96 点

本版は前回マイナス 48 項目すべてを対象ファイルの再読で検証し、`elixir -S mix alchemy.ci` を main で実行した結果を反映した再評価である。

> **CI 関連項目の再検証（2026-08-25）**: 初稿は `9da2712` 時点で書き、品質保証の 3 項目（GitHub CI 無効化 -4 / ローカル CI 失敗 -3 / warranty ドキュメント陳腐化 -2）を計上していた。その後 `988b9e1`（PR #347「fmt/clippy/credo を直し CI を再有効化する」）が入り、`.github/workflows/ci.yml.ignore` が `ci.yml` に戻され、fmt / clippy / format / credo の指摘箇所も修正された。現 HEAD `8f35a57` で `elixir -S mix alchemy.ci` を再実行した結果は **ALL PASSED**（exit 0、20 秒）。これに伴い「ローカル CI が main で失敗する」（-3）と「新規追加コードが fmt / clippy を通っていない」（-2）を撤回し、「GitHub Actions CI が無効化されている」（-4）は **CI 無効化の再発パターン（-1）** へ緩和した。`docs/warranty/ci.md` の陳腐化（-2）は現 HEAD でも未修正のため維持する。

## 採点基準

| 点数 | 基準 |
|:---:|:---|
| -1 | 改善余地あり。動作はするが設計・品質上の軽微な問題 |
| -2 | 重要な機能・設計の欠如。放置すると将来の拡張を阻害する |
| -3 | 設計上の明確な欠陥。バグ・クラッシュ・性能劣化を引き起こしうる |
| -4 | プロジェクトの価値命題を損なう重大な欠如。説明責任が果たせない |
| -5 | プロジェクトの根幹を揺るがす致命的な欠陥。存在しないに等しい |

上限・下限なし。同一観点内で複数項目を合算する。

---

## プロジェクト全体（アーキテクチャ）

### 連合・認証の到達点

- **フル連合（ActivityPub / WebFinger / identity federation）は未実装** `-2`（前回 -4 から緩和）
  > 前回「実装ゼロ」と指摘した連合層は、read-only S2S として第一歩が着地した（`Network.S2S.Instance` / `Catalog` / `Client`、`GET /.well-known/alchemy-s2s.json`）。一方で ActivityPub / WebFinger / インスタンス間 identity federation は依然ソース上ゼロで、`apps/` を `activitypub|webfinger` で検索してもエラーメッセージ文字列以外にヒットしない。S2S 自体も `config :network, Network.S2S, enabled: false` が既定（`config.exs:66-67`）で、訪問トークン・アバター持ち出しといった「連合の本体」は未着手。「分散連合型 VRSNS」の看板に対する到達度は「メタデータ交換の入口ができた」段階である。改善方針: `.well-known` の自己記述と RSA 鍵基盤は既にあるので、次は訪問トークン（他インスタンスの JWKS でゲスト入場を検証）を最小実装し、S2S を既定オンにできる状態まで運びたい。
  > 対象ファイル: `engine/config/config.exs`, `engine/apps/network/lib/network/s2s/instance.ex`

- **auth ↔ engine 認証が既定オフ** `-1`（前回 -3 から緩和）
  > `Network.AuthVerifier` による JWKS 取得 + RS256 検証が実装され Supervisor 配下で稼働し（`application.ex:55`）、`POST /api/room_token` も Bearer 必須化パスを持つ（`router.ex:138-152`）。配線自体は完成している。ただし `config :network, :auth_required, false`（`config.exs:57`）が既定であり、素の状態では前回と同じく誰でも room token を取得できる。デモ互換という理由はコメントに明記されており意図的だが、「既定が安全側でない」設定は運用者が一手忘れた瞬間に穴になる。改善方針: `:prod` の既定を `true` にし、明示的に `AUTH_REQUIRED=false` と書いた場合だけ無認証を許す（`runtime.exs` に既に fail-fast の作りがあるので反転は容易）。
  > 対象ファイル: `engine/config/config.exs`, `engine/config/runtime.exs`

### 永続化

- **engine 側の永続化配線が未着手** `-1`（前回 -2 から緩和）
  > 保存先サービスは `alchemy-assets`（リポジトリルートの `assets/`）として実在するようになった（後述の assets 節参照）。しかし engine 側は変わっておらず、`"__save__"` / `"__load__"` は依然「local persistence disabled; network TBD」のログを出して何もしない（`game.ex:106-111`）。`FormulaStore` の synced スコープも `:formula_store_synced` ETS のみで再起動で消える（`formula_store.ex:35-46`）。したがって「ルームがクラッシュしたら状態が初期化される」「ワールド・アバターを置く場所がない」という帰結は前回と同一である。改善方針: `assets` の `PUT/GET /api/v1/objects/*path` を叩く HTTP クライアントを 1 本書いて `__save__` / `__load__` に繋ぐ。保存パス（`users/{sub}/private/Save/{content_id}/save.{slot}`）と JSON スキーマは assets 側の README が既に定義しているため、決めるべき設計はほぼ残っていない。
  > 対象ファイル: `engine/apps/contents/lib/events/game.ex`, `engine/apps/core/lib/core/formula_store.ex`

**プロジェクト全体マイナス小計: -4**（前回 -9）

---

## auth（認証サービス）

2026-07-31 以降の auth コミットは**ドキュメント 4 件のみ**（`c17c574`, `1bd16f1`, `70a8bb9`, `8f62501`）。`lib/` の変更はゼロで、前回指摘 7 項目はすべて現ソースで存続を確認した。

### 認証フロー

- **ログイン・登録がメール検証を要求しない** `-2`
  > `login/3` はパスワード検証と `user.status == :active` のみを見て `email_verified_at` を参照しない（`accounts.ex:55-68`）。`email_verified_at` を見るのは verify フロー専用の `ensure_user_verifiable/1`（`accounts.ex:489-491`）だけ。さらに register も未検証のまま `issue_session` してアクセストークンを返す。検証メール送信・`AccountToken` の SHA-256 ハッシュ保存・ワンタイム消費と検証フロー自体は丁寧に作られているだけに、そのゲートが認証経路のどこにも効いていないのは設計の抜けである。改善方針: `require_verified_email` を config フラグで導入し、`login/3` と保護エンドポイントで `email_verified_at` を必須にする（既存テストの `user_fixture/1` を検証済みユーザーに変える必要がある）。
  > 対象ファイル: `auth/lib/auth/accounts.ex`

- **最低年齢チェックなし** `-1`
  > `BirthdayInPast` は未来日付の拒否のみで（`birthday_in_past.ex:14-19`）、年齢下限のバリデーションがない。`PasswordComplexity` を含む Ash のカスタムバリデーション基盤は整っているので、COPPA / 各国法令を意識した `MinimumAge` を同じパターンで追加できる。VRSNS として年齢レーティング（`max_content_status: "General"` を S2S で公開する設計まである）を持つなら、入口の年齢確認は必須になる。
  > 対象ファイル: `auth/lib/auth/accounts/validations/birthday_in_past.ex`

### 運用

- **`/health` に DB 疎通チェックなし** `-1`
  > status / service / version を返すのみ（`health_controller.ex:6-12`）。DB 障害時も `ok` を返すため K8s readiness probe としては機能しない。`Ecto.Adapters.SQL.query(Repo, "SELECT 1", [])` を 1 行足すだけで readiness の意味が生まれる。
  > 対象ファイル: `auth/lib/auth_web/controllers/health_controller.ex`

- **`account_tokens` の GC なし** `-1`
  > `TokenCleanup` の対象は `token_revocations` と stale `refresh_tokens` のみ（`token_cleanup.ex:62-68`）。`AccountToken` は `expires_at` / `used_at` を持つのに定期削除の対象外で、検証・リセットメールを送るたびに行が永久に残る。既存の `do_run/0` に 1 クエリ追加すれば済む。
  > 対象ファイル: `auth/lib/auth/token_cleanup.ex`

- **レート制限が単一ノード ETS** `-1`
  > `:auth_rate_limit` の named ETS テーブル（`rate_limit.ex:10,54-60`）。12 バケット・telemetry 連携・定期掃除と実装品質は高いが、auth を水平スケールした瞬間にバケットがノード間で共有されず制限が実質 N 倍に緩む。連合として複数運営者に配る前提なら、Redis 等の共有ストアか `:pg` ベースの集約に移す設計余地を残しておきたい。
  > 対象ファイル: `auth/lib/auth/rate_limit.ex`

- **CORS 未設定** `-1`
  > `auth/` 全体で `Corsica` / `cors_plug` / `CORS` の参照がゼロ。`endpoint.ex:41-52` にも CORS plug がない。Rust の `auth_client` はネイティブ HTTP なので現状問題は出ないが、ブラウザ由来の SPA・管理画面を足す時点でプリフライトが通らない。
  > 対象ファイル: `auth/lib/auth_web/endpoint.ex`

- **Dialyzer / hex.audit なし** `-1`
  > `mix.exs` の deps に `dialyxir` / `mix_audit` がなく（`mix.exs:41-63`）、`precommit` エイリアスも credo + test まで（`mix.exs:87-93`）。CI も format / compile / credo / ecto / test のみ。型検査と依存脆弱性監査は、これだけ認証ロジックを持つサービスでは入れておく価値が高い。
  > 対象ファイル: `auth/mix.exs`, `auth/.github/workflows/ci.yml`

**auth マイナス小計: -8**（前回 -8、変化なし）

---

## assets（アセット・永続化サービス）

前回評価の対象外だった新規サービス。リポジトリルート `assets/` に 2026-08-07 の 1 コミット（`600b985`）で追加され、lib 22 ファイル / テスト 3 ファイル・12 ケース。プラス点は別文書に記載する。

- **engine から呼ばれておらず 18 日間停止している** `-1`
  > Objects CRUD・所有権強制・JWKS 検証・Docker Compose・CI が揃った動くサービスだが、利用者がいない。engine・client の双方に `assets` を呼ぶコードはゼロで、`assets/` 自身も追加コミット以降 18 日間更新がない。README が「含まない（後フェーズ）: engine `__save__` / `__load__` 配線（engine 側 Phase 2–3）」と段階を明示しているため無計画ではないが、サービスを立てた分だけ運用対象（DB・コンテナ・CI）は増えており、価値を生まないまま維持コストだけが乗っている状態である。改善方針: engine 側の配線を 1 本通し、`BulletHell3D` のハイスコアだけでも往復させる。エンドツーエンドが 1 経路通れば、残りは同じ形の反復になる。
  > 対象ファイル: `assets/`, `engine/apps/contents/lib/events/game.ex`

- **書き込みのレート制限・容量クォータがない** `-1`
  > `MAX_OBJECT_BYTES`（既定 1 MiB）による 1 オブジェクトのサイズ上限はあるが、書き込み回数の制限とユーザー単位の総容量クォータがない。`PUT /api/v1/objects/*path` は Bearer 必須なのでアカウントは要るが、1 アカウントでスロットを変えながら 1 MiB を無制限に書き込めばディスクを埋められる。auth 側は 12 バケットの多軸レート制限を持つだけに、BLOB を受けるサービスに何もないのは非対称である。改善方針: auth の `Auth.RateLimit` と同型のプラグ + `AssetMetadata` の `byte_size` 合計に対するクォータチェック。
  > 対象ファイル: `assets/lib/assets_web/controllers/object_controller.ex`, `assets/lib/assets/objects.ex`

- **テスト密度が薄く `/health` も浅い** `-1`
  > lib 22 に対しテスト 3 ファイル・12 ケース。パスポリシー・所有権・CRUD の主要経路は押さえているが、JWKS 取得失敗・kid ローテーション・`MAX_OBJECT_BYTES` 超過（413）・同一パスへの同時書き込みを検証するテストがない。特に JWKS はネットワーク越しの依存で失敗モードが多く、そこが無検証だと auth 障害時の挙動が読めない。`/health` も auth と同様に DB 疎通を見ない（`health_controller.ex`）。改善方針: `test/support/token.ex` で静的 RSA 自己署名の仕組みは既にあるので、失効・kid 不一致・期限切れのケースを足すコストは低い。
  > 対象ファイル: `assets/test/`, `assets/lib/assets/token/jwks.ex`, `assets/lib/assets_web/controllers/health_controller.ex`

**assets マイナス小計: -3**

---

## engine — apps/core

### エンジン語彙の分離

- **`Core.Telemetry` にゲーム固有メトリクスが残存** `-1`（前回 -3 の残渣）
  > `Core.Config` の `@default_content` 撤去（現在は `:server, :current` 必須で raise、`config.ex:15-18`）、`Core.StressMonitor` の `wave_label/1` 呼び出し撤去（現在は `FrameCache` の汎用 `:label` 参照、`stress_monitor.ex:46-63`）、`Core.Stats` の汎用カウンタ化により、前回 -3 とした「core → contents の論理的循環依存」は本体が解消した。残っているのは `Core.Telemetry` のメトリクス定義で、`"game.tick.enemy_count"` / `"game.level_up.count"` / `"game.boss_spawn.count"` という BulletHell 固有の語彙をエンジン層が握っている（`telemetry.ex:25-36`）。改善方針: メトリクス定義もコンテンツ側から宣言して注入する（`Core.Config` / `Component` で既に確立した注入パターンをそのまま適用できる）。
  > 対象ファイル: `engine/apps/core/lib/core/telemetry.ex`

### ドキュメント整合

- **`Core.Component` の moduledoc が撤去済みの 60Hz 物理ループを記述**（新規） `-1`
  > `on_physics_process/1` を「物理フレーム（60Hz）」と説明している（`component.ex:12`）。実際にはゲーム用 60Hz 物理ループは撤去済みで、`Contents.Events.Game` が権威 tick（既定 20Hz）の中で `physics_scenes` に含まれるシーンのときだけ `dispatch_to_components(:on_physics_process, ...)` を呼ぶ（`game.ex:487,500-507`）。README も「サーバー NIF は Formula VM のみ。ゲーム用 60Hz 物理ループはない」と明記している（`README.md:52`）。エンジンの中心ビヘイビアの moduledoc が、プロジェクトが最も強調している設計転換と逆のことを書いている。改善方針: 「物理シーン中のみ権威 tick で呼ばれる」に書き換える。moduledoc の誠実さはこのプロジェクトの強み（プラス +3 で評価している）だからこそ、中心ビヘイビアの記述ずれは影響が大きい。
  > 対象ファイル: `engine/apps/core/lib/core/component.ex`

### テスト容易性

- **`NifBridge.Behaviour` が未配線（モック不能）** `-2`
  > 前回指摘のまま未解決。Behaviour は定義のみで（`nif_bridge_behaviour.ex:1-8`）、`Core.Formula.run/3` は `alias Core.NifBridge` の実 NIF を直呼びする（`formula.ex:22,43`）。moduledoc 自身が「本番は `Core.NifBridge` が直接 NIF を呼ぶ」と書いており、Behaviour が意図的に死んだ抽象になっている。config 注入も Mox もないため、NIF ビルドなしで core のテストが回らない。改善方針: `Application.get_env(:core, :nif_bridge, Core.NifBridge)` の 1 行注入 + `test.exs` での Mox 設定。前回提案した「純 Elixir インタプリタによる differential testing」への足掛かりにもなる。
  > 対象ファイル: `engine/apps/core/lib/core/nif_bridge_behaviour.ex`, `engine/apps/core/lib/core/formula.ex`

※前回指摘のうち以下 4 件は現ソースで解消を確認し、撤回する。
- `FrameCache が単一スナップショット・BulletHell 固有スキーマ`（-2）→ room_id キーの ETS + 必須は `:physics_ms` のみ（`frame_cache.ex:5-7,66-68`）、複数ルームテストあり（`frame_cache_test.exs:24-39`）
- `死にコード・死に設定の残存`（-1）→ `Core.InputHandler` と `config :core, Core.NifBridge, features: []` はともに grep 0 件
- `Core.Stats が旧ゲーム前提`（-1）→ 汎用カウンタ API のみ。`refute Map.has_key?(summary, :kills_by_enemy)` でテストが契約を固定（`stats_test.exs:28`）
- `出荷 tick_hz とコメント・推奨値の矛盾`（-1）→ コメントも実値も `Core.Config` フォールバックもすべて 20（`config.exs:94-96`, `config.ex:12-13`）

**core マイナス小計: -4**（前回 -10）

---

## engine — apps/contents

### マルチルーム

- **シーンスタックが全ルームで共有されている**（新規） `-4`
  > 初稿では「前回 -4 とした『非 `:main` ルームでゲームループが駆動しない』は解消」と判定したが、これは**誤りだった**（第2評価者の指摘を受けて再検証し、自己修正する）。tick が全ルームで回るのは事実である（`game.ex:46,321-324`、テスト `game_multi_room_tick_test.exs:24-31`）。しかしシーン状態の置き場が 1 つしかない。`Server.Application` は `{Contents.Scenes.Stack, [content_module: content]}` を `room_id` なしで起動するため `__MODULE__` 名で単一登録され（`apps/server/lib/server/application.ex:20-31`, `apps/contents/lib/scenes/stack.ex:205-212`）、5 つの Content すべてが `def flow_runner(_room_id), do: Process.whereis(Contents.Scenes.Stack)` と **`room_id` を捨てて**同じ pid を返す（`bullet_hell_3d.ex:52`, `tetris.ex:27`, `canvas_test.ex:36`, `formula_test.ex:30`, `sample_osc.ex:43`）。結果として、2 ルームで同じコンテンツを動かすと HP・スコア・シーン遷移が相互に上書きされる。`Contents.Scenes.Stack` は `room_id` オプションでの名前登録に対応済み（`stack.ex:16,205`）で、`ContentBehaviour` には `scene_stack_spec/1`（`content.ex:130-135`）という optional callback まで用意されているのに、実装している Content が 1 つもない——つまり「マルチルームの器は作られたが中身が入っていない」状態である。OTP プロセス隔離とルーム別 ETS をここまで丁寧に作った上でシーン状態だけがグローバルなのは、マルチルームという価値命題を実質的に無効にする。改善方針: `scene_stack_spec/1` を各 Content が実装して `RoomSupervisor` の子として起動し、`flow_runner/1` を `Process.whereis({Contents.Scenes.Stack, room_id})`（または Registry 経由）に変える。同時に「2 ルームで別々のスコアが保たれる」テストを 1 本置いて、この誤りが再発しないよう固定する。
  > 対象ファイル: `engine/apps/contents/lib/contents/bullet_hell_3d.ex`, `engine/apps/contents/lib/scenes/stack.ex`, `engine/apps/server/lib/server/application.ex`

- **`Helpers` の 1 引数版が `:main` 固定** `-1`（前回 -3 から緩和）
  > `Render` は `context` の `room_id` を使い（`render.ex:28-29`）、`Events.Game` も `state.room_id` 経由に移行した（`game.ex:515`）ため、前回 -3 とした「flow_runner(:main) のハードコード」は主要経路が解消した。残るのは `Contents.Components.Category.Device.Helpers` の 1 引数版で、`with_scene_type/2` と `with_playing_scene/1` が `:main` に委譲する（`helpers.ex:14-15,38-39`）。moduledoc に「room_id 省略時は `:main`（後方互換）」と明記されており把握はされているが、マルチルームループが実際に駆動するようになった今、この既定値は非 `:main` ルームで静かに誤ったルームを触る経路になる。改善方針: 1 引数版を deprecate して呼び出し元を移行し、既定値を削除する。
  > 対象ファイル: `engine/apps/contents/lib/components/category/device/helpers.ex`

### テスト

- **テスト密度が依然低い** `-2`（前回 -3 から緩和）
  > lib 126 ファイルに対しテスト 8 ファイル（6.3%）。追加された 4 ファイル（`game_multi_room_tick_test.exs`、`zenoh_frame_publish_mfa_test.exs`、`osc_test.exs` ほか）はいずれも「今回変えた設計を守る」ための的を射たテストで質は高い。しかし `nodes/`（40+ モジュール）、`objects/`、各 Content の playing ロジック、`FrameEncoder` の DrawCommand 変換は依然無検証で、ゲーム速度の同一性やシーン遷移の回帰を検出する層がない。GitHub CI が復活した（PR #347）ため回帰検出の器は戻ったが、器に入れるテストがない領域はそのまま盲点として残る。改善方針: `FrameEncoder` の DrawCommand → protobuf 変換は入出力が純関数に近く、golden fixture 方式で低コストに面を稼げる。
  > 対象ファイル: `engine/apps/contents/test/`

### 結合

- **contents → network のコンパイル時依存が残存** `-1`（前回 -2 から緩和）
  > Zenoh publish は MFA 注入に移行し（`config.exs:104-108` の `{Network.ZenohBridge, :publish_frame, []}` を `game.ex:534-538` で `apply/3`）、lib 内の `Network.ZenohBridge.publish_frame` 直接呼び出しは 0 件になった。`FrameBroadcaster` による段階的な有効化も丁寧である。ただし `apps/contents/mix.exs:32-34` に `{:network, in_umbrella: true}` が残り、`FrameEncoder` の都合で network がコンパイル時依存のまま。「network が上位」という umbrella の層構造には依然逆行しており、contents 単体でのビルド・テストができない。改善方針: protobuf 生成コードを `network` から切り出して両者が依存する下位アプリに置く。
  > 対象ファイル: `engine/apps/contents/mix.exs`

### 未完成物

- **未実装コンポーネント・死に実装の残存** `-1`
  > `objects/core/` の 4 ファイルが「空間エンジンとの統合後に実装」の TODO スタブのまま（`destroy.ex:16`, `duplicate.ex:19`, `create_empty_parent.ex:18`, `create_empty_child.ex:18`）。`MenuComponent` は実装と `get_menu_ui/2` を持つが、どの Content の `components/0` にも登録されておらず（`bullet_hell_3d.ex:23-28`, `component_list.ex:15-22`）、`get_menu_ui/2` の呼び出し元も lib 内に存在しない。前回指摘から変化なし。改善方針: 統合予定が立っていないなら `workspace/` に設計メモとして退避し、lib からは消す。「動く実装」と「動かない実装」が同じ名前空間に同居している方が読み手のコストが高い。
  > 対象ファイル: `engine/apps/contents/lib/objects/core/`, `engine/apps/contents/lib/components/category/ui/menu_component.ex`

※前回指摘のうち以下 1 件は撤回する。
- `命名の不統一（Content. / Contents.）`（-1）→ ゲームコンテンツ本体を `Content.*`（14 モジュール）、エンジン側インフラ・コンポーネントを `Contents.*`（112 モジュール）とする意図的な分離規約が PR #340 で確立した。混在ではなく規約であるため減点を撤回する（規約の明文化は提案に回す）

※前回指摘の `:main 以外のルームでゲームループが駆動しない`（-4）は、**撤回を取り消す**。tick の駆動は解消したが、シーン状態の共有という別形の同根問題が残っていたため、上記「シーンスタックが全ルームで共有されている」（-4）として計上し直した。

**contents マイナス小計: -9**（前回 -14）

---

## engine — apps/network

### 認証の既定値

- **UDP JOIN の認証が既定オフ** `-1`（前回 -3 から緩和）
  > JOIN パケットは `Network.RoomAuth.verify_join_token/2` を通り、失敗時は `unauthorized` エラーを返す（`udp/server.ex:217-232`）。`AUTH_REQUIRED=true` 時の拒否・許可の統合テストもある（`network_udp_test.exs:283-307`）。機構は正しく入った。残る問題は `required?/0` が false のとき token を無視して常に `:ok` を返す点（`room_auth.ex:18-20,29-35`）で、既定設定（`config.exs:57`）では前回同様に client_id 自己申告で入室できる。プロジェクト全体の指摘と同根で、こちらは経路単位の残渣として計上する。
  > 対象ファイル: `engine/apps/network/lib/network/room_auth.ex`, `engine/apps/network/lib/network/udp/server.ex`

- **Zenoh 経由の入力・入室の認証が既定オフ** `-1`（前回 -2 から緩和）
  > movement / action / client_info のすべてが `RoomAuth.unwrap_payload/2` を通るようになった（`zenoh_bridge.ex:196-211,221-236,289-310`）。ただし同じく既定オフ時は生 protobuf をそのまま受理する（`room_auth.ex:55-56,74-75`）。
  > 対象ファイル: `engine/apps/network/lib/network/zenoh_bridge.ex`, `engine/apps/network/lib/network/room_auth.ex`

- **封筒形式をヒューリスティックで判別している**（新規） `-1`
  > `unwrap_payload/2` は `<<len::16-big, token::binary-size(len), rest::binary>>` にマッチした後、トークン検証が失敗しかつ `AUTH_REQUIRED` オフの場合、`(reason in [:expired, :scope_mismatch] or len > 30) and looks_like_token?(token)` という条件で「封筒だったのか生 protobuf だったのか」を推測する（`room_auth.ex:60-78`）。PR #347 の credo 対応で `unwrap_wrapped/5` に切り出され `@max_token_bytes 1000` の上限も入ったが、推測そのものは残っている。`looks_like_token?/1` は Base64URL 文字種の正規表現でしかなく（`room_auth.ex:93-95`）、protobuf の先頭 2 バイトが妥当な `len` に化けて後続が偶然その文字種に収まれば、ペイロードの先頭が黙って切り落とされる。ワイヤ形式の SSoT を「経路・形式ごとに定める」と自ら掲げているプロジェクトで、ワイヤの解釈を確率的な推測に委ねているのは原則違反である。改善方針: 封筒の先頭にマジックバイト + バージョンを置く、あるいは Zenoh のキー式（トピック）で封筒あり／なしを分ける。どちらも後方互換を保ったまま推測を消せる。
  > 対象ファイル: `engine/apps/network/lib/network/room_auth.ex`

### DoS 耐性

- **UDP に生パケットサイズ・セッション数・送信頻度の上限がない**（新規） `-2`
  > zlib 展開上限（64KB）は入ったが、その前段の防御が抜けている。ソケットは `active: true` で任意サイズのパケットを受けて処理し（`udp/server.ex:186-197`）、JOIN はセッション数の上限なしに sessions マップを増やし、登録済みセッションからの INPUT / ACTION には seq 検証もレート制限もない（`udp/server.ex:240-275`）。`:action` の name も長さ上限なしで decode する（`protocol.ex:165-166`）。UDP は送信元詐称が容易なため、zip bomb を潰した後に残った素朴な flood がそのまま増幅面になる。改善方針: パケット長の上限チェック（現行ペイロード最大の 2 倍程度）、セッション数上限、セッション単位のトークンバケット。既に `session_timeout_ms` の管理構造があるので、同じ sessions マップに送信カウンタを持たせるだけで足りる。
  > 対象ファイル: `engine/apps/network/lib/network/udp/server.ex`, `engine/apps/network/lib/network/udp/protocol.ex`

- **`GET /health` がルーム ID 一覧を公開している**（新規） `-1`
  > レスポンスに `room_ids` をそのまま含める（`router.ex:95-104`。PR #347 で `cond` → `case` に整形されたが公開項目は不変）。ヘルスチェックは通常無認証で外部公開するため、稼働中のワールド名が偵察できてしまう。S2S の `worlds` カタログは公開を意図した設計だが、health は別物である。改善方針: 件数（`rooms`）のみを返し、一覧が必要なら S2S / 管理エンドポイント側に置く。
  > 対象ファイル: `engine/apps/network/lib/network/router.ex`

### 分散・信頼性

- **Elixir 側 `ZenohBridge` に再接続がない**（新規） `-3`
  > Rust クライアント側には指数バックオフ再接続と再購読が入った（プラス点 +4 で評価）一方、サーバ側は `init/1` で `Zenohex.Session.declare_subscriber/3` を 3 本（movement / action / client_info）宣言したあと、セッションの死活を監視する仕組みが一切ない（`zenoh_bridge.ex:60-65`）。`handle_info/2` に `:DOWN` の処理も再宣言もなく（`:142,168-169`）、未知メッセージは debug ログに落ちるだけである。したがって zenohd が再起動した場合、クライアントは再接続するのにサーバは購読を失ったまま生き続け、入力が届かないルームが静かに残る。片側だけ回復する非対称は、両方落ちるより発見が遅れる種類の障害である。第2評価者はこれを -4 とした（本評価では、Supervisor 配下なのでプロセス自体は監視されており `:zenoh_enabled` が既定オフである点を考慮して -3 とする）。改善方針: セッションを `Process.monitor` し、`:DOWN` でバックオフ再接続して 3 本の subscriber を再宣言する。Rust 側の `reconnect_with_backoff`（`platform/desktop.rs:279-331`）が設計の雛形になる。
  > 対象ファイル: `engine/apps/network/lib/network/zenoh_bridge.ex`

- **`find_room_node` の全ノード RPC スキャン** `-2`
  > 前回指摘のまま未解決。ルーム所在解決は毎回 `cluster_nodes()` への `:rpc` 逐次スキャンで（`distributed.ex:239-246`）、コード内コメント自身が「将来は `:global` レジストリや永続的な配置テーブルでキャッシュする余地あり」と認めている。`list_rooms_clustered/0` も同様（`distributed.ex:205-217`）。「1000 人規模」を掲げるなら、ノード数 × 呼び出し頻度に線形劣化する経路は先に潰しておきたい。改善方針: `:pg` でルーム → ノードのグループを張るか、`Registry` の分散版に相当する配置テーブルを 1 つ持つ。
  > 対象ファイル: `engine/apps/network/lib/network/distributed.ex`

- **UDP に断片化・再送・順序制御がない** `-1`
  > 前回指摘のまま未解決。`seq` はヘッダに存在しサーバ送信 FRAME で発行される（`udp/server.ex:332-334`）が、受信側の INPUT / ACTION で検証されない。FRAME は zlib 圧縮ペイロードを単一パケットに載せるのみで、MTU 超過時の分割も再送もない（`protocol.ex:113-117,169-173`）。現行の描画量では顕在化しないが、3D シーンが育つと静かに壊れる。改善方針: 提案に挙げた QUIC datagram / WebTransport の採用を先に検討する方が、信頼性層を自作するより費用対効果が高い。
  > 対象ファイル: `engine/apps/network/lib/network/udp/protocol.ex`

※前回指摘のうち以下 3 件は現ソースで解消を確認し、撤回する。
- `zlib 展開の無制限化`（-3）→ `@max_uncompressed_frame_bytes 64 * 1024` + チャンク累積で上限を超えたら `:error` を返す `safe_inflate_limited/4`（`protocol.ex:49-50,242-261`）、64KB+1 のテストあり（`network_udp_test.exs:247-251`）
- `engine の SECRET_KEY_BASE に fail-fast がない`（-3）→ `config_env() == :prod` かつ未設定/空で raise（`runtime.exs:32-42`）
- `UDP セッションの無期限成長`（-2）→ `session_timeout_ms: 30_000` / `sweep_interval_ms: 5_000`（`config.exs:37-40`）+ `:sweep_sessions` による淘汰 + PING での `touch_session`（`udp/server.ex:61-63,202-205,278-285,365-380`）、タイムアウトと延長のテストあり（`network_udp_test.exs:422-485`）

**network マイナス小計: -12**（前回 -16）

---

## engine — apps/server

- **テストが 0 件** `-1`
  > `apps/server/test/` ディレクトリが依然存在しない。lib は `server.ex` と `application.ex` の 2 ファイル 41 行で、`:main` ルーム起動失敗時に raise する fail-fast の起動シーケンス（プラス点として評価している箇所）そのものが無検証。改善方針: Supervisor ツリーが起動して `:main` ルームが Registry に登録されるところまでを見る smoke test 1 本。`workspace/0_reference/improvement-plan.md` の D-4 に同じ項目が挙がっており、今回も未着手のまま。
  > 対象ファイル: `engine/apps/server/`

- **リリース定義の不在** `-1`
  > ルート `mix.exs:4-10` と `apps/server/mix.exs:4-15` の双方に `releases:` がなく、サーバの配布・デーモン化手段が `mix run --no-halt` のみ。auth と assets の 2 サービスは `mix release` + Dockerfile を持つだけに、engine だけが取り残されている。連合として他運営者にサーバを立ててもらう構想があるなら、配布形態がないことは構想の前提を欠く。改善方針: `releases:` 定義 + systemd unit / コンテナイメージ。`auth/Dockerfile` と `assets/Dockerfile` がそのまま雛形になる。
  > 対象ファイル: `engine/mix.exs`, `engine/apps/server/mix.exs`

**server マイナス小計: -2**（前回 -2、変化なし）

---

## engine — rust/nif（Formula VM）

- **Rust 側テストが除算に偏っている** `-1`（前回 -3 から緩和）
  > `#[test]` が 0 件だった状態から 6 件に増え、`cargo test -p nif` で実際に 6 passed を確認した。ただし 6 件すべてが `binary_div` 関連（`vm.rs:198-307`）で、`decode_bytecode` の境界条件（途中終端・未知 opcode・レジスタ範囲外・名前の UTF-8 不正）や他の算術命令の型昇格を Rust 側で検出する層は依然ゼロ。これらは Elixir 統合テスト（`formula_test.exs`、10 テスト）でカバーされているが、NIF ビルドを伴う遅い経路にしか防壁がない状態である。改善方針: `decode.rs` の `ensure_len` 系分岐に対する `#[test]` は入力バイト列を直書きするだけで書けるので、面を稼ぐコストが低い。
  > 対象ファイル: `engine/rust/nif/src/formula/decode.rs`, `engine/rust/nif/src/formula/vm.rs`

- **命令数・入力サイズの上限なし / DirtyCpu 未指定** `-1`
  > 前回指摘のまま未解決。`decode_bytecode` は `while pos < bytecode.len()` で EOF まで無制限に命令を積み（`decode.rs:53-170`）、`run_formula_bytecode` は `#[rustler::nif]` のみで `schedule = "DirtyCpu"` を指定していない（`formula_nif.rs:26-27`）。ユーザー作成コンテンツを実行する VM としては、巨大バイトコード 1 本で BEAM の通常スケジューラを専有できる。改善方針: `MAX_INSTRUCTIONS` 定数 + 実行ステップ上限（gas 方式）と `DirtyCpu` 指定。制御フロー命令を追加する前に入れておくべき順番である。
  > 対象ファイル: `engine/rust/nif/src/formula/decode.rs`, `engine/rust/nif/src/nif/formula_nif.rs`

※前回指摘のうち以下 2 件は現ソースで解消を確認し、撤回する。
- `binary_div の float 除算が整数除算に化けるバグ`（-3）→ `binary_div` が I32/I32 のみ整数除算に分岐し、それ以外は `binary_op_f32` へ（`vm.rs:151-167`）。`as_i32()` による型誤判定を避ける理由がコメントに明記され、`div_f32_returns_float` テストで `5.0 / 2.0 → F32(2.5)` を固定（`vm.rs:228-242`）
- `i32::MIN / -1 のパニック経路`（-2）→ `va.checked_div(vb).unwrap_or(i32::MAX)`（`vm.rs:158-159`）+ `div_i32_min_by_neg_one_does_not_panic` テスト（`vm.rs:273-283`）

なお前回の `Rust 単体テストがゼロ`（-3）は 0 件 → 6 件になったため撤回ではなく、上記「除算に偏っている」（-1）として緩和扱いで計上している（撤回と緩和で二重に数えない）。

**rust/nif マイナス小計: -2**（前回 -9）

---

## engine — rust/client

### 価値命題の配線

- **クライアント側予測が未配線** `-2`（前回 -4 の分割）
  > 補間は完全に配線された（プラス点参照）ため、前回 -4 の主要部分は解消した。残るのは予測で、`predict_input` は「スケルトン」「入力をそのまま返す」という実装のまま（`predict.rs:8-12`）、参照は `lib.rs` の re-export のみ。権威 tick が 20Hz、補間の遅延バッファが 80〜250ms である以上、自機の移動には最小でも 100ms 超の体感遅延が乗る。補間が入ったことで「カクつき」は消えたが「重さ」は残っており、VR では特に効く。改善方針: 自分の移動入力のみローカル即時反映 + サーバ照合。入力に `seq` が既にあるので、サーバ側の ack 付与だけで土台が揃う。
  > 対象ファイル: `engine/rust/client/shared/src/predict.rs`

- **OpenXR が app に未配線・ランタイム限定** `-3`（前回 -4 から緩和）
  > `openxr_loop.rs` は 331 行の実装になり、セッション状態機械（READY / STOPPING）・action set・`simple_controller` バインディング・head/controller pose とボタンの `XrInputEvent` 化まで書かれている（`openxr_loop.rs:14-255`。PR #347 の fmt 適用で 336 行から 331 行になった）。前回の「TODO で即 `Err`」からは明確に前進した。しかし VR が動作しないという結論は変わらない。理由は 3 つある。(1) `app/src/main.rs` に `xr` クレートへの参照が一切なく（`main.rs:16-21` の use 一覧に不在）、デスクトップクライアントから XR ループが起動されない。(2) `xr/Cargo.toml:7-9` で `default = []`、`openxr` は optional のため既定ビルドに含まれない。(3) `XR_MND_headless` を必須とし未対応ランタイムでは即 `Err`（`openxr_loop.rs:23-27`）で、Monado 系に事実上限定される。加えて headless（入力専用）なのでステレオ描画・スワップチェーンはない。改善方針: まず app への配線と feature の既定化を行い、`XR_MND_headless` 非対応時は入力なしで継続するフォールバックを入れる。「動く経路が 1 本ある」状態にしないと、実装量が増えても価値命題は動かない。
  > 対象ファイル: `engine/rust/client/xr/src/openxr_loop.rs`, `engine/rust/client/xr/Cargo.toml`, `engine/rust/client/app/src/main.rs`

### 品質基盤

- **クライアント Rust テストが CI で実行されない** `-3`
  > 前回指摘のまま未解決で、CI 復活後もここは変わっていない。`mix alchemy.ci` の Rust テストは `cargo test -p nif` のみ（`alchemy.ci.ex:99-106`）で、復活した `ci.yml:50-51` の `rust-test` ジョブも `cargo test --manifest-path rust/Cargo.toml -p nif` のまま。実際にはクライアント側に 52 件の `#[test]` が存在する（shared 18 / system_ui 16 / auth_client 8 / network 6 / audio 2 / render_frame_proto 2、現 HEAD で再計測）。今回追加された `SnapshotInterpolator` の 18 テストは補間ロジックの品質を担保する中核なのに、その 1 件も回帰検出に使われていない。良いテストを書きながら使っていない状態が 3 週間以上続いている。CI が緑になった今、この 1 行を変えないままだと「緑」の意味が実際より広く読まれてしまう。改善方針: `-p nif` を `--workspace` に変える 1 行。`openxr` は optional feature なのでデフォルト feature のままなら CI 時間も大きく増えない。
  > 対象ファイル: `engine/apps/core/lib/mix/tasks/alchemy.ci.ex`, `engine/.github/workflows/ci.yml`

- **render クレートのテストが 0 件** `-2`
  > 前回指摘のまま未解決。2650 行・client 最大規模のクレート（3D/2D パイプライン・カメラ・テキスト）に `#[test]` が 1 件もなく `tests/` もない。`headless.rs` に PNG 出力機能がありながら golden image 回帰は未整備。golden 契約テストは network 側の protobuf デコード（`render_frame_e2e_contract.rs`）でピクセル比較ではない。改善方針: 提案に挙げた headless golden image 回帰。既存の PNG 出力にハッシュ比較を足すだけで最初の 1 本が書ける。
  > 対象ファイル: `engine/rust/client/render/`

### 未実装・性能

- **WASM プラットフォームが未実装スタブ** `-2`
  > 前回指摘のまま未解決。`platform/web.rs:1-29` は全メソッドが「Zenoh WebSocket (WASM) は未実装」を返し、`spawn_subscriber` は空スレッド。クレート構成が示唆するブラウザ対応は現状も虚像。改善方針: 当面やらないなら `cfg` で切って web.rs を消し、ロードマップ側に置く。「あるように見えて動かない」コードはクレート構成の読み手を誤らせる。
  > 対象ファイル: `engine/rust/client/network/src/platform/web.rs`

- **`RenderFrame` の毎フレーム clone（補間で増加）** `-1`
  > 前回指摘のまま未解決で、補間導入により経路が増えた。`sample()` は毎回 `f.clone()` または `interpolate_render_frame` で新規 `RenderFrame` を生成し（`interp.rs:588,592,596,607,615`）、ブリッジ側も `guard.sample(now).unwrap_or_default()` で所有権コピーを受ける（`network_render_bridge.rs:206`）。`commands` / `mesh_definitions` / `ui` を含む構造体を 60fps でフル複製している。client 全体で `Arc<RenderFrame>` の使用は 0 件。3D シーンの DrawCommand が増えるほど効く。改善方針: `RenderBridge::next_frame` の戻り値を `Arc<RenderFrame>` にし、補間結果のみ新規確保する。
  > 対象ファイル: `engine/rust/client/shared/src/interp.rs`, `engine/rust/client/network/src/network_render_bridge.rs`

- **カリング・SE ボイス上限なし** `-1`
  > 前回指摘のまま未解決。GPU バックフェイスカリング（`pipeline_3d/mod.rs:269`）のみで、フラスタム・距離カリングのロジックは render クレートに存在しない。SE は `play_se_with_volume` が呼び出しごとに `Sink::connect_new` + `detach()` するため同時再生数の上限がない（`audio.rs:54-61`）。弾幕系コンテンツで被弾が連続した際にミキサ上の Sink が際限なく増える。改善方針: SE 側はボイスプール + 優先度で上限を切るのが定石。カリングは DrawCommand をサーバが生成している構造上、クライアント側だけでなくサーバ側の視錐台判定でも効かせられる。
  > 対象ファイル: `engine/rust/client/render/`, `engine/rust/client/audio/src/audio.rs`

※前回指摘のうち以下 2 件は現ソースで解消を確認し、撤回する。
- `Zenoh publisher を put ごとに宣言`（-3）→ key ごとの publisher キャッシュ（Default / Drop の 2 系統 + generation 管理）で初回のみ declare（`platform/desktop.rs:27-31,204-245`）
- `Zenoh 切断からの再接続なし`（-2）→ `reconnect_with_backoff`（初期 500ms、×2、最大 8s）+ subscriber 切断時の resubscribe（`platform/desktop.rs:19-21,107-114,142-152,279-330`）

※本評価の初稿（`9da2712` 時点）で新規計上した以下 1 件は、現 HEAD で解消を確認し撤回する。
- `新規追加コードが fmt / clippy を通っていない`（-2）→ `9da2712` では `cargo fmt --check` が `xr/src/openxr_loop.rs` の 4 箇所、`cargo clippy --workspace -- -D warnings` が `shared/src/interp.rs:348,349,373` で失敗していたが、`988b9e1` で両ファイルが修正され（`interp.rs` 12 行 / `openxr_loop.rs` 18 行）、現 HEAD の `mix alchemy.ci` で `[PASS] cargo fmt` / `[PASS] cargo clippy` を確認した。なお `rustfmt.toml` / `rust-toolchain.toml` は依然不在で、ツールチェーン固定による将来の偽陽性回避は未着手のまま（提案側に回す）

**rust/client マイナス小計: -14**（前回 -22）

---

## 横断評価層

### 品質保証

- **CI 無効化・再有効化の反復がプロセスとして定着している**（新規） `-1`（初稿 -4「GitHub Actions CI が無効化されている」から緩和）
  > 現 HEAD `8f35a57` では `.github/workflows/ci.yml` が実在し（`988b9e1` で `ci.yml.ignore` から rename）、`mix alchemy.ci` も ALL PASSED である。したがって初稿の「防壁が存在しない」という指摘は解消した。残る問題は再発パターンそのものである。`git log --follow -- .github/workflows/ci.yml` は `ci ignore`（`1e73f60`, `daf332d`, `e624ad4`, `35bcc93`, `c4680ae`, `7b1b27f`）と `CI を有効化する` / `re-enable CI workflow`（`988b9e1`, `40d2053`, `97e5e64`）の往復を数か月にわたり繰り返しており、「赤くなったら拡張子で無効化する → 後でまとめて直す」が事実上の運用になっている。今回の無効化期間は PR #326〜#345 の 20 本という、プロジェクト史上最大規模の改修期間と重なった。回帰検出なしでセキュリティ層・ネットコード・マルチルームループを同時に書き換えたことになる（結果として `mix test` 自体は当時も PASS しており実害は出ていないが、それは事後的に判明したことである）。加えて `ci.yml` を無効化しても README・`docs/warranty/ci.md` の記述は追随しないため、無効化中は看板が事実と正反対になる。前回評価（Fable 2026-07-31）が PR #322 の「CI 再有効化」を +1 加点した直後に再び ignore 化されていたのは、評価者を含む読み手が存在しない防壁を前提に判断させられた実例である。現状が緑である以上減点は -1 に留めるが、再発を防ぐ制度的な仕掛けは依然ゼロである。改善方針: (1) main への push / PR を必須チェックにする branch protection、(2) 無効化する場合は `ci.yml` を消さず `continue-on-error: true` で可視化を維持する、(3) それでも無効化するなら README と `ci.md` を同じコミットで直し、再有効化の条件をワークフロー内に書き残す。なお `auth/` と `assets/` は一度も無効化されていない。
  > 対象ファイル: `engine/.github/workflows/ci.yml`, `engine/README.md`, `engine/docs/warranty/ci.md`

- **`docs/warranty/ci.md` が削除済みクレートと実在しない設定値を記述**（新規） `-2`
  > 品質保証を説明する文書自体が最も陳腐化しており、CI が復活した現 HEAD でも未修正のまま残っている。(1) `ci.md:10,13` は CI ジョブとして `cargo test -p physics` と `cargo bench -p physics`（前回比 +10% 超でブロック）を掲載するが、physics クレートは撤去済みで存在せず、復活した `ci.yml:50-51` の定義は `cargo test -p nif` のみで bench ジョブは存在しない。`README.md:95` の「main のみ `cargo bench` のリグレッション検知」も同様に事実でない（`README.md:89` の「すべての push で GitHub Actions が自動実行されます」は CI 復活により再び事実になった）。(2) `ci.md:46` は `CyclomaticComplexity` を「本プロジェクト **15**」と書くが `.credo.exs:9` は `max_complexity: 10`。初稿時点の credo 失敗は複雑度 11〜12 によるもので、文書どおりの設定なら通っていた（PR #347 はコードを分割して 10 以下に収める方向で直しており、対処は正しいが文書は依然 15 のまま）。(3) `ci.md:48` は `AliasUsage` を「3 回以上に緩和」と書くが実際は `{Credo.Check.Design.AliasUsage, false}` で完全無効。(4) `ci.md:54-55` は `UnlessWithElse` / `WithClauses` を「無効化している」と書くが `.credo.exs` に該当設定はなく、逆に文書化されていない `{Credo.Check.Design.TagTODO, false}` がある。ドキュメント品質は本プロジェクトの強み（moduledoc の誠実さは +3 で評価している）だからこそ、warranty 配下がこの状態なのは目立つ。改善方針: `ci.md` の表を `.credo.exs` と `ci.yml` から生成するか、少なくとも CI 変更時に同時更新する対象として明記する。
  > 対象ファイル: `engine/docs/warranty/ci.md`, `engine/.credo.exs`, `engine/README.md`

### テスト戦略

- **プロパティベース・fuzz・ベンチマークが全体に不在** `-2`
  > 前回指摘のまま未解決。`engine/mix.lock` / `engine/rust/Cargo.lock` / `auth/mix.exs` のいずれにも StreamData / benchee / proptest / criterion がなく、`engine/rust/**/benches/` は 0 ファイル、`#[bench]` も 0 件。バイトコード VM（Formula）・バイナリプロトコル（UDP）・グラフコンパイラ（FormulaGraph）・スナップショット補間という「ランダム入力と時間軸に晒される層」を 4 つ持つ構成に対して、example-based テストのみは防御が薄い。特に `SnapshotInterpolator` は 18 テストが充実している一方、到着時刻・順序・欠落の組み合わせ空間は example では覆いきれない性質のもので、proptest が最も効く対象である。改善方針: まず `interp.rs` に proptest を 1 本（任意の到着列に対して `sample()` が panic せず、出力時刻が単調である）。次に Formula の graph → VM roundtrip。
  > 対象ファイル: `engine/mix.lock`, `engine/rust/Cargo.lock`, `auth/mix.exs`

### 可観測性

- **可観測性の実装が定義と乖離** `-2`
  > 前回指摘のまま未解決。engine 全体の `:telemetry.execute` は 3 箇所のみ（`[:game, :session_end]`、`[:game, :tick]`、`[:game, :frame_dropped]`）。`Core.Telemetry` は `Telemetry.Metrics.ConsoleReporter` どまりで（`telemetry.ex:12-14`）、LiveDashboard も外部エクスポートもない（LiveDashboard は auth の dev_routes のみ）。この 3.5 週間で新規に入った層（JWKS 検証、S2S peer 取得、UDP セッション淘汰、Zenoh 再接続、補間の遅延適応）はいずれも運用時に「今どうなっているか」を知りたい対象なのに、telemetry イベントが 1 つも追加されていない。特に補間の適応遅延（80〜250ms を EMA で追従）は、ユーザーが「重い」と言ったときに実測値がないと切り分け不能である。改善方針: 新規層に `:telemetry.execute` を足し、ConsoleReporter を PromEx に差し替える。イベント名の設計は既存 3 件の `[:game, _]` 形式を踏襲すればよい。
  > 対象ファイル: `engine/apps/core/lib/core/telemetry.ex`

### ゲームプレイ完成度

- **「遊べるゲーム」としての完成度がエンジンのデモ水準にとどまる**（新規） `-2`
  > Content 5 種のうち、開始 → プレイ → 終了 → リトライの全経路が閉じているのは `Content.Tetris` のみ。開発既定に近い `BulletHell3D` はタイトル画面がなく起動即プレイで、敵種は 1 種（Cone、単色 `@color_enemy`）、プレイヤーの攻撃手段が存在せず（敵弾を避けるだけ）、ステージは単一アリーナで時間経過による難度スケールのみ。`CanvasTest` / `FormulaTest` / `SampleOsc` はデバッグ・検証用である。アセットは `engine/assets/audio/` に bgm.wav / hit.wav / death.wav 等 6 ファイルと `sprites/atlas.png` が同梱されているが、`vampire_survivor/` と `mini_shooter/` は `.gitkeep` のみで、`BulletHell3D` はプロシージャルメッシュ描画（`assets_path: ""`）のため BGM をコンテンツ側から配信していない。設定 UI もない。「コンテンツ交換可能性の実証」という目的には 5 例で足りている（プラス側で +3 として評価した）が、「遊べるゲームとしての完成度」の観点では、外部の人に渡して 10 分遊べる状態には達していない。エンジンの土台の精度と、その上に載っている遊びの量の差が、このプロジェクトで最も目立つ非対称である。改善方針: 既定コンテンツを Tetris にして「完結したループが既定で体験できる」状態にするだけでも初見の印象は変わる。パラメータ外部化と dt ベース化は済んでいるので、敵種・武器種の追加は設計上の障害がなく純粋な物量の問題である。
  > 対象ファイル: `engine/apps/contents/lib/contents/bullet_hell_3d/`, `engine/assets/`

### セキュリティ・配布

- **依存の脆弱性監査がない** `-1`
  > 前回指摘のまま未解決。`cargo audit` / `mix hex.audit` は復活した `ci.yml` の 5 ジョブにも `mix.exs` の aliases にも組み込まれておらず、`dependabot.yml` はリポジトリ全体で 0 件。zenoh / wgpu / rustls / Ash と、更新の速い依存を多数抱える構成である。改善方針: `mix.exs` の alias に `hex.audit` を足すのは 1 行。`cargo-audit` は `ci.yml` に 1 ジョブ追加すれば済み、CI が動いている今が最も入れやすい。
  > 対象ファイル: `engine/.github/`, `auth/.github/workflows/ci.yml`, `assets/.github/workflows/ci.yml`

- **CI が ubuntu のみ・クライアント配布手段なし** `-1`
  > 前回指摘のまま未解決。CI が復活した結果、この項目は初めて実効を持つ形で残った。`ci.yml` の 5 ジョブすべてが `runs-on: ubuntu-latest` の単一 OS。クライアントは Windows/macOS を明示サポートする分岐（`platform/` による OS 別実装、Windows Credential Manager / Keychain / Secret Service）を持ち、`mix alchemy.router` は Windows と Unix で listen アドレスを分けているのに、その分岐が CI で一度も検証されない。インストーラ（MSIX / notarized dmg）・自動更新も未着手で、ランチャーは別リポジトリに分離された。改善方針: `rust-check` / `rust-test` に `strategy.matrix.os` で windows-latest を 1 つ足す。少なくとも `cargo check` だけでも回せば OS 別分岐のコンパイル破綻は防げる。
  > 対象ファイル: `engine/.github/workflows/ci.yml`

**横断マイナス小計: -11**（前回 -6）

---

## 総計

| 大分類 | マイナス小計 | 前回（Fable 2026-07-31） | 差分 |
|:---|:---:|:---:|:---:|
| プロジェクト全体（アーキテクチャ） | -4 | -9 | **+5** |
| auth | -8 | -8 | — |
| assets（新規対象） | -3 | — | **-3** |
| engine — apps/core | -4 | -10 | **+6** |
| engine — apps/contents | -9 | -14 | **+5** |
| engine — apps/network | -12 | -16 | **+4** |
| engine — apps/server | -2 | -2 | — |
| engine — rust/nif | -2 | -9 | **+7** |
| engine — rust/client | -14 | -22 | **+8** |
| 横断評価層 | -11 | -6 | **-5** |
| **マイナス合計** | **-69** | **-96** | **+27** |

指摘項目数: 47 件（前回 48 件）。内訳は新規 10 件と前回由来 37 件（緩和 12 / 維持 25、うち auth 7 件は `lib/` 変更ゼロのため全件存続）。前回 48 件のうち 11 件を撤回した。

技術評価層は core / nif / rust/client で大きく改善し、横断評価層も PR #347 の CI 再有効化により -17（初稿）から -11 に戻した。一方 contents（-9）と network（-12）は初稿より悪化している。理由は、第2評価者（GPT-5.6 Sol）が指摘した 2 点を自分で対象ファイルを再検証した結果、**初稿の判定が誤りだったと認めた**ためである。

| 自己修正した項目 | 初稿 | 修正後 | 誤りの内容 |
|:---|:---:|:---:|:---|
| シーンスタックが全ルームで共有 | 撤回（-4 → 0） | **-4** | tick の全ルーム駆動をもって「マルチルーム解消」と判定したが、シーン状態の置き場が単一 GenServer のままだった |
| Elixir 側 Zenoh 再接続なし | 未計上 | **-3** | Rust クライアント側の再接続実装（+4）を評価した際、サーバ側に同等の回復がないことを見落とした |

残る横断の主因は 3 つ、warranty ドキュメントの陳腐化（-2）、これまで採点していなかったゲームプレイ完成度（-2）、プロパティベース・fuzz・ベンチマークの不在（-2）である。

### 初稿（`9da2712` 時点）からの変更

| 項目 | 初稿 | 現 HEAD `8f35a57` | 根拠 |
|:---|:---:|:---:|:---|
| GitHub Actions CI が無効化されている | -4 | **-1**（再発パターンとして残置） | `988b9e1` で `ci.yml.ignore` → `ci.yml` に rename |
| ローカル CI が main で失敗する | -3 | **撤回** | `mix alchemy.ci` = ALL PASSED（exit 0、20 秒） |
| 新規追加コードが fmt / clippy を通っていない | -2 | **撤回** | `interp.rs` / `openxr_loop.rs` を `988b9e1` で修正、fmt / clippy とも PASS |
| `Core.Component` moduledoc の 60Hz 記述 | — | **-1**（新規） | `component.ex:12` と `game.ex:487,500-507` / `README.md:52` の乖離 |
| シーンスタックが全ルームで共有 | 撤回 | **-4**（自己修正） | `flow_runner(_room_id)` が全 Content で `Process.whereis(Contents.Scenes.Stack)` |
| Elixir 側 Zenoh 再接続なし | — | **-3**（自己修正） | `zenoh_bridge.ex:60-65` に監視・再宣言がない |
| **マイナス合計** | **-69** | **-69** | ±0 |
