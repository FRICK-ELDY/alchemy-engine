# Fable 評価 — マイナス点詳細一覧

評価日: 2026-07-31 / 評価者: Fable 5（ソースベース評価、ドキュメント非参照）
対象: `auth/`（認証サービス、lib 37 ファイル）+ `engine/`（apps 4アプリ + rust/client 10クレート + rust/nif）
前回評価: 2026-07-07（`archive/2026-07-31/`）。本版は engine の tick 設定化・CI 再有効化（PR #320〜#322）を反映し、前回の全指摘を現ソースで再検証した再評価。

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
  > プロジェクトの掲げる「分散連合型 VRSNS」のうち、「連合」に相当する実装（ActivityPub / WebFinger / インスタンス間 S2S API / インスタンス間 identity federation）はソース上ゼロ。`apps/`・`rust/` を `activitypub|webfinger|federation` で検索してもヒットなし（今回再確認）。前回以降に連合アーキテクチャの方針ドキュメントは追加されたが（PR #319）、本評価はソースのみを対象とするためコードゼロの事実は変わらない。存在するのは libcluster + `:rpc` による **単一運営者の BEAM クラスタ**（`engine/config/config.exs:16-17` はデフォルト `topologies: []`）と Zenoh 配信であり、これは「分散」ではあっても「連合」ではない。
  > 対象ファイル: `engine/config/config.exs`, `engine/apps/network/lib/network/distributed.ex`

- **auth と engine が未接続（認証の分断）** `-3`
  > auth は RS256 JWT + JWKS を発行するが、engine 側に JWKS を取得して JWT を検証するコードが存在しない（Bearer / JWKS / Joken の参照は engine の Elixir 側にゼロ。JWT を扱うのは Rust `auth_client` のクライアント側のみ）。engine の入場券 `POST /api/room_token` は **無認証で誰にでも** room token を発行する（`network/router.ex:14-19`）。auth の作り込みがゲームサーバの保護に一切寄与していない状態が前回から継続。
  > 対象ファイル: `engine/apps/network/lib/network/router.ex`, `auth/lib/auth/token/keys.ex`

- **永続化層の不在（engine）** `-2`
  > ゲーム状態のセーブ/ロードは「network TBD」として明示的に無効化されており（`events/game.ex:106-115`）、ルームプロセスがクラッシュすると Supervisor は再起動するが状態は初期化される。FormulaStore synced も ETS のみで再起動で消失。VRSNS としてワールド・アバター等の永続データを持つ場所がない。
  > 対象ファイル: `engine/apps/contents/lib/events/game.ex`, `engine/apps/core/lib/core/formula_store.ex`

**全体マイナス小計: -9**

---

## auth（認証サービス）

前回（2026-07-07）以降コミットなし（HEAD `4df420e`、作業ツリーはクリーン）。残存指摘 7 件を現ソースで再確認し、全て存続。

- **ログインにメール検証を要求しない** `-2`
  > 検証フロー（verify-email / resend-verification）は実装済みだが、`login/3` は `status == :active` とパスワードのみ確認し `email_verified_at` を見ない（`accounts.ex:55-68`）。未検証ユーザーでも access token を取得でき、本番運用ではメール所有確認の意味が半減する。
  > 対象ファイル: `auth/lib/auth/accounts.ex`

- **最低年齢チェックなし** `-1`
  > `BirthdayInPast` は過去日のみを要求（`birthday_in_past.ex:14-16`）。`PasswordComplexity` などバリデーション基盤は整っているが、COPPA 等を意識した年齢下限バリデーションは存在しない。
  > 対象ファイル: `auth/lib/auth/accounts/validations/birthday_in_past.ex`

- **`/health` に DB 疎通チェックなし** `-1`
  > status/service/version のみ返却（`health_controller.ex:6-12`）。K8s readiness としては浅く、DB 障害時も `ok` を返しうる。
  > 対象ファイル: `auth/lib/auth_web/controllers/health_controller.ex`

