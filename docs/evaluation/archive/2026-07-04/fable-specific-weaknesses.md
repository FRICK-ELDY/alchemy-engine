# Fable 評価 — マイナス点詳細一覧

評価日: 2026-07-04 / 評価者: Fable 5（ソースベース評価、ドキュメント非参照）
対象: `auth/`（認証サービス）+ `engine/`（apps 4アプリ + rust/client 10クレート + rust/nif）

## 採点基準

| 点数 | 基準 |
|:---:|:---|
| -1 | 軽微な問題。命名の不統一、小さな重複、ドキュメント不足など |
| -2 | 中程度の問題。設計原則違反、テスト欠如、保守性を下げる実装 |
| -3 | 設計上の明確な欠陥。バグ・クラッシュ・性能劣化を引き起こしうる |
| -4 | プロジェクトの価値命題を損なう重大な欠如。説明責任が果たせない |
| -5 | アーキテクチャレベルの根本的欠陥。大規模な手戻りが必要 |

---

## プロジェクト全体（アーキテクチャ）

- **「連合（Federation）」の実装が存在しない** `-4`
  > プロジェクトの掲げる「分散連合型 VRSNS」のうち、「連合」に相当する実装（ActivityPub / WebFinger / インスタンス間 S2S API / インスタンス間 identity federation）はソース上ゼロ。全リポジトリを `activitypub|webfinger|federation` で検索してもヒットなし。存在するのは libcluster + `:rpc` による **単一運営者の BEAM クラスタ**（`engine/config/config.exs:16-17` はデフォルト `topologies: []` で単一ノード）と Zenoh 配信であり、これは「分散」ではあっても「連合」ではない。価値命題の中核が未着手である以上、-4 は免れない。
  > 対象ファイル: `engine/config/config.exs`, `engine/apps/network/lib/network/distributed.ex`

- **auth と engine が未接続（認証の分断）** `-3`
  > auth は RS256 JWT + JWKS を発行するが、engine 側に JWKS を取得して JWT を検証するコードが存在しない。engine の入場券 `POST /api/room_token` は **無認証で誰にでも** room token を発行する（`network/router.ex:14-30`）。結果として RoomToken・WebSocket 認証はセルフサービスで、auth の作り込みがゲームサーバの保護に一切寄与していない。
  > 対象ファイル: `engine/apps/network/lib/network/router.ex`, `auth/lib/auth/token/keys.ex`

- **永続化層の不在（engine）** `-2`
  > ゲーム状態のセーブ/ロードは「network TBD」として明示的に無効化されており（`events/game.ex:107-112`）、ルームプロセスがクラッシュすると Supervisor は再起動するが状態は初期化される。FormulaStore synced も ETS のみで再起動で消失。VRSNS としてワールド・アバター等の永続データを持つ場所がない。
  > 対象ファイル: `engine/apps/contents/lib/events/game.ex`, `engine/apps/core/lib/core/formula_store.ex`

---

## auth（認証サービス）

- **レート制限が完全に欠如** `-4`
  > `/api/login`・`/api/register`・`/api/refresh` に試行回数制限・スロットリングが一切ない（router にプラグなし、Hammer 等の依存もなし）。Argon2 の計算コストが唯一の抑止であり、インターネット公開する認証サービスとしてブルートフォース・アカウント列挙・登録スパムに無防備。タイミング攻撃対策まで実装した他の丁寧さと落差が大きく、認証サービスの価値命題を損なう欠如。
  > 対象ファイル: `auth/lib/auth_web/router.ex`, `auth/mix.exs`

- **Authenticate プラグの未処理エラー経路（クラッシュ→500）** `-3`
  > `Token.verify/1` は Joken 検証失敗時に `{:error, error}`（構造体）を返しうるが（`token.ex:47`）、`AuthWeb.Plugs.Authenticate` の `else` 節は `:invalid_token`・`:revoked`・`:user_not_found`・`:user_not_active` の 4 atom しかマッチしない（`authenticate.ex:35-45`）。細工されたトークンで WithClauseError が発生し、401 ではなく 500 を返す。認証境界での例外は情報漏洩とログノイズの両面で有害。
  > 対象ファイル: `auth/lib/auth_web/plugs/authenticate.ex`

