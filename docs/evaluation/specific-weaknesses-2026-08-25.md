# マイナス点 統合一覧 — 2026-08-25

評価日: 2026-08-25
検証対象コミット: engine `8f35a57`（PR #347 マージ後、作業ツリークリーン）
統合元:
- 第1評価者（Claude Opus 5）: `opus/opus-specific-weaknesses-2026-08-25.md`（47 項目 / **-69**）
- 第2評価者（GPT-5.6 Sol）: `gpt/gpt-specific-weaknesses-2026-08-25.md`（44 項目 / **-119**）

両評価者は互いの当日文書を参照せずに独立して採点した。本文書は両者の指摘を突き合わせ、**採用点**を決めたものである。出典は **両者**（独立に同じ欠陥へ到達）／**Opus**／**GPT** で示す。両者が到達した項目は、優先度の高い信号として扱う。

## 採点基準

| 点数 | 基準 |
|:---:|:---|
| -1 | 改善余地あり。動作はするが設計・品質上の軽微な問題 |
| -2 | 重要な機能・設計の欠如。放置すると将来の拡張を阻害する |
| -3 | 設計上の明確な欠陥。バグ・クラッシュ・性能劣化を引き起こしうる |
| -4 | プロジェクトの価値命題を損なう重大な欠如。説明責任が果たせない |
| -5 | プロジェクトの根幹を揺るがす致命的な欠陥。存在しないに等しい |

---

## 最重要 — 両評価者が独立に到達した欠陥

この 6 件は、互いの文書を読んでいない 2 人が同じ結論に達したものである。最優先で対処すべき集合と考える。

### マルチルーム

- **シーンスタックが全ルームで共有されている** `-4` — **両者**（Opus -4 / GPT -5）
  > `Server.Application` は `Contents.Scenes.Stack` を `room_id` なしで単一起動し（`apps/server/lib/server/application.ex:20-31`, `apps/contents/lib/scenes/stack.ex:205-212`）、5 つの Content すべてが `def flow_runner(_room_id), do: Process.whereis(Contents.Scenes.Stack)` と `room_id` を捨てて同じ pid を返す（`bullet_hell_3d.ex:52`, `tetris.ex:27`, `canvas_test.ex:36`, `formula_test.ex:30`, `sample_osc.ex:43`）。tick 自体は全ルームで回る（`game.ex:46,321-324`、テスト `game_multi_room_tick_test.exs:24-31`）ため「マルチルーム対応済み」に見えるが、2 ルームで同じコンテンツを動かせば HP・スコア・シーン遷移が相互に上書きされる。`Stack` は `room_id` 付き登録に対応済みで（`stack.ex:16,205`）、`ContentBehaviour` には `scene_stack_spec/1` という optional callback まで用意されている（`content.ex:130-135`）のに、実装した Content が 1 つもない。
  > **採用判断**: GPT は -5、Opus は -4。器（room_id 付き登録・`scene_stack_spec/1`）が既に存在し欠けているのは配線とテストのみであるため、「存在しないに等しい」ではなく **-4** を採用する。なお Opus は初稿でこの項目を「解消」と誤判定しており、GPT の指摘を受けて対象ファイルを再検証して自己修正した。独立二重評価が機能した実例である。
  > 対象ファイル: `engine/apps/contents/lib/contents/bullet_hell_3d.ex`, `engine/apps/contents/lib/scenes/stack.ex`, `engine/apps/server/lib/server/application.ex`

### ネットワーク

- **Elixir 側 `ZenohBridge` に再接続がない** `-3` — **両者**（Opus -3 / GPT -4）
  > `init/1` で movement / action / client_info の subscriber を 3 本宣言したあと、セッションの死活監視が存在しない（`apps/network/lib/network/zenoh_bridge.ex:60-65`）。`handle_info/2` に `:DOWN` 処理も再宣言もなく、未知メッセージは debug ログに落ちるだけである（`:142,168-169`）。Rust クライアント側には指数バックオフ再接続と再購読が入った（プラス点で評価）ため、**zenohd 再起動時にクライアントだけが復帰してサーバは購読を失ったまま生き続ける**。片側だけ回復する非対称は、両方落ちるより発見が遅れる。
  > **採用判断**: `:zenoh_enabled` が既定オフでプロセス自体は Supervisor 配下という緩和要因を考慮し、Opus の **-3** を採用する。修正の雛形は Rust 側の `reconnect_with_backoff`（`rust/client/network/src/platform/desktop.rs:279-331`）にある。
  > 対象ファイル: `engine/apps/network/lib/network/zenoh_bridge.ex`

- **`AUTH_REQUIRED` が prod でも既定 false** `-3` — **両者**（Opus -1 ×3 に分割 / GPT -3）
  > `config :network, :auth_required, false`（`config/config.exs:57`）が既定で、`RoomAuth.required?/0` が false のときトークンを無視して常に `:ok` を返す（`room_auth.ex:18-20,29-35,55-56,74-75`）。JWKS 取得 + RS256 検証（`auth_verifier.ex`）と UDP / Zenoh の検証経路は完成しているのに、既定が安全側でないため運用者が 1 手忘れた瞬間に無認証で入室できる。
  > **採用判断**: Opus は経路単位（全体 -1 / UDP -1 / Zenoh -1）、GPT は 1 項目 -3。同一の根に対する二重計上を避け、**-3 の 1 項目**に統合する。`runtime.exs` に既に fail-fast の作りがあるため、`:prod` の既定を true にして明示的な `AUTH_REQUIRED=false` のみ無認証を許す形へ反転するのが最短である。
  > 対象ファイル: `engine/config/config.exs`, `engine/config/runtime.exs`, `engine/apps/network/lib/network/room_auth.ex`

### クライアント