- **`account_tokens` の GC なし** `-1`
  > `TokenCleanup` の対象は `TokenRevocation` / `RefreshToken` のみ（`token_cleanup.ex:12-13,62-68`）。期限切れ・使用済み account_token が蓄積しうる。
  > 対象ファイル: `auth/lib/auth/token_cleanup.ex`

- **レート制限が単一ノード ETS** `-1`
  > 水平スケール時にバケットがノード間で共有されない。複数 auth インスタンス運用時は Redis 等への移行が必要。
  > 対象ファイル: `auth/lib/auth/rate_limit.ex`

- **CORS 未設定** `-1`
  > endpoint / router に CORS 設定なし（Corsica 等の導入ゼロ）。SPA クライアントからの直接 API 呼び出しには追加設定が必要。
  > 対象ファイル: `auth/lib/auth_web/endpoint.ex`

- **Dialyzer / hex.audit なし** `-1`
  > credo は導入済みだが、型検査・依存脆弱性監査は mix.exs / CI とも未導入（`ci.yml:49-55`）。
  > 対象ファイル: `auth/mix.exs`, `auth/.github/workflows/ci.yml`

**auth マイナス小計: -8**

---

## engine — apps/core

- **core → contents の論理的循環依存** `-3`
  > `Core.RoomSupervisor` からのコンテンツ直接参照は解消された（現在は `game_events_module` の config 注入のみ）が、漏洩箇所が移動しただけで問題自体は残存。`Core.Config` が `@default_content Content.BulletHell3D` を持ち（`config.ex:12`）、`Core.StressMonitor` は `content_module.wave_label(elapsed_s)` を呼び enemy_count を監視する（`stress_monitor.ex:40-46`）。エンジン層がゲーム実装の語彙に依存しており、「core はコンテンツを知らない」という自らの設計原則に違反したまま。
  > 対象ファイル: `engine/apps/core/lib/core/config.ex`, `engine/apps/core/lib/core/stress_monitor.ex`

- **NifBridge.Behaviour が未配線（モック不能）** `-2`
  > Behaviour を定義しながら DI（config 注入や Mox）がなく、`Core.Formula.run/3` は常に実 NIF を直呼びする（`formula.ex:43`）。NIF ビルドなしで core のテストを実行できず、Behaviour が死んだ抽象になっている。
  > 対象ファイル: `engine/apps/core/lib/core/nif_bridge_behaviour.ex`, `engine/apps/core/lib/core/formula.ex`

- **FrameCache が単一スナップショット・BulletHell 固有スキーマ** `-2`
  > ETS キャッシュがルーム ID を持たず全ルームで `{:snapshot, data}` の 1 スロットを共有し、フィールドも enemy_count / bullet_count 等の特定ゲーム前提（`frame_cache.ex:12-31`）。マルチルーム監視が原理的に不可能。
  > 対象ファイル: `engine/apps/core/lib/core/frame_cache.ex`

- **死にコード・死に設定の残存** `-1`（前回 -2 から緩和）
  > `Core.InputHandler`（NIF 撤去後に呼び出し元なし）と `config :core, Core.NifBridge, features: []`（moduledoc 自ら「死に設定」と明記）は残存。一方、前回指摘した「`physics_ms` が固定値を emit する死にメトリクス」は実測値ベースに修正され解消した（`game.ex:409-437`, `diagnostics.ex:55-58`）ため 1 点緩和。
  > 対象ファイル: `engine/apps/core/lib/core/input_handler.ex`, `engine/config/config.exs`

- **Core.Stats が旧ゲーム前提** `-1`
  > kills 系（`kills_*`）など BulletHell 固有の統計をエンジン層で保持（`stats.ex:44-53,110-125`）。※前回記載の「graze」は現ソースに存在しないため記述を修正。
  > 対象ファイル: `engine/apps/core/lib/core/stats.ex`