- **メールアドレス検証がない** `-2`
  > 登録時にメール所有確認がなく、format regex のみ。他人のメールアドレスで登録可能で、将来のパスワードリセット実装時に不正の起点になる。
  > 対象ファイル: `auth/lib/auth/accounts/user.ex`

- **リフレッシュトークンのローテーションなし** `-2`
  > `refresh` は同一 opaque token を使い回し `last_used_at` を更新するのみ（`accounts.ex:66-90`）。盗まれたトークンはスライディングウィンドウを更新し続ける限り半永久的に有効で、再利用検知もない。OAuth 2.0 Security BCP のローテーション+再利用検知に照らして欠如。
  > 対象ファイル: `auth/lib/auth/accounts.ex`

- **アクセストークン TTL 86,400 秒（24 時間）** `-2`
  > `config :auth, :jwt` の TTL が 24 時間（`config/config.exs:16`）。jti 失効は auth ローカル DB 照会のみで、JWKS 検証する外部リソースサーバには失効が伝播しない設計のため、長 TTL のリスクがそのまま残る。一般的な 5〜15 分に対して過大。
  > 対象ファイル: `auth/config/config.exs`

- **鍵ローテーション未対応** `-2`
  > 署名鍵は単一ペア固定で、JWKS は常に 1 鍵のみ返す。ローテーション時に旧鍵検証の猶予期間を設ける仕組みがなく、鍵漏洩時は全トークン即時無効化しか選択肢がない。
  > 対象ファイル: `auth/lib/auth/token/keys.ex`

- **token_revocations / 期限切れ refresh_tokens の GC がない** `-2`
  > 失効レコードは `expires_at` 経過後も削除されず無限に蓄積する。定期削除ジョブ（Oban 等）が存在しない。
  > 対象ファイル: `auth/lib/auth/accounts/token_revocation.ex`

- **アカウント運用機能の不在（パスワードリセット・変更・退会）** `-2`
  > パスワードを忘れたユーザーの復旧手段、パスワード変更、アカウント削除の API がない。運用開始した瞬間に必要になる機能群。
  > 対象ファイル: `auth/lib/auth_web/router.ex`

- **auth の CI が品質ゲートなし** `-2`
  > GitHub Actions は `mix test` のみで、`format --check-formatted`・`credo`・`compile --warnings-as-errors` がない。engine 側 CI（fmt/clippy/credo/warnings-as-errors 完備）との落差が大きく、モノレポ内で品質基準が分裂している。
  > 対象ファイル: `auth/.github/workflows/ci.yml`

- **本番デプロイ構成の不在** `-2`
  > Dockerfile は dev 用 compose（Postgres）のみで、`mix release` 設定・本番イメージ・ヘルスチェック用 DB 疎通確認がない。`/health` 相当も未実装（router に該当ルートなし）。
  > 対象ファイル: `auth/`（全体）

- **register のユーザー列挙** `-1`
  > 登録失敗時に `has already been taken` がフィールド別に返り、username/email の存在が列挙可能。login 側は対策済みなのと非対称。
  > 対象ファイル: `auth/lib/auth_web/controllers/auth_controller.ex`

- **DB SSL 設定がコメントアウトのまま** `-1`
  > `runtime.exs` の ssl 設定が TODO コメントで放置。マネージド DB 接続時に平文になるリスク。
  > 対象ファイル: `auth/config/runtime.exs`

- **最低年齢チェックなし** `-1`
  > 誕生日を必須収集しながら、COPPA 等を意識した年齢下限バリデーションがない。収集だけして使わないのは中途半端。
  > 対象ファイル: `auth/lib/auth/accounts/user.ex`

**auth マイナス小計: -26**

---

## engine — apps/core