- **OpenXR が出荷 app へ未配線** `-4` — **両者**（Opus -3 / GPT -4）
  > `openxr_loop.rs` はセッション状態機械・action set・pose / ボタンの `XrInputEvent` 化まで書かれた 296 行の実装になった（`rust/client/xr/src/openxr_loop.rs:14-259`）。しかし (1) `app/src/main.rs` に `xr` クレートの参照がなく起動経路がない、(2) `xr/Cargo.toml:7-9` で `default = []`・`openxr` は optional のため既定ビルドに含まれない、(3) `XR_MND_headless` を必須とし未対応ランタイムでは即 `Err`（`openxr_loop.rs:23-27`）で Monado 系に事実上限定される。結果として **VR は動かない**。
  > **採用判断**: 「VR 対応」を掲げるプロジェクトで VR が起動しないことは価値命題の欠如に当たるため、GPT の **-4** を採用する。まず app 配線と feature 既定化、`XR_MND_headless` 非対応時のフォールバックで「動く経路が 1 本ある」状態を作るべきである。
  > 対象ファイル: `engine/rust/client/xr/src/openxr_loop.rs`, `engine/rust/client/xr/Cargo.toml`, `engine/rust/client/app/src/main.rs`

- **クライアント Rust テストが CI 対象外** `-3` — **両者**（Opus -3 / GPT -3、点数一致）
  > `mix alchemy.ci` の Rust テストは `cargo test -p nif` のみで（`apps/core/lib/mix/tasks/alchemy.ci.ex:99-106`）、GitHub Actions も同じ（`.github/workflows/ci.yml:50-51`）。実際にはクライアント側に **52 件**の `#[test]` がある（shared 18 / system_ui 16 / auth_client 8 / network 6 / audio 2 / render_frame_proto 2）。今回の最大成果である `SnapshotInterpolator` の 18 テストが 1 件も回帰検出に使われていない。
  > **採用判断**: 両者一致で **-3**。`-p nif` を `--workspace` に変える 1 行で解消する。**費用対効果が最も高い未対応項目**として、両評価者が独立に最優先候補に挙げた。
  > 対象ファイル: `engine/apps/core/lib/mix/tasks/alchemy.ci.ex`, `engine/.github/workflows/ci.yml`

### 永続化

- **engine → assets の save / load が未配線** `-3` — **両者**（Opus -1 / GPT -4）
  > `assets` サービスは Objects CRUD・所有権強制・JWKS 検証・Docker Compose・CI を備えて動作する状態だが、engine 側の `"__save__"` / `"__load__"` は「local persistence disabled; network TBD」のログを出すだけである（`apps/contents/lib/events/game.ex:106-111`）。`FormulaStore` の synced スコープも ETS のみで再起動で消える（`formula_store.ex:35-46`）。サービス追加から 18 日間、engine・client のどちらにも `assets` を呼ぶコードがない。
  > **採用判断**: Opus は「README に段階が明示されており無計画ではない」として -1、GPT は「価値命題（ワールド・アバターの永続）の欠如」として -4。保存先が実在し契約（`users/{sub}/private/...`）も定義済みで残るのが配線のみである一方、ルームがクラッシュすれば状態が失われる現状は重い。中間の **-3** を採用する。
  > 対象ファイル: `engine/apps/contents/lib/events/game.ex`, `assets/README.md`

---

## プロジェクト全体（アーキテクチャ）

- **連合が read-only カタログ止まり** `-2` — **両者**（Opus -2 / GPT -2）
  > read-only S2S（`Network.S2S.Instance` / `Catalog` / `Client`、`GET /.well-known/alchemy-s2s.json`）は着地したが、ActivityPub / WebFinger / インスタンス間 identity federation はソース上ゼロで、S2S 自体も既定オフ（`config/config.exs:66-67`）。訪問トークンやアバター持ち出しといった「連合の本体」は未着手である。
  > 対象ファイル: `engine/apps/network/lib/network/s2s/instance.ex`, `engine/config/config.exs`

- **CI 再無効化を防ぐ強制力がない** `-2` — **両者**（Opus -1 / GPT -2）
  > 現 HEAD は `ci.yml` が有効で `mix alchemy.ci` も ALL PASSED である。問題は再発パターンで、`ci ignore` ↔ 再有効化の往復が履歴に 4 回以上あり、今回の無効化期間は PR #326〜#345 の 20 本と重なった。required checks / branch protection は設定されていない。
  > **採用判断**: 現状が緑であることを踏まえても、制度的な歯止めがゼロである点を重く見て GPT の **-2** を採用する。
  > 対象ファイル: `engine/.github/workflows/ci.yml`

**プロジェクト全体 小計: -4**（Opus -4 / GPT -11。差の主因は、GPT が「評価ルール・保証文書の旧構成」-4 をこの分類に置き、Opus が横断の文書 drift として計上したこと。本まとめでは横断に集約した）

---

## auth（認証サービス）

両評価者の指摘 7 項目・小計 -8 が完全一致した。2026-08-01 以降 `lib/` の変更がゼロであるため、前回指摘がそのまま存続している。

- **メール未検証でも JWT を発行する** `-2` — **両者**
  > `login/3` はパスワードと `status == :active` のみを見て `email_verified_at` を参照しない（`auth/lib/auth/accounts.ex:55-68`）。register も未検証のまま `issue_session` する。検証メール送信・SHA-256 ハッシュ保存・ワンタイム消費という検証フロー自体は丁寧に作られているのに、そのゲートが認証経路のどこにも効いていない。
  > 対象ファイル: `auth/lib/auth/accounts.ex`

- **最低年齢ポリシーがない** `-1` — **両者**
  > `BirthdayInPast` は未来日付の拒否のみ（`auth/lib/auth/accounts/validations/birthday_in_past.ex:14-19`）。年齢レーティングを S2S で公開する設計まで持つなら入口の年齢確認は必須である。
  > 対象ファイル: `auth/lib/auth/accounts/validations/birthday_in_past.ex`