- **出荷 tick_hz とコメント・推奨値の矛盾**（新規） `-1`
  > `config.exs:59-60` のコメントは「デフォルト 20（推奨）」と明記しながら、直後の設定値は `config :server, :tick_hz, 10`（`config.exs:61`）。10 を選んだ理由の説明もなく、`Core.Config` のフォールバック（20）とも食い違う。読み手がどちらが正かを判断できない。
  > 対象ファイル: `engine/config/config.exs`, `engine/apps/core/lib/core/config.ex`

**core マイナス小計: -10**

---

## engine — apps/contents

- **`:main` 以外のルームでゲームループが駆動しない** `-4`
  > `:elixir_frame_tick` の self-send は `room_id == :main` の場合しかスケジュールされず（`game.ex:46-49,343-351`）、非 `:main` ルームの `{:frame_events, _}` はカウンタ更新のみで `scene_update` を呼ばない（`game.ex:332-335`）。`Core.RoomSupervisor.start_room(:room2)` で起動した追加ルームはフレームが進まない。マルチルーム基盤（Supervisor/Registry/Distributed/隔離テスト）を丁寧に構築しながら、肝心のループが単一ルーム前提のままで、「分散型 VRSNS」の複数ワールド同時稼働という価値命題が現状成立しない。
  > 対象ファイル: `engine/apps/contents/lib/events/game.ex`

- **flow_runner(:main) のハードコード** `-3`
  > レンダリング・デバイス系コンポーネントが `content.flow_runner(:main)` を直書きしており（`render.ex:28`, `helpers.ex:15`）、ルーム別の FlowRunner を引けない。`Events.Game` 本体は `flow_runner(state.room_id)` に移行済みなだけに、コンポーネント側の残存が際立つ。
  > 対象ファイル: `engine/apps/contents/lib/components/category/rendering/render.ex`, `engine/apps/contents/lib/components/category/device/helpers.ex`

- **テスト密度が極端に低い** `-3`
  > lib 119 ファイルに対しテスト 4 ファイル（約 3%）。ゲームロジック（衝突・ウェーブ・スコア）、シーン遷移、FrameEncoder の DrawCommand 変換がほぼ無検証で、リファクタリングの安全網がない。今回の dt 化のような全域変更が入っても、ゲーム速度の同一性を検証するテストは存在しない。
  > 対象ファイル: `engine/apps/contents/test/`

- **contents → network の直接依存** `-2`
  > `Events.Game` が `Network.ZenohBridge.publish_frame` を直接参照し（`game.ex:551`）、umbrella の層構造（network が上位）に逆行する結合がある。FormulaStore が MFA 注入で解決した問題と同型なのに、こちらは未解決。
  > 対象ファイル: `engine/apps/contents/lib/events/game.ex`

- **未実装コンポーネントの残存** `-1`
  > `objects/core/destroy.ex` 等の「空間エンジン統合後に実装」TODO 群、配線されていない MenuComponent。
  > 対象ファイル: `engine/apps/contents/lib/objects/core/`

- **命名の不統一（Content. / Contents.）** `-1`
  > 単数 `Content.*`（`Content.BulletHell3D` 等）と複数 `Contents.*`（`Contents.Events.Game` 等）の 2 つの名前空間が混在したまま。
  > 対象ファイル: `engine/apps/contents/lib/`

※前回指摘の「tick 定数の不整合（-1）」は、`Core.Config.tick_ms/0` への一元化と `context.dt` ベースのゲームロジックへの移行により解消。

**contents マイナス小計: -14**

---

## engine — apps/network

- **UDP JOIN が無認証** `-3`
  > WebSocket は RoomToken 必須なのに、UDP の JOIN パケットは client_id を自己申告するだけで入室できる（`udp/server.ex:197-221` の join 処理にトークン検証なし）。同一ゲームへの入口でトランスポートにより認証強度が非対称で、UDP 側から容易に迂回できる。
  > 対象ファイル: `engine/apps/network/lib/network/udp/server.ex`