- **core → contents の論理的循環依存** `-3`
  > umbrella 依存は contents→core の一方向だが、core の `@default_content Contents.BulletHell3D`（`room_supervisor.ex` 等）や `Core.StressMonitor` の `wave_label` / `enemy_count` 参照など、エンジン層がゲーム実装の語彙に依存している。config デフォルトと監視項目にコンテンツ知識が漏れており、「core はコンテンツを知らない」という自らの設計原則に違反。
  > 対象ファイル: `engine/apps/core/lib/core/room_supervisor.ex`, `engine/apps/core/lib/core/stress_monitor.ex`

- **NifBridge.Behaviour が未配線（モック不能）** `-2`
  > Behaviour を定義しながら DI（config 注入や Mox）がなく、`Core.Formula` は常に実 NIF を直呼びする。NIF ビルドなしで core のテストを実行できず、Behaviour が死んだ抽象になっている。
  > 対象ファイル: `engine/apps/core/lib/core/nif_bridge_behaviour.ex`, `engine/apps/core/lib/core/formula.ex`

- **FrameCache が単一スナップショット・BulletHell 固有スキーマ** `-2`
  > ETS キャッシュがルーム ID を持たず全ルームで 1 スロットを共有し、フィールドも enemy_count / wave 等の特定ゲーム前提。マルチルーム監視が原理的に不可能。
  > 対象ファイル: `engine/apps/core/lib/core/frame_cache.ex`

- **死にコード・死に設定の残存** `-2`
  > `Core.InputHandler`（NIF 撤去後に呼び出し元なし）、`Core.Telemetry` の `game.tick.physics_ms`（Rust physics 廃止後も固定値を emit）、`config :core, Core.NifBridge, features: []`（moduledoc 自ら「死に設定」と明記）。整理されず残っている。
  > 対象ファイル: `engine/apps/core/lib/core/input_handler.ex`, `engine/apps/core/lib/core/telemetry.ex`, `engine/config/config.exs`

- **Core.Stats が旧ゲーム前提** `-1`
  > kills/graze 等 BulletHell 固有の統計をエンジン層で保持。
  > 対象ファイル: `engine/apps/core/lib/core/stats.ex`

**core マイナス小計: -10**

---

## engine — apps/contents

- **`:main` 以外のルームでゲームループが駆動しない** `-4`
  > `:elixir_frame_tick` の self-send は `room_id == :main` の場合しかスケジュールされず（`events/game.ex` init 内）、`Core.RoomSupervisor.start_room(:room2)` で起動した追加ルームはフレームが進まない。マルチルーム基盤（Supervisor/Registry/Distributed/隔離テスト）を丁寧に構築しながら、肝心のループが単一ルーム前提のままで、「分散型 VRSNS」の複数ワールド同時稼働という価値命題が現状成立しない。
  > 対象ファイル: `engine/apps/contents/lib/events/game.ex`

- **flow_runner(:main) のハードコード** `-3`
  > レンダリング・デバイス系コンポーネントが `content.flow_runner(:main)` を直書きしており（`render.ex:28`, `helpers.ex:15`）、ルーム別の FlowRunner を引けない。上記と併せてマルチルーム化の際に広範な修正が必要。
  > 対象ファイル: `engine/apps/contents/lib/components/category/rendering/render.ex`, `engine/apps/contents/lib/components/category/device/helpers.ex`

- **テスト密度が極端に低い** `-3`
  > lib 119 ファイルに対しテスト 4 ファイル（約 3%）。ゲームロジック（衝突・ウェーブ・スコア）、シーン遷移、FrameEncoder の DrawCommand 変換がほぼ無検証で、リファクタリングの安全網がない。エンジンの心臓部である `Events.Game` 自体の単体テストもない。
  > 対象ファイル: `engine/apps/contents/test/`

- **contents → network の直接依存** `-2`
  > `Events.Game` が `Network.ZenohBridge.publish_frame` 等を直接参照し、umbrella の層構造（network が上位）に逆行する結合がある。FormulaStore が MFA 注入で解決した問題と同型なのに、こちらは未解決。
  > 対象ファイル: `engine/apps/contents/lib/events/game.ex`