- **`/health` に DB readiness がない** `-1` — **両者**
  > status / service / version を返すのみで DB 障害時も `ok`（`auth/lib/auth_web/controllers/health_controller.ex:6-12`）。K8s readiness probe として機能しない。`assets` の `/health` も同様である。
  > 対象ファイル: `auth/lib/auth_web/controllers/health_controller.ex`

- **`account_tokens` の GC が対象外** `-1` — **両者**
  > `TokenCleanup` は `token_revocations` と stale `refresh_tokens` のみを削除する（`auth/lib/auth/token_cleanup.ex:62-96`）。`AccountToken` は `expires_at` / `used_at` を持つのに定期削除されず、検証・リセットメールごとに行が残る。
  > 対象ファイル: `auth/lib/auth/token_cleanup.ex`

- **レート制限が単一ノード ETS** `-1` — **両者**
  > `:auth_rate_limit` の named ETS（`auth/lib/auth/rate_limit.ex:10,54-60`）。実装品質は高いが水平スケール時にバケットが共有されず制限が実質 N 倍に緩む。
  > 対象ファイル: `auth/lib/auth/rate_limit.ex`

- **CORS allowlist がない** `-1` — **両者**
  > `Corsica` / `cors_plug` の参照がゼロで `endpoint.ex:41-52` にも CORS plug がない。Rust クライアントはネイティブ HTTP なので現状は問題ないが、SPA・管理画面を足す時点でプリフライトが通らない。
  > 対象ファイル: `auth/lib/auth_web/endpoint.ex`

- **Dialyzer / 依存監査がない** `-1` — **両者**
  > `dialyxir` / `mix_audit` が deps になく（`auth/mix.exs:41-63`）、`precommit` も credo + test まで。認証ロジックを持つサービスとして型検査と脆弱性監査は入れる価値が高い。
  > 対象ファイル: `auth/mix.exs`

**auth 小計: -8**（両者一致）

---

## assets（アセット・永続化サービス）

- **BLOB とメタデータが非アトミック** `-2` — **GPT**
  > `Assets.Objects.put/4` はファイル書き込みと `AssetMetadata` の upsert を別々に行い、トランザクション境界がない（`assets/lib/assets/objects.ex:20-53`）。片方だけ成功した場合、メタデータのない孤児ファイルまたは実体のないメタデータが残る。
  > **採用判断**: GPT は -3。私有領域の単一ユーザーデータで、再送で回復可能かつ孤児検出も容易であることを考慮し **-2** を採用する。改善は「先にメタデータを pending で作り、書き込み成功後に確定する」2 相方式が定石。
  > 対象ファイル: `assets/lib/assets/objects.ex`

- **テストが失敗系・並行系を覆っていない** `-2` — **両者**（Opus -1 / GPT -2）
  > lib 22 ファイルに対しテスト 3 ファイル・12 ケース。JWKS 取得失敗・kid ローテーション・`MAX_OBJECT_BYTES` 超過（413）・同一パスへの同時書き込みが未検証である。特に JWKS はネットワーク越しの依存で失敗モードが多い。
  > 対象ファイル: `assets/test/`, `assets/lib/assets/token/jwks.ex`

- **書き込みのレート制限・容量クォータがない** `-1` — **Opus**
  > 1 オブジェクトのサイズ上限（既定 1 MiB）はあるが、書き込み回数の制限とユーザー単位の総容量クォータがない。1 アカウントでスロットを変えながら書き込めばディスクを埋められる。auth が 12 バケットの多軸レート制限を持つだけに非対称である。
  > 対象ファイル: `assets/lib/assets_web/controllers/object_controller.ex`

- **ストレージがローカルディスク単一アダプタ** `-1` — **GPT**
  > 保存先がローカルディスク実装に固定で、S3 互換などへの差し替え口がない。複数ノードで assets を動かした時点で共有ストレージが必要になる。
  > 対象ファイル: `assets/lib/assets/objects.ex`

（engine 未配線 -3 は「最重要」節に計上済み）

**assets 小計: -9**（Opus -3 / GPT -10。engine 未配線 -3 を含む）

---

## engine — apps/core

- **`NifBridge.Behaviour` が未配線（モック不能）** `-2` — **両者**
  > Behaviour は定義のみで（`nif_bridge_behaviour.ex:1-8`）、`Core.Formula.run/3` は実 NIF を直呼びする（`formula.ex:22,43`）。config 注入も Mox もないため NIF ビルドなしで core のテストが回らない。GPT は加えて Behaviour の型と実装の不一致を指摘している。
  > 対象ファイル: `engine/apps/core/lib/core/nif_bridge_behaviour.ex`, `engine/apps/core/lib/core/formula.ex`

- **`FormulaStore` の ETS が OTP 所有でない** `-2` — **GPT**
  > `:formula_store_synced` ETS がプロセス所有の明示なく作られ、所有者が落ちた場合の再作成・引き継ぎが設計されていない（`apps/core/lib/core/formula_store.ex:35-46`）。`FrameCache` が「ETS の所有者をルームより先に起動してアプリ寿命で保持する」（`apps/server/lib/server/application.ex:20-31`）という規律を持つのと対照的である。
  > 対象ファイル: `engine/apps/core/lib/core/formula_store.ex`

- **`Core.Telemetry` にゲーム固有メトリクスが残存** `-1` — **Opus**
  > `"game.tick.enemy_count"` / `"game.level_up.count"` / `"game.boss_spawn.count"` という BulletHell 固有の語彙をエンジン層が握っている（`telemetry.ex:25-36`）。`Core.Config` / `StressMonitor` / `Stats` からの語彙分離は完了しており、残渣はここだけである。
  > 対象ファイル: `engine/apps/core/lib/core/telemetry.ex`