- **zlib 展開の無制限化（zip bomb 耐性なし）** `-3`
  > `decompress_frame_payload/1` は `:zlib.uncompress/1` を上限なしで呼ぶ（`protocol.ex:180-184`）。小さな圧縮パケットで巨大メモリ確保を誘発でき、UDP は送信元詐称も容易なため増幅攻撃面になる。
  > 対象ファイル: `engine/apps/network/lib/network/udp/protocol.ex`

- **engine の SECRET_KEY_BASE に fail-fast がない** `-3`
  > dev/test 用の固定値 `"alchemy-engine-secret-key-base-dev-test-..."` が config.exs に直書きされ（`config.exs:28`）、runtime.exs は env があれば上書きするのみで prod で未設定でも raise しない（`runtime.exs:29-31`）。RoomToken は Phoenix.Token（この secret 由来）で署名されるため、**トークン偽造が公開リポジトリの値だけで可能**になる。auth 側は raise する実装があるだけに欠陥が際立つ。今回 runtime.exs に TICK_HZ 対応が入ったが、この修正は依然未着手。
  > 対象ファイル: `engine/config/config.exs`, `engine/config/runtime.exs`

- **UDP セッションの無期限成長** `-2`
  > セッションテーブルは JOIN/LEAVE でのみ増減し、タイムアウト・ハートビート淘汰がない（ping は PONG 応答のみ、`udp/server.ex:264-269`）。JOIN しっぱなしのエントリが蓄積し続け、ブロードキャスト先も増える一方。
  > 対象ファイル: `engine/apps/network/lib/network/udp/server.ex`

- **Zenoh 経由の入力・入室が無認証** `-2`
  > ZenohBridge の client_info / input は形式検証（正規表現・最大 100 ルーム制限）のみで、身元認証がない（`zenoh_bridge.ex:263-311`）。Zenoh ルータに到達できれば誰でも任意ルームへ入力を注入できる。
  > 対象ファイル: `engine/apps/network/lib/network/zenoh_bridge.ex`

- **find_room_node の全ノード RPC スキャン** `-2`
  > ルーム所在解決が毎回 `[node() | Node.list()]` への `:rpc.call` 逐次スキャンで（`distributed.ex:242-247`）、コード内コメント自身が「キャッシュ・pg 化が必要」と認めている。ノード数・呼び出し頻度に対して線形に劣化する。
  > 対象ファイル: `engine/apps/network/lib/network/distributed.ex`

- **UDP に断片化・再送・順序制御がない** `-1`
  > フレームが MTU を超えた場合の分割送信がなく、seq 番号もクライアント入力側で検証されない。現行ペイロードでは顕在化しないが、描画量増加で壊れる。
  > 対象ファイル: `engine/apps/network/lib/network/udp/protocol.ex`

**network マイナス小計: -16**

---

## engine — apps/server

- **テストが 0 件** `-1`
  > `apps/server` に test ディレクトリ自体が存在しない。起動シーケンス（main ルーム起動失敗時の raise 等）に対するテストがない。
  > 対象ファイル: `engine/apps/server/`

- **リリース定義の不在** `-1`
  > ルート mix.exs / apps/server/mix.exs とも `releases` 定義がなく、サーバ配布・デーモン化の手段が `mix run --no-halt` のみ。
  > 対象ファイル: `engine/mix.exs`

**server マイナス小計: -2**

---

## engine — rust/nif（Formula VM）

- **binary_div の float 除算が整数除算に化けるバグ** `-3`
  > `Value::as_i32()` は F32 も `Some(truncate)` を返すため（`value.rs:22-28`）、`binary_div` の `if let (Some(va), Some(vb)) = (a.as_i32(), b.as_i32())` が **常に成立**し、F32 同士の除算も整数除算になる（`vm.rs:151-165`）。`5.0 / 2.0` が `2.5` ではなく `I32(2)` を返す。float 除算パスは到達不能な死にコード。加減乗は `matches!((I32, I32))` で型を先に分岐しているため、除算だけ静かに誤った値を返す実バグ。前回指摘から未修正のまま。
  > 対象ファイル: `engine/rust/nif/src/formula/vm.rs`, `engine/rust/nif/src/formula/value.rs`