- **未実装コンポーネントの残存** `-1`
  > `objects/core/destroy.ex` 等の「空間エンジン統合後に実装」TODO 群、配線されていない MenuComponent。
  > 対象ファイル: `engine/apps/contents/lib/objects/core/`

- **命名の不統一（Content. / Contents.）** `-1`
  > `Content.FlowRunner` と `Contents.*` の 2 つの名前空間が混在。
  > 対象ファイル: `engine/apps/contents/lib/`

- **tick 定数の不整合** `-1`
  > `@tick_ms 16`（62.5Hz）と protobuf/クライアント側の 16.67ms 想定が微妙にずれ、換算に 1000/16 と 60 が混在。
  > 対象ファイル: `engine/apps/contents/lib/events/game.ex`

**contents マイナス小計: -15**

---

## engine — apps/network

- **UDP JOIN が無認証** `-3`
  > WebSocket は RoomToken 必須なのに、UDP の JOIN パケットは client_id を自己申告するだけで入室できる（`udp/server.ex` の join 処理にトークン検証なし）。同一ゲームへの入口でトランスポートにより認証強度が非対称で、UDP 側から容易に迂回できる。
  > 対象ファイル: `engine/apps/network/lib/network/udp/server.ex`

- **zlib 展開の無制限化（zip bomb 耐性なし）** `-3`
  > `Protocol.decode` の圧縮ペイロード展開（`:zlib.uncompress/1`）に展開後サイズ上限がなく、小さな圧縮パケットで巨大メモリ確保を誘発できる。UDP は送信元詐称も容易なため増幅攻撃面になる。
  > 対象ファイル: `engine/apps/network/lib/network/udp/protocol.ex`

- **engine の SECRET_KEY_BASE に fail-fast がない** `-3`
  > dev/test 用の固定値 `"alchemy-engine-secret-key-base-dev-test-minimum-64-chars-required-xxxx"` が config.exs に直書きされ（`config.exs:28`）、prod で env 未設定でも raise せずこの公開値のまま起動する。RoomToken は Phoenix.Token（この secret 由来）で署名されるため、**トークン偽造が公開リポジトリの値だけで可能**になる。auth 側は raise する実装があるだけに欠陥が際立つ。
  > 対象ファイル: `engine/config/config.exs`, `engine/config/runtime.exs`

- **UDP セッションの無期限成長** `-2`
  > クライアントテーブルにタイムアウト・ハートビート淘汰がなく、JOIN しっぱなしのエントリが蓄積し続ける。切断検知がないためブロードキャスト先も増える一方。
  > 対象ファイル: `engine/apps/network/lib/network/udp/server.ex`

- **Zenoh 経由の入力・入室が無認証** `-2`
  > ZenohBridge の client_info / input は形式検証（正規表現・ルーム上限）のみで、身元認証がない。Zenoh ルータに到達できれば誰でも任意ルームへ入力を注入できる。
  > 対象ファイル: `engine/apps/network/lib/network/zenoh_bridge.ex`

- **find_room_node の全ノード RPC スキャン** `-2`
  > ルーム所在解決が毎回 `Node.list()` 全体への `:rpc.call` 逐次スキャンで、コード内コメント自身が「キャッシュ・pg 化が必要」と認めている。ノード数・呼び出し頻度に対して線形に劣化する。
  > 対象ファイル: `engine/apps/network/lib/network/distributed.ex`

- **UDP に断片化・再送・順序制御がない** `-1`
  > フレームが MTU を超えた場合の分割送信がなく、seq 番号もクライアント入力側で検証されない。現行ペイロードでは顕在化しないが、描画量増加で壊れる。
  > 対象ファイル: `engine/apps/network/lib/network/udp/protocol.ex`

**network マイナス小計: -16**

---

## engine — apps/server

- **テストが 0 件** `-1`
  > 起動シーケンス（main ルーム起動失敗時の raise 等）に対するテストがない。
  > 対象ファイル: `engine/apps/server/`

- **リリース定義の不在** `-1`
  > `mix release` 設定がなく、サーバ配布・デーモン化の手段が `mix run --no-halt` のみ。
  > 対象ファイル: `engine/mix.exs`

**server マイナス小計: -2**