- **`Core.Component` の moduledoc が旧前提（60Hz / NIF world）** `-1` — **両者**
  > `on_physics_process/1` を「物理フレーム（60Hz）」と説明し（`component.ex:12`）、context に `world_ref`（Rust ワールド参照）を挙げる（`:22`）。実際には 60Hz 物理ループは撤去され、権威 tick（既定 20Hz）内で `physics_scenes` のシーンのみ呼ばれる（`game.ex:487,500-507`）。README も「ゲーム用 60Hz 物理ループはない」と明記している（`README.md:52`）。moduledoc の誠実さがこのプロジェクトの強みだからこそ、中心ビヘイビアの記述ずれは影響が大きい。
  > 対象ファイル: `engine/apps/core/lib/core/component.ex`

**core 小計: -6**（Opus -4 / GPT -8。GPT の「room 別 Game と global stateful child の不整合」-3 はシーンスタック共有と同根のため contents 側に集約した）

---

## engine — apps/contents

- **`Tetris` だけが固定 60Hz 前提** `-2` — **GPT**
  > `@tick_sec 1.0 / 60.0` と `@base_drop_frames 45` というフレーム数ベースの落下タイマーを持つ（`apps/contents/lib/contents/tetris/playing.ex:10,13,64-65,160-184`）。権威 tick は既定 20Hz なので、dt ベース化の恩恵から唯一取り残されており、実速度が意図の 1/3 になる。「tick_hz を変えてもゲーム速度が変わらない」という設計上の主張に対する反例が本体に残っている。
  > **採用判断**: GPT は -3。影響が 1 コンテンツ内に閉じ、他 4 コンテンツは dt ベース化済みであることを考慮して **-2** を採用する。
  > 対象ファイル: `engine/apps/contents/lib/contents/tetris/playing.ex`

- **テスト密度が低く状態分離の検証がない** `-3` — **両者**（Opus -2 / GPT -2、統合して -3）
  > lib 126 ファイルに対しテスト 8 ファイル（6.3%）。`nodes/`（40+ モジュール）、`objects/`、各 Content の playing ロジック、`FrameEncoder` の DrawCommand 変換が無検証である。加えて「2 ルームで状態が混ざらない」ことを確かめるテストが存在せず、それがシーンスタック共有の見落としを許した。
  > 対象ファイル: `engine/apps/contents/test/`

- **未実装コンポーネント・descriptor 実行系のスタブ残存** `-3` — **両者**（Opus -1 / GPT -2 ×2 → 統合 -3）
  > `objects/core/` の 4 ファイルが「空間エンジンとの統合後に実装」の TODO スタブ（`destroy.ex:16`, `duplicate.ex:19`, `create_empty_parent.ex:18`, `create_empty_child.ex:18`）。`MenuComponent` は実装を持つがどの Content の `components/0` にも登録されていない（`bullet_hell_3d.ex:23-28`, `component_list.ex:15-22`）。GPT はさらに descriptor 実行系のスタブを指摘している。「動く実装」と「動かない実装」が同じ名前空間に同居している。
  > 対象ファイル: `engine/apps/contents/lib/objects/core/`, `engine/apps/contents/lib/components/category/ui/menu_component.ex`

- **`contents` → `network` のコンパイル時依存が残存** `-1` — **Opus**
  > Zenoh publish は MFA 注入に移行し lib 内の直接呼び出しは 0 件になったが、`apps/contents/mix.exs:32-34` に `{:network, in_umbrella: true}` が残り、`FrameEncoder` の都合で network がコンパイル時依存のままである。contents 単体のビルド・テストができない。
  > 対象ファイル: `engine/apps/contents/mix.exs`

- **`Helpers` の 1 引数版が `:main` 固定** `-1` — **Opus**
  > `Contents.Components.Category.Device.Helpers` の 1 引数版が `:main` に委譲する（`helpers.ex:14-15,38-39`）。マルチルームループが駆動する現在、この既定値は非 `:main` ルームで静かに誤ったルームを触る経路になる。
  > 対象ファイル: `engine/apps/contents/lib/components/category/device/helpers.ex`

- **撤去済み frame injection をホットループに温存** `-1` — **GPT**
  > 撤去済みの NIF frame injection 経路に対応するコードが毎フレームの経路に残っている。死にコードがホットパスにあること自体のコストは小さいが、読み手に現行設計を誤解させる。
  > 対象ファイル: `engine/apps/contents/lib/events/game.ex`

（シーンスタック共有 -4 は「最重要」節に計上済み）

**contents 小計: -15**（Opus -9 / GPT -15。シーンスタック共有 -4 を含む）

---

## engine — apps/network

- **`RoomToken` が JWT subject に束縛されていない** `-3` — **GPT**
  > `Network.RoomToken` のペイロードは `room_id` のみで（`room_token.ex:8-10,33-37`）、ユーザー識別子を含まない。`AUTH_REQUIRED=true` で `/api/room_token` が Bearer JWT を検証しても、発行される RoomToken に `sub` が伝播しないため、(1) トークンを入手した第三者が誰としてでも入室でき、(2) サーバがセッションをユーザーに紐付けられない。したがって「認証した」ことがゲーム内の identity になっていない。認証層を作り込んだ後に残る、最も本質的な穴である。
  > **採用判断**: GPT の **-3** を採用する。Opus は本項目を検出できていない。改善は `Phoenix.Token.sign` のペイロードを `%{room_id: ..., sub: ...}` に拡張し、join 時に `sub` を session state に載せるだけで済む。
  > 対象ファイル: `engine/apps/network/lib/network/room_token.ex`, `engine/apps/network/lib/network/router.ex`