- **Rust 単体テストがゼロ** `-3`
  > `nif` クレートに `#[test]` が 1 件もなく、CI の `cargo test -p nif` は 0 テストで PASS する。上記の除算バグが素通りしているのはこの直接的帰結。decode の境界条件・VM の型昇格 regression を検出する層が Rust 側に存在しない。
  > 対象ファイル: `engine/rust/nif/src/`

- **i32::MIN / -1 のパニック経路** `-2`
  > I32 除算が生の `/` を使っており、`i32::MIN / -1` はオーバーフローで release でもパニックする。加減乗を saturating にした防御方針（`vm.rs:127,136,145`）と不整合。Rustler が panic を catch して Erlang 例外にするため BEAM は落ちないが、エラータプル契約が破れる。
  > 対象ファイル: `engine/rust/nif/src/formula/vm.rs`

- **命令数・入力サイズの上限なし** `-1`
  > `decode_bytecode`（`decode.rs:53-170`）は EOF まで無制限に命令を積み、NIF は通常スケジューラ登録（DirtyCpu 未指定、`formula_nif.rs:26-27`）なので巨大バイトコードは BEAM スケジューラを専有しうる。ユーザー作成コンテンツを実行する VM としては DoS 面。
  > 対象ファイル: `engine/rust/nif/src/formula/decode.rs`, `engine/rust/nif/src/nif/formula_nif.rs`

**rust/nif マイナス小計: -9**

---

## engine — rust/client

- **補間・予測が未配線（10〜20Hz 描画のカクつき）** `-4`
  > サーバのフレーム配信は権威 tick ごと（出荷設定 10Hz、推奨 20Hz）なのに、クライアントは受信フレームをそのまま描画し、`shared/src/interp.rs` の `lerp` / `lerp_vec2` は定義・re-export のみで **どこからも使われていない**（今回再確認）。60fps レンダリングに対し実質 10〜20Hz のスナップショット表示となり、権威 tick の低 Hz 化（今回の変更）により前回よりさらに影響が拡大した。VR/リアルタイム体験の中核品質（滑らかさ）を損なう価値命題直撃の欠如。
  > 対象ファイル: `engine/rust/client/shared/src/interp.rs`, `engine/rust/client/network/src/network_render_bridge.rs`

- **OpenXR が実質スタブ** `-4`
  > `xr` クレートに `openxr` の optional 依存（feature `openxr`）と `run_xr_input_loop` の枠組みは追加されたが、feature 有効時も `run_openxr_loop` は TODO で即 `Err("not yet implemented")` を返す。VR 入力（head_pose/controller_pose）のサーバ側受け口やガードは実装済みなのに、それを発生させる HMD 統合が動作しない。「VRSNS」の V が現状動作しない状況は前回と同じ。
  > 対象ファイル: `engine/rust/client/xr/src/lib.rs`, `engine/rust/client/xr/Cargo.toml`

- **Zenoh publisher を put ごとに宣言（ホットパス性能欠陥）** `-3`
  > `ClientSession::put` / `put_drop` が呼び出しのたびに `declare_publisher` している（`platform/desktop.rs:45-66`）。入力送信は高頻度で走るため、毎回 publisher の宣言・破棄が発生する。Zenoh の設計では publisher は宣言して再利用するのが前提であり、レイテンシ・ルータ負荷の双方に効く。
  > 対象ファイル: `engine/rust/client/network/src/platform/desktop.rs`