---

## engine — rust/nif（Formula VM）

- **binary_div の float 除算が整数除算に化けるバグ** `-3`
  > `Value::as_i32()` は F32 も `Some(truncate)` を返すため（`value.rs`）、`binary_div` の `if let (Some(va), Some(vb)) = (a.as_i32(), b.as_i32())` が **常に成立**し、F32 同士の除算も整数除算になる（`vm.rs:151-165`）。`5.0 / 2.0` が `2.5` ではなく `I32(2)` を返す。float 除算パスは到達不能な死にコード。加減乗は型で正しく分岐しているため、除算だけ静かに誤った値を返す実バグ。Elixir テストは整数のゼロ除算しか検証しておらず検出されていない。
  > 対象ファイル: `engine/rust/nif/src/formula/vm.rs`, `engine/rust/nif/src/formula/value.rs`

- **Rust 単体テストがゼロ** `-3`
  > `nif` クレートに `#[test]` が 1 件もなく、CI の `cargo test -p nif` は 0 テストで PASS する。上記の除算バグが素通りしているのはこの直接的帰結。decode の境界条件・VM の型昇格regressionを検出する層が Rust 側に存在しない。
  > 対象ファイル: `engine/rust/nif/src/`

- **i32::MIN / -1 のパニック経路** `-2`
  > I32 除算が生の `/` を使っており（`vm.rs`）、`i32::MIN / -1` はオーバーフローで release でもパニックする（Rust の除算は常に検査）。加減乗を saturating にした防御方針と不整合。Rustler が panic を catch して Erlang 例外にするため BEAM は落ちないが、エラータプル契約が破れる。
  > 対象ファイル: `engine/rust/nif/src/formula/vm.rs`

- **命令数・入力サイズの上限なし** `-1`
  > `decode_bytecode` は EOF まで無制限に命令を積み、通常スケジューラ NIF（DirtyCpu 未指定）なので巨大バイトコードは BEAM スケジューラを専有しうる。ユーザー作成コンテンツを実行する VM としては DoS 面。
  > 対象ファイル: `engine/rust/nif/src/formula/decode.rs`, `engine/rust/nif/src/nif/formula_nif.rs`

**rust/nif マイナス小計: -9**

---

## engine — rust/client

- **補間・予測が未配線（20Hz 描画のカクつき）** `-4`
  > サーバは 3 フレームに 1 回（約 20Hz）しか配信しないのに、クライアントは受信フレームをそのまま描画し、`shared/src/interp.rs` に補間ユーティリティが存在しながら **どこからも使われていない**（grep で使用箇所ゼロ）。60fps レンダリングに対し実質 20Hz のスナップショット表示となり、VR/リアルタイム体験の中核品質（滑らかさ）が損なわれている。VRSNS を名乗る上での価値命題直撃。
  > 対象ファイル: `engine/rust/client/shared/src/interp.rs`, `engine/rust/client/network/src/network_render_bridge.rs`

- **OpenXR が完全スタブ** `-4`
  > `xr` クレートは型定義（イベント enum 等）のみで、openxr クレートへの依存も実装もない（`xr/src/lib.rs`）。VR 入力（head_pose/controller_pose）のサーバ側受け口やガードは実装済みなのに、それを発生させる HMD 統合が存在しない。「VRSNS」の V が現状動作しない。
  > 対象ファイル: `engine/rust/client/xr/src/lib.rs`

- **Zenoh publisher を put ごとに宣言（ホットパス性能欠陥）** `-3`
  > `ClientSession::put` / `put_drop` が呼び出しのたびに `declare_publisher` している（`platform/desktop.rs:45-67`）。入力送信は 60Hz で走るため、毎フレーム publisher の宣言・破棄が発生する。Zenoh の設計では publisher は宣言して再利用するのが前提であり、レイテンシ・ルータ負荷の双方に効く。
  > 対象ファイル: `engine/rust/client/network/src/platform/desktop.rs`