- **UDP に信頼性・リプレイ・断片化の契約がない** `-3` — **両者**（Opus -1 / GPT -4）
  > `seq` はヘッダに存在しサーバ送信 FRAME で発行されるが（`udp/server.ex:332-334`）、受信側の INPUT / ACTION で検証されない。したがって古いパケットの再送・並べ替え・リプレイをそのまま受理する。FRAME は zlib 圧縮ペイロードを単一パケットに載せるのみで MTU 超過時の分割も再送もない（`protocol.ex:113-117,169-173`）。
  > **採用判断**: リプレイ受理はセキュリティ、断片化は 3D シーン拡大時の破損として、いずれも実害が読める。中間の **-3** を採用する。信頼性層の自作より QUIC datagram / WebTransport の採用検討を先に置くべきである（提案参照）。
  > 対象ファイル: `engine/apps/network/lib/network/udp/protocol.ex`, `engine/apps/network/lib/network/udp/server.ex`

- **UDP に生パケットサイズ・セッション数・送信頻度の上限がない** `-2` — **Opus**
  > zlib 展開上限（64KB）は入ったが前段の防御が抜けている。ソケットは `active: true` で任意サイズを受け（`udp/server.ex:186-197`）、JOIN はセッション数上限なしに sessions マップを増やし、登録済みセッションからの INPUT / ACTION にレート制限がない（`:240-275`）。`:action` の name も長さ上限なしで decode する（`protocol.ex:165-166`）。送信元詐称が容易な経路として素朴な flood がそのまま増幅面になる。
  > 対象ファイル: `engine/apps/network/lib/network/udp/server.ex`

- **ルーム所在解決が全ノード RPC スキャン** `-2` — **両者**
  > `find_room_node` は毎回 `cluster_nodes()` への `:rpc` 逐次スキャンで（`distributed.ex:239-246`）、コード内コメント自身が「将来は `:global` レジストリや永続的な配置テーブルでキャッシュする余地あり」と認めている。`list_rooms_clustered/0` も同様（`:205-217`）。「1000 人規模」を掲げるならノード数 × 呼び出し頻度に線形劣化する経路は先に潰したい。
  > 対象ファイル: `engine/apps/network/lib/network/distributed.ex`

- **封筒形式をヒューリスティックで判別している** `-1` — **Opus**
  > `unwrap_payload/2` はトークン検証失敗時に `(reason in [:expired, :scope_mismatch] or len > 30) and looks_like_token?(token)` で「封筒だったのか生 protobuf だったのか」を推測する（`room_auth.ex:60-78`）。`looks_like_token?/1` は Base64URL 文字種の正規表現でしかなく（`:93-95`）、protobuf の先頭 2 バイトが妥当な `len` に化けて後続が偶然その文字種に収まれば、ペイロード先頭が黙って切り落とされる。ワイヤ形式の SSoT を経路ごとに定めると掲げるプロジェクトで、ワイヤ解釈を確率に委ねているのは原則違反である。マジックバイト + バージョンで消える。
  > 対象ファイル: `engine/apps/network/lib/network/room_auth.ex`

- **`GET /health` がルーム ID 一覧を公開している** `-1` — **Opus**
  > レスポンスに `room_ids` をそのまま含める（`router.ex:93-96`）。無認証で外部公開する前提のエンドポイントから稼働中のワールド名が偵察できる。件数のみ返し、一覧は S2S / 管理エンドポイントに置くべきである。
  > 対象ファイル: `engine/apps/network/lib/network/router.ex`

- **S2S クライアントが平文 HTTP を許容** `-1` — **GPT**
  > `Network.S2S.Client` が peer URL のスキームを制限しておらず、`http://` でも取得を試みる（`s2s/client.ex:14-22`）。署名付きレスポンスを扱う経路として、TLS を必須にするか少なくとも既定で拒否したい。
  > 対象ファイル: `engine/apps/network/lib/network/s2s/client.ex`

（`AUTH_REQUIRED` 既定 -3、Elixir 側 Zenoh 再接続 -3 は「最重要」節に計上済み）

**network 小計: -19**（Opus -12 / GPT -17。上記 2 件を含む）

---

## engine — apps/server

- **engine の release 定義がない** `-2` — **両者**（Opus -1 / GPT -2）
  > ルート `mix.exs:4-10` と `apps/server/mix.exs:4-15` の双方に `releases:` がなく、配布・デーモン化手段が `mix run --no-halt` のみである。auth と assets は `mix release` + Dockerfile を持つため engine だけが取り残されている。連合として他運営者にサーバを立ててもらう構想があるなら、配布形態の不在は構想の前提を欠く。
  > 対象ファイル: `engine/mix.exs`, `engine/apps/server/mix.exs`

- **専用テストがゼロ** `-1` — **両者**
  > `apps/server/test/` が存在しない。`:main` ルーム起動失敗時に raise する fail-fast の起動シーケンス（プラス点として評価している箇所）そのものが無検証である。Supervisor が起動して `:main` が Registry に登録されるまでを見る smoke test 1 本で足りる。
  > 対象ファイル: `engine/apps/server/`

**server 小計: -3**（Opus -2 / GPT -3）

---

## engine — rust/nif（Formula VM）

- **通常スケジューラ NIF に命令数・入力サイズ上限がない** `-3` — **両者**（Opus -1 / GPT -3）
  > `decode_bytecode` は `while pos < bytecode.len()` で EOF まで無制限に命令を積み（`decode.rs:53-170`）、`run_formula_bytecode` は `#[rustler::nif]` のみで `schedule = "DirtyCpu"` を指定していない（`formula_nif.rs:26-27`）。**ユーザー作成コンテンツを実行する VM** としては、巨大バイトコード 1 本で BEAM の通常スケジューラを専有できる。
  > **採用判断**: 「ユーザーがルールを持ち込む」ことが価値命題である以上、スケジューラ専有はクラッシュに準ずる影響と見て GPT の **-3** を採用する。制御フロー命令を追加する前に入れるべき順序である。
  > 対象ファイル: `engine/rust/nif/src/formula/decode.rs`, `engine/rust/nif/src/nif/formula_nif.rs`