- **クライアント Rust テストが CI で実行されない** `-3`
  > CI の Rust テストは `cargo test -p nif` のみで（nif は 0 テスト）、実際に存在する 29 件のクライアントテスト（system_ui 16 / auth_client 8 / audio 2 / render_frame_proto 2 / network 1）が **一度も CI で走らない**。`mix alchemy.ci` も同様に `-p nif` のみ。良いテストを書きながら回帰検出に使えていない。
  > 対象ファイル: `engine/.github/workflows/ci.yml`, `engine/apps/core/lib/mix/tasks/alchemy.ci.ex`

- **Zenoh 切断からの再接続なし** `-2`
  > セッション確立後の切断（ルータ再起動等）を検知して再接続するロジックがなく（`reconnect` 相当の実装ゼロ）、subscriber スレッドは黙って受信しなくなる。クライアントは再起動が必要。
  > 対象ファイル: `engine/rust/client/network/src/platform/desktop.rs`

- **WASM プラットフォームが未実装スタブ** `-2`
  > `platform/web.rs` は `ClientSession` スケルトンで、`open`/`put`/`put_drop` は「未実装」エラーを返し `spawn_subscriber` は空スレッド。クレート構成が示唆するブラウザ対応は現状虚像。
  > 対象ファイル: `engine/rust/client/network/src/platform/web.rs`

- **render クレートのテストが 0** `-2`
  > 最大規模のクレート（3D/2D パイプライン・カメラ・テキスト）に単体テストがなく、headless レンダラーがありながら golden image 回帰も未整備。
  > 対象ファイル: `engine/rust/client/render/`

- **RenderFrame の毎フレーム clone** `-1`
  > ブリッジ→レンダラー間で `RenderFrame` を clone しており（`network_render_bridge.rs:207,221`）、描画コマンド増加時のアロケーション負荷になる。
  > 対象ファイル: `engine/rust/client/network/src/network_render_bridge.rs`

- **カリング・SE ボイス上限なし** `-1`
  > フラスタム/画面外カリングがなく全 DrawCommand を GPU へ送る。SE は都度 `Sink` 生成→`detach()`（`audio.rs:54-61`）で同時再生数上限がない。
  > 対象ファイル: `engine/rust/client/render/`, `engine/rust/client/audio/`

※前回指摘の「GPU デバイスロス回復なし（-1）」は、`SurfaceError::Lost | Outdated` 時に surface を reconfigure する実装が確認できたため撤回（`renderer/mod.rs:547-556`）。

**rust/client マイナス小計: -22**

---

## 横断評価層

- **プロパティベース・fuzz・ベンチマークが全体に不在** `-2`
  > StreamData/proptest/criterion/benchee のいずれも依存に存在しない。バイトコード VM・バイナリプロトコル・グラフコンパイラという「ランダム入力に晒される層」を 3 つも持つプロジェクト構成に対して、example-based テストのみは防御不足。
  > 対象ファイル: `engine/mix.exs`, `engine/rust/`, `auth/mix.exs`

- **可観測性の実装が定義と乖離** `-2`
  > telemetry の `execute` は engine 全体で 3 箇所のみ（frame_dropped / session_end / tick）で、`Core.Telemetry` は ConsoleReporter どまり（LiveDashboard・外部エクスポートなし）。physics_ms の実測化で死にメトリクスは解消したが、運用時に「見える」状態にないことは変わらない。
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

| 大分類 | マイナス小計 | 前回 | 差分 |
|:---|:---:|:---:|:---:|
| プロジェクト全体（アーキテクチャ） | -9 | -9 | — |
| auth | -8 | -8 | — |
| engine — apps/core | -10 | -10 | —（-2→-1 緩和 1 件、新規 -1 が 1 件） |
| engine — apps/contents | -14 | -15 | +1（tick 不整合解消） |
| engine — apps/network | -16 | -16 | — |
| engine — apps/server | -2 | -2 | — |
| engine — rust/nif | -9 | -9 | — |
| engine — rust/client | -22 | -23 | +1（SurfaceError 回復を確認し撤回） |
| 横断評価層 | -6 | -6 | — |
| **マイナス合計** | **-96** | **-98** | **+2** |

指摘項目数: 48 件。