- **クライアント Rust テストが CI で実行されない** `-3`
  > CI の Rust テストは `cargo test -p nif` のみで（`ci.yml:50-51`、nif は 0 テスト）、実際に存在する約 29 件のクライアントテスト（golden 契約・パストラバーサル・system_ui 状態機械等）が **一度も CI で走らない**。良いテストを書きながら回帰検出に使えていない。
  > 対象ファイル: `engine/.github/workflows/ci.yml`, `engine/apps/core/lib/mix/tasks/alchemy.ci.ex`

- **Zenoh 切断からの再接続なし** `-2`
  > セッション確立後の切断（ルータ再起動等）を検知して再接続するロジックがなく、subscriber スレッドは黙って受信しなくなる。クライアントは再起動が必要。
  > 対象ファイル: `engine/rust/client/network/src/platform/desktop.rs`

- **WASM プラットフォームが未実装スタブ** `-2`
  > `platform/wasm.rs` 相当は存在するが実体がなく、クレート構成が示唆するブラウザ対応は現状虚像。
  > 対象ファイル: `engine/rust/client/network/src/platform/`

- **render クレートのテストが 0** `-2`
  > 最大規模のクレート（3D/2D パイプライン・カメラ・テキスト）に単体テストがなく、headless レンダラーがありながら golden image 回帰も未整備。
  > 対象ファイル: `engine/rust/client/render/`

- **GPU デバイスロス回復なし** `-1`
  > `SurfaceError::Lost` 等での再構成処理がなく、ドライバリセットでクラッシュ・黒画面のまま。
  > 対象ファイル: `engine/rust/client/render/src/renderer/mod.rs`

- **RenderFrame の毎フレーム clone** `-1`
  > ブリッジ→レンダラー間で `RenderFrame` を clone しており、描画コマンド増加時のアロケーション負荷になる。
  > 対象ファイル: `engine/rust/client/network/src/network_render_bridge.rs`

- **カリング・SE ボイス上限なし** `-1`
  > フラスタム/画面外カリングがなく全 DrawCommand を GPU へ送る。SE の同時再生数上限もない。
  > 対象ファイル: `engine/rust/client/render/`, `engine/rust/client/audio/`

**rust/client マイナス小計: -23**

---

## 横断評価層

- **プロパティベース・fuzz・ベンチマークが全体に不在** `-2`
  > StreamData/proptest/criterion/benchee のいずれも依存に存在しない。バイトコード VM・バイナリプロトコル・グラフコンパイラという「ランダム入力に晒される層」を 3 つも持つプロジェクト構成に対して、example-based テストのみは防御不足。
  > 対象ファイル: `engine/mix.exs`, `engine/rust/`, `auth/mix.exs`

- **可観測性の実装が定義と乖離** `-2`
  > telemetry の `execute` は engine 全体で 3 箇所のみで、`Core.Telemetry` は ConsoleReporter どまり（LiveDashboard・外部エクスポートなし）。定義済みメトリクスに死にメトリクス（physics_ms）が混在し、運用時に「見える」状態にない。
  > 対象ファイル: `engine/apps/core/lib/core/telemetry.ex`

- **依存の脆弱性監査がない** `-1`
  > `cargo audit` / `mix hex.audit` / dependabot 設定が CI・リポジトリに存在しない。
  > 対象ファイル: `engine/.github/workflows/ci.yml`, `auth/.github/workflows/ci.yml`

- **CI が ubuntu のみ・配布手段なし** `-1`
  > クライアントは Windows/macOS を明示サポートする分岐を持つのに CI は ubuntu-latest のみ。インストーラ・ランチャー・自動更新も未着手。
  > 対象ファイル: `engine/.github/workflows/ci.yml`

**横断マイナス小計: -6**

---

## 総計

| 大分類 | マイナス小計 |
|:---|:---:|
| プロジェクト全体（アーキテクチャ） | -9 |
| auth | -26 |
| engine — apps/core | -10 |
| engine — apps/contents | -15 |
| engine — apps/network | -16 |
| engine — apps/server | -2 |
| engine — rust/nif | -9 |
| engine — rust/client | -23 |
| 横断評価層 | -6 |
| **マイナス合計** | **-116** |