- **decode エラー契約が非対称** `-2` — **GPT**
  > NIF 層の異常は `rustler::Error::Term`、VM のドメインエラーは `{:error, atom, detail}` タプルという 2 層設計自体は良い（プラス点で評価）。しかし decode 系のエラーだけがこの分類の境界を跨いでおり、Elixir 側から見て同じ失敗が経路によって異なる形で返る。エラー契約の一貫性を強みとして評価している以上、ここは揃えたい。
  > **採用判断**: GPT は -3。実害は Elixir 側のパターンマッチ 1 箇所増に留まるため **-2** を採用する。
  > 対象ファイル: `engine/rust/nif/src/nif/formula_nif.rs`, `engine/rust/nif/src/formula/decode.rs`

- **Rust テストが除算に偏っている** `-1` — **両者**
  > `#[test]` 6 件すべてが `binary_div` 関連（`vm.rs:198-307`）。`decode_bytecode` の境界条件（途中終端・未知 opcode・レジスタ範囲外・UTF-8 不正）や他の算術命令の型昇格を Rust 側で検出する層がない。入力バイト列を直書きするだけで書けるため面を稼ぐコストは低い。
  > 対象ファイル: `engine/rust/nif/src/formula/decode.rs`

**rust/nif 小計: -6**（Opus -2 / GPT -7）

---

## engine — rust/client

- **クライアント側予測が未配線** `-2` — **両者**
  > `predict_input` は「入力をそのまま返す」スケルトンのまま（`shared/src/predict.rs:8-13`）。権威 tick 20Hz、補間の遅延バッファ 80〜250ms である以上、自機移動に最低 100ms 超の体感遅延が乗る。補間で「カクつき」は消えたが「重さ」は残っており、VR では特に効く。
  > 対象ファイル: `engine/rust/client/shared/src/predict.rs`

- **補間の対応付けが安定 ID でなく最近傍** `-2` — **GPT**
  > `interpolate_render_frame` はエンティティを距離 3.0 以内の最近傍で突き合わせる（`shared/src/interp.rs:41,311-410`）。DrawCommand に安定した entity_id がないための設計で、Opus はこれを「インデックス対応の罠を避けた良い設計」として +5 の一部に含めた。しかし高速移動・高密度・テレポートでは誤対応が原理的に避けられない。
  > **採用判断**: **両評価者の判断が正面から食い違う唯一の項目**である。まとめとしては両方を採る。近傍マッチは「ID のないプロトコル上での最善手」としてプラス評価を維持し、同時に「protobuf に `entity_id` を 1 フィールド足せば構造的に解決する未払いの設計負債」として **-2** を計上する。ワイヤ変更を伴うため段階的に（ID を送り、あれば ID・なければ近傍で対応）進められる。
  > 対象ファイル: `engine/rust/client/shared/src/interp.rs`, `3rdparty/alchemy-protocol/proto`

- **WASM トランスポートがスタブ** `-2` — **両者**
  > `platform/web.rs:1-29` は全メソッドが「Zenoh WebSocket (WASM) は未実装」を返し、`spawn_subscriber` は空スレッド。クレート構成が示唆するブラウザ対応は現状も虚像である。当面やらないなら `cfg` で切ってロードマップ側に置くほうが読み手を誤らせない。
  > 対象ファイル: `engine/rust/client/network/src/platform/web.rs`

- **`render` クレートの回帰テストがゼロ** `-2` — **両者**
  > 2729 行・client 最大規模のクレート（3D / 2D パイプライン・カメラ・テキスト）に `#[test]` が 1 件もなく `tests/` もない。`headless.rs` に PNG 出力機能がありながら golden image 回帰は未整備である。既存の PNG 出力にハッシュ比較を足すだけで最初の 1 本が書ける。
  > 対象ファイル: `engine/rust/client/render/`

- **カリング・SE ボイス上限がない** `-1` — **両者**（Opus -1 / GPT -2）
  > GPU バックフェイスカリング（`pipeline_3d/mod.rs:269`）のみで、フラスタム・距離カリングのロジックが存在しない。SE は `play_se_with_volume` が呼び出しごとに `Sink::connect_new` + `detach()` するため同時再生数の上限がない（`audio.rs:54-61`）。弾幕系で被弾が連続するとミキサ上の Sink が際限なく増える。
  > 対象ファイル: `engine/rust/client/render/`, `engine/rust/client/audio/src/audio.rs`

- **`RenderFrame` の毎フレーム clone** `-1` — **両者**
  > `sample()` は毎回 `f.clone()` または `interpolate_render_frame` で新規 `RenderFrame` を生成し（`interp.rs:588,592,596,607,615`）、ブリッジ側も所有権コピーを受ける（`network_render_bridge.rs:206`）。`commands` / `mesh_definitions` / `ui` を含む構造体を 60fps でフル複製している。client 全体で `Arc<RenderFrame>` の使用は 0 件。
  > 対象ファイル: `engine/rust/client/shared/src/interp.rs`

- **`network` クレートが `render` / `audio` に依存** `-1` — **GPT**
  > トランスポートのクレートが描画・オーディオに依存しており（`network/Cargo.toml:7-17`）、クレート境界の明快さ（プラス +4 で評価）に対する例外になっている。`RenderFrame` 型と audio cue の受け渡しのためだが、型を `shared` 側に寄せれば依存は切れる。
  > **採用判断**: GPT は -2。実害は再利用性の低下に留まるため **-1** を採用する。
  > 対象ファイル: `engine/rust/client/network/Cargo.toml`

（OpenXR 未配線 -4、クライアントテスト CI 対象外 -3 は「最重要」節に計上済み）

**rust/client 小計: -18**（Opus -14 / GPT -19。上記 2 件を含む）

---

## 横断評価層

### 品質保証・ドキュメント

- **保証ドキュメントと評価ルールが旧構成のまま** `-3` — **両者**（Opus -2 / GPT -4）
  > 品質保証を説明する文書自体が最も陳腐化している。`docs/warranty/ci.md:10,13` は CI ジョブとして `cargo test -p physics`（クレートは撤去済み）と `cargo bench -p physics`（+10% 超でブロック）を掲載するが、実際の定義は `cargo test -p nif` のみで bench ジョブは存在しない（`.github/workflows/ci.yml:50-51`）。README の「main のみ `cargo bench` のリグレッション検知」も事実でない（`README.md:95`）。`ci.md:46` は `CyclomaticComplexity` を「本プロジェクト 15」と書くが `.credo.exs:9` は 10、`ci.md:48` は `AliasUsage` を「3 回以上」と書くが実際は無効化、実在する `proto-verify` ジョブは未記載である。加えて評価ルール `.cursor/rules/evaluation.mdc` 自体が旧レイアウト（`native/physics` / `native/tools/launcher`）を前提にしており、現行の `rust/nif` + `rust/client/*` と一致しない。
  > **採用判断**: Opus は ci.md 単体で -2、GPT は評価ルールを含めて -4。ドキュメント品質がこのプロジェクトの強み（+3）である以上、保証・評価の根拠文書が事実と食い違うのは説明責任の問題に近い。中間の **-3** を採用する。`ci.md` は `.credo.exs` / `ci.yml` から生成するか、CI 変更時の同時更新対象として明記すべきである。
  > 対象ファイル: `engine/docs/warranty/ci.md`, `engine/README.md`, `engine/.credo.exs`, `engine/.cursor/rules/evaluation.mdc`

- **プロパティベース・fuzz・ベンチマークが全体に不在** `-2` — **両者**（点数一致）
  > `engine/mix.lock` / `engine/rust/Cargo.lock` / `auth/mix.exs` のいずれにも StreamData / benchee / proptest / criterion がなく、`rust/**/benches/` は 0 ファイル。バイトコード VM・バイナリプロトコル・グラフコンパイラ・スナップショット補間という「ランダム入力と時間軸に晒される層」を 4 つ持つ構成に対し、example-based のみは防御が薄い。特に `SnapshotInterpolator` の到着時刻・順序・欠落の組み合わせ空間は proptest が最も効く対象である。
  > 対象ファイル: `engine/mix.lock`, `engine/rust/Cargo.lock`

- **telemetry が ConsoleReporter 止まり** `-2` — **両者**（点数一致）
  > engine 全体の `:telemetry.execute` は 3 箇所のみ（`[:game, :session_end]` / `[:game, :tick]` / `[:game, :frame_dropped]`）で、`Core.Telemetry` は `ConsoleReporter` どまり（`telemetry.ex:12-14`）。この 3.5 週間で入った層（JWKS 検証・S2S peer 取得・UDP セッション淘汰・Zenoh 再接続・補間の遅延適応）に telemetry イベントが 1 つも追加されていない。補間の適応遅延はユーザーが「重い」と言ったときに実測値がないと切り分け不能である。
  > 対象ファイル: `engine/apps/core/lib/core/telemetry.ex`

- **依存の脆弱性監査がない** `-1` — **両者**（Opus -1 / GPT -2）
  > `cargo audit` / `mix hex.audit` は CI・aliases とも未組込で、`dependabot.yml` はリポジトリ全体で 0 件。zenoh / wgpu / rustls / Ash と更新の速い依存を多数抱える。alias に `hex.audit` を足すのは 1 行である。
  > 対象ファイル: `engine/.github/workflows/ci.yml`, `engine/mix.exs`

- **CI が単一 OS・署名付き配布手段がない** `-2` — **両者**（Opus -1 / GPT -2）
  > `ci.yml` は全ジョブ `runs-on: ubuntu-latest`。クライアントは Windows / macOS 固有分岐（`platform/` の OS 別実装、Credential Manager / Keychain / Secret Service）を持ち、`mix alchemy.router` も OS で listen アドレスを分けるのに、その分岐が CI で一度も検証されない。インストーラ（MSIX / notarized dmg）・自動更新も未着手である。
  > 対象ファイル: `engine/.github/workflows/ci.yml`

（CI 再無効化の強制力 -2 は「プロジェクト全体」に計上済み）

**横断（品質保証） 小計: -10**（Opus -11 / GPT -11）

### ゲームプレイ完成度

- **実ゲームは 2 本、残り 3 本は技術デモ** `-3` — **両者**（Opus -2 / GPT -3）
  > 開始 → プレイ → 終了 → リトライが閉じているのは `Content.Tetris` と `Content.BulletHell3D` の 2 本で、`CanvasTest` / `FormulaTest` / `SampleOsc` はデバッグ・検証用である。既定に近い `BulletHell3D` はタイトル画面がなく起動即プレイ、敵種 1 種（Cone、単色）、プレイヤーの攻撃手段なし、単一アリーナで時間経過による難度スケールのみ。エンジンのコンテンツ交換可能性の実証としては 5 例で足りているが、外部の人に渡して 10 分遊べる状態には達していない。
  > 対象ファイル: `engine/apps/contents/lib/contents/bullet_hell_3d/`

- **視覚アセットが極薄** `-2` — **GPT**
  > `engine/assets/audio/` に 6 ファイル、`sprites/atlas.png` 1 枚のみで、`vampire_survivor/` と `mini_shooter/` は `.gitkeep` だけである。`BulletHell3D` はプロシージャルメッシュ描画（`assets_path: ""`）のため BGM をコンテンツ側から配信していない。設定 UI もない。
  > **採用判断**: GPT は -3。エンジン評価の主眼ではないが「遊べるゲーム」観点では実質的な欠落であるため **-2** を採用する。
  > 対象ファイル: `engine/assets/`

- **ゲームプレイ E2E / ビジュアル回帰がない** `-1` — **GPT**
  > 「起動して 1 分遊べる」ことを機械的に確認する経路がない。`render` の headless PNG 出力があるため、golden image と組み合わせれば最小の 1 本は書ける（提案参照）。
  > **採用判断**: 内容が「render 回帰テストゼロ」（rust/client -2）と重なるため、こちらは **-1** に留めて二重計上を避ける。
  > 対象ファイル: `engine/rust/client/render/src/headless.rs`

**横断（ゲームプレイ） 小計: -6**（Opus -2 / GPT -10）

---

## 総計

| 大分類 | 採用 | Opus | GPT | 主な相違点 |
|:---|:---:|:---:|:---:|:---|
| プロジェクト全体（アーキテクチャ） | **-4** | -4 | -11 | GPT は文書 drift をここに計上（本まとめは横断へ集約） |
| auth | **-8** | -8 | -8 | 完全一致（7 項目とも同一） |
| assets | **-9** | -3 | -10 | GPT が非アトミック性・単一アダプタを追加検出 |
| engine — apps/core | **-6** | -4 | -8 | GPT が `FormulaStore` の ETS 所有を追加検出 |
| engine — apps/contents | **-15** | -9 | -15 | Tetris 60Hz は GPT のみ。Opus はシーンスタック共有を初稿で見落とし |
| engine — apps/network | **-19** | -12 | -17 | RoomToken の subject 未束縛・S2S 平文は GPT のみ |
| engine — apps/server | **-3** | -2 | -3 | release 定義の重みが -1 / -2 |
| engine — rust/nif | **-6** | -2 | -7 | gas 上限と decode 契約の重みが大きく異なる |
| engine — rust/client | **-18** | -14 | -19 | 近傍マッチの評価が正反対（下記） |
| 横断評価層（品質保証） | **-10** | -11 | -11 | 項目の割り方が異なる（本まとめは文書 drift を統合して -3） |
| 横断評価層（ゲームプレイ） | **-6** | -2 | -10 | アセット・遊び幅の重みが最大の相違 |
| **マイナス合計** | **-104** | **-69** | **-119** | |

各カテゴリの「採用」は、当該節に列挙した項目と「最重要」節から当該カテゴリへ配分した項目の合計である（contents にシーンスタック共有 -4、network に `AUTH_REQUIRED` -3 と Zenoh 再接続 -3、rust/client に OpenXR -4 とクライアントテスト CI 外 -3、assets に engine 未配線 -3 を含む）。network と rust/client の採用点が両評価者いずれの合計も上回るのは、双方の検出を和集合として採ったためである。

採用項目数: **56 件**。出典の内訳は、**両評価者が独立に同じ欠陥へ到達したものが 37 件**、GPT のみが 12 件、Opus のみが 7 件である。

### 評価者間の相違について

**相違の性質は 3 種類に分かれる。**

1. **重みの違い（大半）** — 同じ事実を見て点数が 1〜2 段違う。GPT は「出荷経路で成立していないもの」を厳しく採点し（未配線 = -4）、Opus は「器と契約が既にあり残るのが配線のみ」なら緩める傾向がある。合計差 -50 のうち約 -30 はこの傾向差で説明できる。本まとめは、影響が実際に読める範囲で中間を採った。

2. **検出漏れ（双方にある）** — GPT のみが検出したもの: `RoomToken` の subject 未束縛（-3）、Tetris の 60Hz 固定（-2）、`FormulaStore` の ETS 非所有（-2）、assets の非アトミック性（-2）、S2S の平文 HTTP 許容（-1）。Opus のみが検出したもの: 封筒形式のヒューリスティック判別（-1）、`/health` のルーム ID 公開（-1）、UDP の flood 耐性欠如（-2）、assets の書き込みクォータ欠如（-1）、`Helpers` の `:main` 固定（-1）。**独立二重評価を導入した最大の成果はこの 10 件**であり、単独評価では取りこぼしていた。なお Opus のみの項目は残り 2 件（`Core.Telemetry` の残存語彙 -1、`contents` → `network` のコンパイル時依存 -1）あるが、これらは前回評価からの継続指摘であり新規検出ではない。

3. **判断の対立（1 件のみ）** — 補間のエンティティ対応付けを最近傍で行う設計について、Opus は「インデックス対応の罠を避けた優れた設計」として加点、GPT は「安定 ID を持たない設計上の欠陥」として減点した。まとめとしては両方を採用した（プラス側は「ID のないプロトコル上での最善手」、マイナス側は「protobuf に `entity_id` を足せば構造的に解決する未払いの負債」-2）。両立させたのは、現時点の実装として最善であることと、より良い解が構造的に存在することが同時に真だからである。

### Opus の自己修正

第1評価者は初稿（`9da2712` 時点）で「シーンスタック共有」を解消と誤判定し、「Elixir 側 Zenoh 再接続なし」を見落としていた。GPT の指摘を受けて対象ファイルを再検証し、自ら -4 / -3 を計上し直した上で、関連するプラス点（`RoomSupervisor` +3 → +2）も引き下げている。同一の評価者が単独で評価していれば、`8f35a57` の評価は「マルチルーム対応完了」という誤った記録として残っていた。
