# Opus 評価 — マイナス点詳細一覧（2026-10-09）

評価日: 2026-10-09 / 評価者: **Claude Opus 5.5**（第1評価者・独立評価）
対象: スーパープロジェクト `alchemy-engine` と submodule `world-server` / `client` / `auth-server` / `protocol`（各リポジトリの `PROTOCOL_PIN` は `v0.1.2` = `84278a8...`）。2026-10-09 時点の作業ツリー
前回比較の起点: 自系統の前回詳細 `opus/archive/2026-08-25/` と前回まとめ `archive/specific-weaknesses-2026-08-25.md`（いずれも「再検証すべき主張の一覧」として使用し、点数は引き継いでいない）

全項目について対象ファイルを今回あらためて開いて確認した。行番号は今回読んだ現行ソースのもの。「前回から継続」と書いた項目も、現行ファイルで残存を確認してから計上している。

## 採点基準

| 点数 | 基準 |
|:---:|:---|
| -1 | 改善余地あり。動作はするが設計・品質上の軽微な問題 |
| -2 | 重要な機能・設計の欠如。放置すると将来の拡張を阻害する |
| -3 | 設計上の明確な欠陥。バグ・クラッシュ・性能劣化を引き起こしうる |
| -4 | プロジェクトの価値命題を損なう重大な欠如。説明責任が果たせない |
| -5 | プロジェクトの根幹を揺るがす致命的な欠陥。存在しないに等しい |

---

## プロジェクト全体（アーキテクチャ・ビジョンとコードの一致）

### ビジョンの主張と実装

- **「IEEE 754 binary64 の 3D 座標系を保証する」が、ワイヤ上では全座標が binary32** `-4`（新規）
  > README の一行目（`README.md:5,20`）とビジョンの冒頭（`.workspace/0_docs/vision.md:12,25`）は、このプロジェクトが保証するものとして「IEEE 754 binary64 の 3D 座標系」を掲げている。直近の PR #363（`1dbbb52`）で文言をこう揃えたばかりである。ところが、サーバとクライアントが合意する唯一のワイヤ契約 `protocol/proto/` を数えると、`float`（binary32）フィールドが 91、座標・寸法に使われる `double` は 0 である（`double` は `frame_injection.proto:14` の `elapsed_seconds` の 1 つだけ）。DrawCommand の座標は `float x = 1;` から始まり（`protocol/proto/render_frame/draw_commands.proto:27,33,43` ほか）、クライアント側の型も `f32` に固定されている（`client/shared/src/types.rs` の `Vec2 { x: f32, y: f32 }`、`client/shared/src/render_frame/draw_command.rs`）。Elixir の float は内部的に binary64 なので**サーバの中だけは** binary64 だが、ワイヤを越えた時点で原点から約 8km で 1mm 精度を失う。プラットフォームの一行要約が、コードと正面から矛盾している状態である。
  > **改善方針**: 主張に合わせてコードを変えるか、コードに合わせて主張を変えるかのどちらかを明示的に選ぶ。前者なら Godot 4 の "large world coordinates" や Unreal 5 の LWC と同様に、権威座標は binary64 で持ち、ワイヤにはチャンク原点（`double` または `int64` のセル座標）+ ローカルオフセット（`float`）を載せる「浮動原点」方式が定石である。後者なら「サーバ内部の権威座標は binary64、ワイヤとクライアント描画は binary32」と保証範囲を書き分ける。
  > 対象ファイル: `README.md`, `.workspace/0_docs/vision.md`, `protocol/proto/render_frame/draw_commands.proto`, `client/shared/src/types.rs`

- **ビジョンが「物理の基盤」を保証項目に挙げているが、エンジンに物理は存在しない** `-2`（新規）
  > `vision.md:27` は「物理の基盤 — 衝突判定・空間分割・移動の仕組み（コンテンツではなく器）」をエンジンの保証項目として列挙する。しかし、サーバ NIF は Formula VM のみ（`world-server/rust/nif/src/lib.rs:1-4`、`world-server/rust/Cargo.toml` の members は `nif` だけ）、Elixir 側の core にも衝突・空間分割のモジュールはない（`world-server/apps/core/lib/core/` 一覧）。`Content.BulletHell3D` は当たり判定をコンテンツ側で自前実装している（`bullet_hell_3d.ex:6` に「Rust 物理エンジンは使用しない」と明記）。つまり「器」であるはずの物理がコンテンツごとに再実装される構造になっている。NIF から物理を撤去した判断自体は正しいとプラス側で評価しているが、撤去後にビジョンの保証表を更新していない。
  > **改善方針**: (a) 保証表から外して「将来の器」として backlog に移すか、(b) `core` に純 Elixir の空間ハッシュと AABB / 球判定を置いて「器」として提供する。後者は Bevy の `bevy_rapier` のような外部プラグイン位置づけでもよい。
  > 対象ファイル: `.workspace/0_docs/vision.md`, `world-server/rust/nif/src/lib.rs`

### リポジトリ分割

- **4 リポジトリに分割したが、リポジトリ横断の検証が 1 つもない** `-3`（新規）
  > 今回の 45 日間の主作業はスーパープロジェクト化（`world-server` / `client` / `auth-server` / `protocol` の submodule 化）だった。分割そのものはプラス側で評価しているが、分割によって**以前は 1 リポジトリ内で成立していた保証が切れた**。(1) スーパープロジェクトには `.github/` がなく、submodule のピン同士の整合を見るジョブがない。(2) `PROTOCOL_PIN` は `world-server/PROTOCOL_PIN` と `client/PROTOCOL_PIN` に**別々に**置かれ（現在はどちらも `tag=v0.1.2` / `sha=84278a8...` で一致）、片方だけ上げてももう片方は気づかない。(3) Elixir が生成した golden バイト列（`client/network/tests/fixtures/render_frame_elixir_golden.bin`）は client 側にしかなく、`world-server` 側に「現在の `FrameEncoder` が同じバイト列を出す」ことを確認するテストがない（`world-server/apps/network/test/network/proto/protobuf_contract_test.exs` は Input / ClientInfo / FrameInjection の往復だけで RenderFrame の golden を見ていない）。再生成手順もコメントに「one-off script を `mix run` する」と書かれているだけである（`render_frame_e2e_contract.rs:8-10`）。(4) そのうえ client 側の CI は `cargo test` を走らせない（client 節参照）。結果として、Elixir 側の `FrameEncoder` を変えて Rust 側のデコードが壊れても、**どの CI も赤くならない**。
  > **改善方針**: スーパープロジェクトに integration ワークフローを 1 本置く。内容は「submodule をピンで checkout → 2 つの `PROTOCOL_PIN` の一致を検査 → `world-server` で golden を再生成 → `client` で `cargo test -p network --test render_frame_e2e_contract`」。golden の生成は `mix alchemy.gen.golden` のような mix タスクにして手順を固定する。
  > 対象ファイル: `world-server/PROTOCOL_PIN`, `client/PROTOCOL_PIN`, `client/network/tests/render_frame_e2e_contract.rs`, `world-server/apps/network/test/network/proto/protobuf_contract_test.exs`

- **連合が read-only カタログ止まり** `-2`（前回から継続）
  > `Network.S2S.Instance` / `Catalog` / `Client` と `GET /.well-known/alchemy-s2s.json`・`GET /api/s2s/worlds` はあるが（`world-server/apps/network/lib/network/router.ex:32-93`）、既定オフ（`world-server/config/config.exs:67`）で、訪問トークン・インスタンス間 identity・アバター持ち出しはゼロ。カタログの中身も起動中コンテンツと連動しない静的設定である（`config.exs:75` は `bullet-hell-3d` を掲げるが、`config.exs:90` の既定コンテンツは `Content.SampleOsc`）。
  > **改善方針**: 次の一歩は「他インスタンスの JWT を持ったユーザーが自インスタンスのルームに入れる」訪問トークン 1 本に絞る。カタログは `Core.RoomRegistry` と現在の content から生成する。
  > 対象ファイル: `world-server/apps/network/lib/network/s2s/instance.ex`, `world-server/config/config.exs`

### 自己改善サイクル

- **前回改善計画の第 1 波 6 件が 45 日間で 1 件も消化されていない** `-2`（新規）
  > `.workspace/0_reference/improvement-plan.md:59-143` の第 1 波（P-1 クライアントテストを CI に載せる / P-2 prod 認証の fail-secure / P-3 Elixir `ZenohBridge` の再接続 / P-4 保証文書の追従 / P-5 依存監査 / P-6 Tetris の dt 化）を現行ソースで 1 件ずつ確認した。P-1 は `client/.github/workflows/ci.yml` に `cargo test` がなく未了、P-2 は `config.exs:57` が依然 `false`、P-3 は `zenoh_bridge.ex:52-84` に死活監視なし、P-4 は `ci.md:10,13` が依然 `cargo test -p physics` / `cargo bench`、P-5 は 4 リポジトリとも `dependabot.yml` なし、P-6 は `tetris/playing.ex:10,13` が依然 `1.0 / 60.0` と `45` フレーム。いずれも「数行〜1 日」と見積もられていた項目である。`world-server` の Elixir テスト数も core 46 / contents 32 / network 102 で前回と完全に同数だった。分割作業を優先した判断はありうるが、評価 → 計画 → 実装のループがこのサイクルでは回っていない。
  > **改善方針**: 構造変更のサイクルでも、第 1 波のうち 1 行で済むもの（P-1 の `cargo test --workspace`、P-2 の prod 既定反転）だけは同じ PR 列に混ぜる運用にする。
  > 対象ファイル: `.workspace/0_reference/improvement-plan.md`

**プロジェクト全体 小計: -13**

---

## world-server — apps/contents

### マルチルーム・状態分離

- **シーンスタックが全ルームで共有されている** `-4`（前回から継続）
  > `Server.Application` は `{Contents.Scenes.Stack, [content_module: content]}` を `room_id` なしで 1 つだけ起動し（`world-server/apps/server/lib/server/application.ex:25`）、5 つの Content すべてが `def flow_runner(_room_id), do: Process.whereis(Contents.Scenes.Stack)` で `room_id` を捨てる（`bullet_hell_3d.ex:52`, `tetris.ex:27`, `canvas_test.ex:36`, `formula_test.ex:30`, `sample_osc.ex:43`）。`Stack` 側は `room_id` 付き登録に対応済み（`scenes/stack.ex:203-209`）、`ContentBehaviour` には `scene_stack_spec/1` が optional callback として用意されている（`behaviour/content.ex:135`）のに実装はゼロ。`ContentBehaviour` の doc 自身が「room_id は将来のマルチルーム対応で使用する予定」と書いている（`content.ex:42`）。tick は全ルームで回るため、2 ルームで同じコンテンツを動かすと HP・スコア・遷移が相互に上書きされる。
  > **改善方針**: ルームごとに `Contents.Events.Game` と `Contents.Scenes.Stack` を束ねたサブツリー（`one_for_all`）を `RoomSupervisor` 配下に起動し、`flow_runner/1` は `{:via, Registry, {Core.RoomRegistry, {:stack, room_id}}}` で引く。2 ルームで状態が混ざらないことを確かめるテストを同時に足す。
  > 対象ファイル: `world-server/apps/contents/lib/scenes/stack.ex`, `world-server/apps/server/lib/server/application.ex`, `world-server/apps/contents/lib/contents/bullet_hell_3d.ex`

### リモート入力に対する耐性

- **任意のクライアントが `"__quit__"` を送るとサーバプロセス全体が停止する** `-4`（新規）
  > `Device.Keyboard` は全コンテンツに既定で `"__quit__" => :quit` を登録し（`components/category/device/keyboard.ex:70-73`）、受け取ると `event_handler(room_id)` に `:quit_requested` を送る（`:55-58`）。`Contents.Events.Game` は `on_quit_requested/0` 未実装なら `System.stop(0)`、実装済みの 3 コンテンツ（`sample_osc.ex:52`, `formula_test.ex:39`, `canvas_test.ex:45`）も中身は `System.stop(0)` である（`events/game.ex:280-288`）。一方、ネットワーク 3 経路はすべて受信した action 名を無検査で `{:ui_action, name}` としてルームへ転送する（`network/channel.ex:133-145`、`network/udp/server.ex:259-276`、`network/zenoh_bridge.ex:260-272`）。したがって、`AUTH_REQUIRED=false`（既定）なら Zenoh に `game/room/main/input/action` で `"__quit__"` を 1 回 put するだけで、認証ありでも RoomToken を持つ任意の参加者が、**全ルームを載せた BEAM ノードを落とせる**。悪意がなくても起きる。`SampleOsc` / `FormulaTest` / `CanvasTest` の HUD は「Quit」ボタンの action に `"__quit__"` を割り当てており（`sample_osc/playing.ex:238`, `formula_test/playing.ex:205`, `canvas_test/playing.ex:265`）、既定コンテンツ（`SampleOsc`）で 1 人のプレイヤーが Quit を押すと全員のサーバが止まる。クライアントとサーバが同一プロセスだった時代のローカル UI 用の終了経路が、ネットワーク入力の経路と区別されずに残っていることが根本原因である。なお `handle_info(:quit_requested, _)` は `{:noreply, state}` を返さないため（`game.ex:280-288`）、停止処理中に GenServer の bad return も出る。
  > **改善方針**: ネットワーク由来の UI action に許可リストを設け、`__quit__` / `__save__` / `__load__` のような特権 action はネットワーク経路から受け付けない。ルーム停止は `Core.RoomSupervisor.stop_room/1` までに留め、ノード停止はローカルの管理経路（`mix` タスク・管理 API）に限定する。Godot の `multiplayer.allow_object_decoding` や RPC の `authority` 指定と同じ発想で、「誰が呼べる操作か」を経路ごとに決める。
  > 対象ファイル: `world-server/apps/contents/lib/components/category/device/keyboard.ex`, `world-server/apps/contents/lib/events/game.ex`, `world-server/apps/network/lib/network/channel.ex`

- **`Contents.Events.Game` に catch-all の `handle_info` がなく、リモートから 1 メッセージでルームを落とせる** `-3`（新規）
  > `Contents.Events.Game` の `handle_info/2` はすべて特定パターン（`{:ui_action, action} when is_binary(action)` など）で、最後の受け皿がない（`events/game.ex:102-325` を通読して確認。OSC 系の GenServer はすべて `def handle_info(_msg, state)` を持つのと対照的）。`Network.Channel` の `handle_in("action", %{"name" => name}, ...)` は `name` の型を見ずに `send(pid, {:ui_action, name})` する（`network/channel.ex:133-139`）。WebSocket で `{"name": 123}` を送れば `FunctionClauseError` でルームプロセスが落ちる。`RoomSupervisor` は既定の `max_restarts: 3, max_seconds: 5` なので（`core/room_supervisor.ex:60-62`）、短時間に数回送ればスーパーバイザごと落ち、後述の通り `:main` ルームは復元されない。
  > **改善方針**: `Events.Game` に `def handle_info(msg, state)` の受け皿を置いて `Logger.debug` で捨てる。境界側（`Channel` / UDP / Zenoh）でも action 名を「binary・長さ上限・文字種」で検証する。
  > 対象ファイル: `world-server/apps/contents/lib/events/game.ex`, `world-server/apps/network/lib/network/channel.ex`

### 永続化・ゲームロジック

- **save / load が未配線（ログを出すだけ）** `-3`（前回から継続）
  > `"__save__"` / `"__load__"` / `"__load_confirm__"` は「local persistence disabled; network TBD」をログに出して state をそのまま返す（`events/game.ex:106-117`）。前回時点では `assets` サービスが保存先候補として存在したが、今回のスーパープロジェクトには `assets` が含まれておらず（`.gitmodules` は 4 submodule のみ）、保存先の候補自体が見えなくなった。`FormulaStore` の synced スコープも ETS のみで再起動で消える（`core/formula_store.ex:44-50`）。
  > **改善方針**: 保存先を 1 つ決めて 1 経路だけ通す。最小なら `world-server` に Ecto + SQLite / Postgres で `room_snapshots` テーブルを持ち、`__save__` でシーン state を `:erlang.term_to_binary` して保存する。
  > 対象ファイル: `world-server/apps/contents/lib/events/game.ex`

- **`Tetris` だけが固定 60Hz 前提** `-2`（前回から継続）
  > `@tick_sec 1.0 / 60.0` と `@base_drop_frames 45`（`contents/tetris/playing.ex:10,13`）、レベルに応じたフレーム数計算（`:185`）。既定 20Hz では落下が意図の 1/3 の速度になる。他 4 コンテンツは `context.dt` を使っている（`events/game.ex:575-581`）。
  > **改善方針**: `drop_timer` を秒で持ち `context.dt` を減算する。
  > 対象ファイル: `world-server/apps/contents/lib/contents/tetris/playing.ex`

### 品質・負債

- **テスト密度が低く、状態分離・入力境界の検証がない** `-3`（前回から継続）
  > lib 126 ファイルに対しテスト 9 ファイル・32 ケース（前回と同数）。`nodes/` の 40 超のモジュール、各 Content の playing ロジック、`FrameEncoder` の DrawCommand 変換（`frame_encoder.ex` 376 行、テストは audio の 1 ファイルのみ）が無検証である。「2 ルームで状態が混ざらない」「不正な ui_action でルームが落ちない」というテストがないことが、上記 2 件の欠陥を許した。
  > **改善方針**: `FrameEncoder` の golden テスト、`Events.Game` の不正メッセージ耐性テスト、2 ルーム分離テストの 3 本から始める。
  > 対象ファイル: `world-server/apps/contents/test/`

- **未実装スタブ・未登録コンポーネントの残存** `-2`（前回から継続、前回まとめ -3 から減点幅を縮小）
  > `objects/core/destroy.ex:14-17` などの 4 ファイルが TODO で `:ok` を返すスタブ。`Contents.MenuComponent`（`contents/menu_component.ex`、112 行）はどの Content の `components/0` にも登録されていない（grep で参照ゼロを確認）。実装済みと未実装が同じ名前空間に並ぶ。
  > **改善方針**: スタブは `@moduledoc false` + `{:error, :not_implemented}` を返すか、`lib/` から外す。
  > 対象ファイル: `world-server/apps/contents/lib/objects/core/`, `world-server/apps/contents/lib/contents/menu_component.ex`

- **`contents` → `network` のコンパイル時依存** `-1`（前回から継続）
  > `apps/contents/mix.exs` が `{:network, in_umbrella: true}` を持ち、コメントで「`FrameEncoder` が `Alchemy.Render.*` を参照するため」と説明している。protobuf 生成物が `network` 配下にあることが原因で、contents 単体ではビルドできない。
  > **改善方針**: 生成物を独立した `apps/protocol`（または `alchemy_protocol` パッケージ）に移す。
  > 対象ファイル: `world-server/apps/contents/mix.exs`

- **`Device.Helpers` の 1 引数版が `:main` 固定** `-1`（前回から継続）
  > `with_scene_type/2` と `with_playing_scene/1` が `:main` に委譲する（`components/category/device/helpers.ex:14-16,38-40`）。マルチルームで静かに別ルームを触る経路になる。
  > **改善方針**: 1 引数版を削除し、呼び出し側に `room_id` を必須にする。
  > 対象ファイル: `world-server/apps/contents/lib/components/category/device/helpers.ex`

- **撤去済み経路と特定ゲームの語彙がホットループ・汎用ディスパッチに残る** `-1`（前回から継続・範囲拡大）
  > 毎 tick `Process.put(:frame_injection, %{})` → `apply_frame_injection` → 何もしない `apply_frame_injection_binary/2` を通る（`events/game.ex:410-412,449-472`）。汎用イベントディスパッチャに `{:select_weapon, ...}` の後方互換キャスト（`:88-98`）と `{:boss_dash_end, _}`（`:294-298`）が残る。いずれも現行コンテンツに送り手がない。
  > **改善方針**: 削除する。必要なら git 履歴から戻せる。
  > 対象ファイル: `world-server/apps/contents/lib/events/game.ex`

- **`ContentBehaviour` に実装者ゼロの武器・ボス・EXP コールバックが残る** `-1`（新規）
  > `entity_registry/0`、`enemy_exp_reward/1`、`level_up_scene/0`、`boss_alert_scene/0`、`boss_exp_reward/1`、`generate_weapon_choices/1`、`apply_weapon_selected/2` などが optional として定義されている（`behaviour/content.ex:90-119`）が、5 コンテンツのいずれも実装していない（grep で確認）。ビジョンの「エンジンは敵・武器・EXP・ボスを知らない」（`vision.md:33`）に反する語彙が、コンテンツ契約の中に残っている。
  > **改善方針**: 削除し、必要なコンテンツは自分のモジュール内で持つ。
  > 対象ファイル: `world-server/apps/contents/lib/behaviour/content.ex`

- **既定コンテンツ・カタログ・コメントの不一致** `-1`（新規）
  > `config.exs:90` の既定は `Content.SampleOsc` だが、同じファイルのコメントと `vision.md:173` は `Content.BulletHell3D` を「開発既定」としている。S2S カタログ（`config.exs:75`）も `bullet-hell-3d` を掲げる。新規参加者が `mix alchemy.server` で最初に見るのが OSC サンプルになる。
  > **改善方針**: 既定を 1 箇所に決め、カタログは実行中の content から生成する。
  > 対象ファイル: `world-server/config/config.exs`

**apps/contents 小計: -26**

---

## world-server — apps/core

- **`NifBridge.Behaviour` が未配線（NIF をモックできない）** `-2`（前回から継続）
  > Behaviour は定義のみで（`core/nif_bridge_behaviour.ex:1-9`）、`Core.Formula.run/3` は `alias Core.NifBridge` で実 NIF を直呼びする（`core/formula.ex:22,43`）。config 注入も Mox もない。Rust ツールチェーンなしで core のテストが回らない。
  > **改善方針**: `Application.compile_env(:core, :nif_bridge, Core.NifBridge)` で差し替え口を作り、テストで Mox を使う。
  > 対象ファイル: `world-server/apps/core/lib/core/formula.ex`, `world-server/apps/core/lib/core/nif_bridge_behaviour.ex`

- **`FormulaStore` の synced ETS が OTP 所有でない** `-2`（前回から継続）
  > `:formula_store_synced` は「初回に呼んだプロセス」が `:ets.new` で作る（`core/formula_store.ex:44-50,165-167`）。通常はルームの `Events.Game` プロセスが所有者になるため、そのルームが落ちると全ルームの synced 値が消える。2 プロセスが同時に初回呼び出しすると `:ets.new` が `ArgumentError` になる競合もある。`FrameCache` が「ETS の所有者をルームより先に起動する」規律を持つ（`server/application.ex:21-22`）のと対照的である。
  > **改善方針**: `FrameCache` と同様に専用プロセスを Supervisor 子にして所有させる。
  > 対象ファイル: `world-server/apps/core/lib/core/formula_store.ex`

- **`Core.Telemetry` に特定ゲームのメトリクス名が残る** `-1`（前回から継続）
  > `game.tick.enemy_count` / `game.level_up.count` / `game.boss_spawn.count`（`core/telemetry.ex:25-36`）。core の他モジュールからは語彙が抜けた後の残渣である。
  > **改善方針**: コンテンツが自分のメトリクスを `metrics/0` で登録できる optional callback に移す。
  > 対象ファイル: `world-server/apps/core/lib/core/telemetry.ex`

- **`Core.Component` の moduledoc が撤去済みの前提を説明している** `-1`（前回から継続）
  > `on_physics_process/1` を「物理フレーム（60Hz）」、`on_frame_event/2` を「Rust フレームイベント」、`on_nif_sync/1` を「Elixir state → Rust」、context の `world_ref` を「Rust ワールドへの参照」と説明する（`core/component.ex:12-22`）。実際の `world_ref` は `:stub` 固定で（`events/game.ex:21,40`）、60Hz ループも NIF 同期もない。中心ビヘイビアの説明がずれている。
  > **改善方針**: 権威 tick（既定 20Hz）・描画パイプライン同期・`world_ref` 廃止に合わせて書き直す。
  > 対象ファイル: `world-server/apps/core/lib/core/component.ex`

**apps/core 小計: -6**

---

## world-server — apps/network

### 認証・セキュリティ

- **`AUTH_REQUIRED` が prod でも既定 false** `-3`（前回から継続）
  > `config :network, :auth_required, false`（`config/config.exs:57`）に加え、`runtime.exs` も `AUTH_REQUIRED` が `true` / `1` 以外なら `false` に倒す。`RoomAuth.required?/0` が false なら UDP / Zenoh はトークンを無視する（`network/room_auth.ex:18-20,29-35`）。prod で `SECRET_KEY_BASE` 未設定を `raise` で止める作りは既にあるので、同じ形で既定を反転できる。
  > **改善方針**: `config_env() == :prod` では既定 true、明示的な `AUTH_REQUIRED=false` のときだけ無認証を許す。
  > 対象ファイル: `world-server/config/config.exs`, `world-server/config/runtime.exs`, `world-server/apps/network/lib/network/room_auth.ex`

- **`RoomToken` が JWT の subject に束縛されていない** `-3`（前回から継続）
  > `Phoenix.Token.sign(Network.Endpoint, @salt, room_id, ...)` でペイロードは `room_id` だけ（`network/room_token.ex:33-37`）。`/api/room_token` は Bearer JWT を検証しても `{:ok, _claims}` を捨てて発行する（`network/router.ex:145-152`）。トークンを入手した第三者が誰としてでも入室でき、サーバはセッションをユーザーに紐付けられない。
  > **改善方針**: ペイロードを `%{room_id: ..., sub: ...}` にし、join 時に `sub` をセッション state に載せる。
  > 対象ファイル: `world-server/apps/network/lib/network/room_token.ex`, `world-server/apps/network/lib/network/router.ex`

### 回復性

- **Elixir 側 `ZenohBridge` に死活監視・再接続がなく、起動時の不在でアプリごと落ちる** `-3`（前回から継続・内容を補強）
  > `init/1` でセッションを開いて subscriber を 3 本宣言した後、セッション状態を見る経路がない（`network/zenoh_bridge.ex:52-84`）。未知メッセージは debug ログで捨てる（`:168-171`）。加えて `Zenohex.Session.open` が失敗すると `{:stop, reason}` を返し（`:81-83`）、`Network.Application` の子として起動されるため（`network/application.ex:43-59`）、dev / prod の既定（`config.exs:47`）で zenohd が先に立っていなければ network アプリの起動自体が失敗する。Rust クライアント側には指数バックオフ再接続がある（`client/network/src/platform/desktop.rs:280-331`）ので、片側だけ回復する非対称が残る。zenoh 1.x のクライアントセッション内部の自動再接続がどこまで効くかは今回検証していない（`zenohex 0.9.0`）。それを当てにするなら、その旨の記述と結合テストが必要である。
  > **改善方針**: `init/1` は `{:ok, state, {:continue, :connect}}` にしてバックオフ付きで接続を試み、失敗中は publish を捨てる。定期的にセッションの生存を確認し、切断を検知したら subscriber を再宣言する。
  > 対象ファイル: `world-server/apps/network/lib/network/zenoh_bridge.ex`, `world-server/apps/network/lib/network/application.ex`

### UDP

- **UDP に信頼性・リプレイ防止・断片化の契約がない** `-3`（前回から継続）
  > ヘッダに `seq` はあるが受信側で検証しない（`network/udp/server.ex:240-276` は `_seq` で捨てる）。FRAME は zlib 圧縮ペイロードを単一パケットに載せるだけで MTU 超過時の分割も再送もない（`network/udp/protocol.ex:112-117`）。
  > **改善方針**: 自作より QUIC datagram / WebTransport の採用を先に検討する。
  > 対象ファイル: `world-server/apps/network/lib/network/udp/protocol.ex`, `world-server/apps/network/lib/network/udp/server.ex`

- **UDP に生パケット長・セッション数・送信頻度の上限がない** `-2`（前回から継続）
  > `:gen_udp.open(port, [:binary, active: true, ...])`（`udp/server.ex:122`）で任意長を受け、JOIN は上限なしに sessions を増やし（`:296-307`）、INPUT / ACTION にレート制限がない。`:action` の name も長さ上限なしで decode する（`udp/protocol.ex:164-166`）。
  > **改善方針**: パケット長上限、セッション数上限、`{ip, port}` 単位のトークンバケットを入れる。`active: true` は `{active, N}` に変える。
  > 対象ファイル: `world-server/apps/network/lib/network/udp/server.ex`

### 分散・境界

- **ルーム所在解決が全ノード RPC スキャン** `-2`（前回から継続）
  > `find_room_node/1` は毎回 `cluster_nodes()` に対して `:rpc.call` を逐次実行し（`network/distributed.ex:240-246`）、コード内コメントが改善余地を自認している。
  > **改善方針**: `:global` や `Horde.Registry`、または `:pg` グループで配置を引く。
  > 対象ファイル: `world-server/apps/network/lib/network/distributed.ex`

- **Zenoh 封筒形式を推測で判別している** `-1`（前回から継続）
  > 認証オフ時、トークン検証に失敗しても `(reason in [:expired, :scope_mismatch] or len > 30) and looks_like_token?(token)` なら封筒とみなして先頭を切り落とす（`network/room_auth.ex:60-78`）。`looks_like_token?/1` は文字種の正規表現だけである（`:93-95`）。ワイヤの解釈を確率に委ねている。
  > **改善方針**: マジックバイト + バージョン 1 バイトを封筒の先頭に置く。
  > 対象ファイル: `world-server/apps/network/lib/network/room_auth.ex`

- **`GET /health` が稼働中のルーム ID 一覧を返す** `-1`（前回から継続）
  > `room_ids: Enum.map(rooms, &to_string/1)`（`network/router.ex:100-104`）。無認証の死活エンドポイントからワールド名を偵察できる。
  > **改善方針**: 件数のみ返す。
  > 対象ファイル: `world-server/apps/network/lib/network/router.ex`

- **S2S クライアントが平文 HTTP を許容** `-1`（前回から継続）
  > `fetch_worlds/2` は peer URL のスキームを検査しない（`network/s2s/client.ex:15-22`、moduledoc の例も `http://`）。
  > **改善方針**: prod では `https://` 以外を拒否する。
  > 対象ファイル: `world-server/apps/network/lib/network/s2s/client.ex`

**apps/network 小計: -19**

---

## world-server — apps/server

- **`RoomSupervisor` が再起動すると `:main` ルームが復元されない** `-2`（新規）
  > `:main` ルームは `Supervisor.start_link` の**後**に `Core.RoomSupervisor.start_room(:main)` を 1 回呼んで作られる（`server/application.ex:35-43`）。`Core.RoomSupervisor`（`DynamicSupervisor`、既定の再起動強度）が上限を超えて落ちると `Server.Supervisor` が空の状態で再起動するが、`:main` を作り直す経路がない。上記の「catch-all 欠如」と組み合わせると、リモートから数メッセージで `:main` が恒久的に消える。
  > **改善方針**: `:main` の起動を Supervisor 子（`Task` か専用の `RoomBootstrapper`）にして、`RoomSupervisor` と `rest_for_one` で結ぶ。
  > 対象ファイル: `world-server/apps/server/lib/server/application.ex`

- **release 定義がない** `-2`（前回から継続）
  > ルート `mix.exs` と `apps/server/mix.exs` のいずれにも `releases:` がなく、配布・デーモン化は `mix run --no-halt` のみ。`auth-server` は `releases` と Dockerfile を持つ（`auth-server/mix.exs` の `releases/0`）。
  > **改善方針**: `releases: [world_server: [applications: [server: :permanent, ...]]]` と multi-stage Dockerfile を足す。
  > 対象ファイル: `world-server/mix.exs`, `world-server/apps/server/mix.exs`

- **専用テストがゼロ** `-1`（前回から継続）
  > `apps/server/test/` が存在しない。起動シーケンスの fail-fast も、上記の `:main` 非復元も検証されていない。
  > **改善方針**: `RoomSupervisor` を kill して `:main` が戻ることを見る smoke test を 1 本書く。
  > 対象ファイル: `world-server/apps/server/`

- **`Application.start` で `System.put_env("ASSETS_ID", ...)` を設定している** `-1`（新規）
  > サーバ起動時にプロセス環境変数 `ASSETS_ID` を書き換える（`server/application.ex:15-18`）。クライアントが別プロセス・別リポジトリに分離された現在、この環境変数を読む同一プロセス内の利用者は見当たらず、グローバルな副作用だけが残っている。
  > **改善方針**: 削除するか、クライアントに伝えるなら RenderFrame / ClientInfo の応答に載せる。
  > 対象ファイル: `world-server/apps/server/lib/server/application.ex`

**apps/server 小計: -6**

---

## world-server — rust/nif（Formula VM。physics は撤去済みのため評価対象外）

- **通常スケジューラ NIF に命令数・入力サイズの上限がない** `-3`（前回から継続）
  > `decode_bytecode` は EOF まで無制限に命令を積み（`rust/nif/src/formula/decode.rs:53-171`）、`run_formula_bytecode` は `#[rustler::nif]` のみで `schedule = "DirtyCpu"` を指定していない（`rust/nif/src/nif/formula_nif.rs:26`）。ユーザー作成ルールを動かす VM として、巨大バイトコード 1 本で BEAM の通常スケジューラを専有できる。今回 `cargo test -p nif` は 6 件 pass を確認したが、この経路のテストはない。
  > **改善方針**: バイトコード長・命令数の上限を decode で検査し、`schedule = "DirtyCpu"` を付ける。制御フロー命令を足す前に gas メータリングを入れる。
  > 対象ファイル: `world-server/rust/nif/src/formula/decode.rs`, `world-server/rust/nif/src/nif/formula_nif.rs`

- **入力エラーの返し方が経路によって例外とタプルに割れる** `-1`（前回から継続、前回まとめ -2 から減点幅を縮小）
  > inputs の整数範囲外だけは `{:error, :integer_out_of_range, v}` タプルを返し、それ以外の inputs 不正と store_values の不正（同じ整数範囲外を含む）は `rustler::Error::Term` で例外になる（`formula_nif.rs:33-67`）。同じ「入力値が範囲外」が引数によって形を変える。
  > **改善方針**: 呼び出し側の誤用（型違い）は例外、データ由来の不正は全部タプル、と線を引き直す。
  > 対象ファイル: `world-server/rust/nif/src/nif/formula_nif.rs`

- **Rust テストが除算に偏っている** `-1`（前回から継続）
  > `#[test]` は `vm.rs` の 6 件のみで、すべて除算まわり。`decode_bytecode` の境界（途中終端・未知 opcode・UTF-8 不正）は Rust 側で検証されていない。
  > **改善方針**: decode の境界テストと `cargo fuzz` ターゲットを 1 つ足す。
  > 対象ファイル: `world-server/rust/nif/src/formula/decode.rs`

- **撤去前のパス表記と不要な分岐が残る** `-1`（新規）
  > `formula_nif.rs:1` と `decode.rs:1` は `Path: native/nif/src/...` と旧パスを名乗り、`lib.rs:3-4` は存在しない `native/nif/src/physics` を参照する。`lib.rs:14-15` の `not(feature = "umbrella")` 分岐は存在しない `Elixir.App.NifBridge` に登録する。
  > **改善方針**: 削除・更新する。
  > 対象ファイル: `world-server/rust/nif/src/lib.rs`, `world-server/rust/nif/src/nif/formula_nif.rs`

**rust/nif 小計: -6**

---

## client（Rust クライアント）

### client/shared

- **クライアント側予測がスケルトンのまま** `-2`（前回から継続）
  > `predict_input` は入力をそのまま返す（`client/shared/src/predict.rs:11-13`）。権威 20Hz + 補間遅延 80〜250ms で、自機操作に 100ms 超の体感遅延が乗る。
  > **改善方針**: 自機だけローカル予測し、権威スナップショットで再適用（reconciliation）する。
  > 対象ファイル: `client/shared/src/predict.rs`

- **補間の対応付けが安定 ID でなく最近傍** `-2`（前回から継続）
  > `MAX_MATCH_DISTANCE = 3.0` の近傍で突き合わせる（`client/shared/src/interp.rs:41`）。ID のないプロトコル上では最善手だが、高速・高密度・テレポートで誤対応が原理的に避けられない。
  > **改善方針**: DrawCommand に `entity_id` を足し、あれば ID・なければ近傍の段階移行にする。
  > 対象ファイル: `client/shared/src/interp.rs`, `protocol/proto/render_frame/draw_commands.proto`

- **`RenderFrame` を毎フレーム丸ごと clone する** `-1`（前回から継続）
  > `sample()` は `f.clone()` か新規生成を返す（`interp.rs:581-616`）。commands / mesh_definitions / ui を含む構造体を 60fps で複製する。
  > **改善方針**: `Arc<RenderFrame>` で共有し、補間結果だけ新規に作る。
  > 対象ファイル: `client/shared/src/interp.rs`

### client/network

- **WASM トランスポートが全メソッド未実装のスタブ** `-2`（前回から継続）
  > `platform/web.rs:6-29` はすべて「未実装」を返し、`spawn_subscriber` は空スレッドを返す。
  > **改善方針**: 当面やらないなら `cfg` ごと外し、ロードマップ側に置く。
  > 対象ファイル: `client/network/src/platform/web.rs`

- **トランスポートのクレートが描画・オーディオに依存する** `-1`（前回から継続）
  > `network/Cargo.toml:8-9` が `audio` と `render` に依存し、`protobuf_render_frame.rs:3` は `render::decode_pb_render_frame` の再エクスポートである。
  > **改善方針**: `RenderFrame` 型を `shared` か `render_frame_proto` に寄せる。
  > 対象ファイル: `client/network/Cargo.toml`

- **セッションエラーの判定が文字列の部分一致** `-1`（新規）
  > `put_drop` は `e.contains("session closed")` でエラーを握りつぶし（`platform/desktop.rs:74-78`）、`publish` は `looks_like_session_error(&e)` で再接続判定する（`:166-171`）。エラー型が `String` のため、文言変更で回復経路が静かに壊れる。
  > **改善方針**: `enum SessionError { Closed, Put(..), Declare(..) }` を定義する。
  > 対象ファイル: `client/network/src/platform/desktop.rs`

- **移動入力を描画フレームごとに無条件 publish する** `-1`（新規）
  > `next_frame()` は毎回 `publish_movement(dx, dy)` を呼ぶ（`network_render_bridge.rs:185-193`）。入力が変わっていなくても、静止中でも 60 回/秒送る。サーバの権威 tick（20Hz）の 3 倍で、1000 人規模なら上りだけで 6 万メッセージ/秒になる。
  > **改善方針**: 変化時 + 権威 tick 間隔のハートビートだけ送る。
  > 対象ファイル: `client/network/src/network_render_bridge.rs`

### client/render

- **`render` クレートの回帰テストがゼロ** `-2`（前回から継続）
  > 2,900 行超のクレートに `#[test]` が 1 件もない。`headless.rs:382` に `render_frame_offscreen` があるのに golden image 比較がない。
  > **改善方針**: headless 出力のハッシュ比較を 1 本書く。
  > 対象ファイル: `client/render/`

- **フラスタム・距離カリングがない** `-1`（前回から継続）
  > GPU のバックフェイスカリングのみで、CPU 側の可視判定がない（`render/src/renderer/pipeline_3d/mod.rs`）。
  > **改善方針**: `Camera3D` の視錐台で DrawCommand を前段で間引く。
  > 対象ファイル: `client/render/src/renderer/pipeline_3d/mod.rs`

### client/audio

- **SE の同時再生数に上限がない** `-1`（前回から継続）
  > `play_se_with_volume` は呼び出しごとに `Sink::connect_new` + `detach()`（`client/audio/src/audio.rs:57-60`）。弾幕で被弾が連続すると Sink が際限なく増える。
  > **改善方針**: ボイスプール（例: 32）と優先度で古いものを止める。
  > 対象ファイル: `client/audio/src/audio.rs`

### client/app（統合）・CI

- **OpenXR が出荷 app へ未配線** `-4`（前回から継続）
  > `app/Cargo.toml:19` は `xr` に依存するが、`app/src/main.rs` に `xr` の参照はない。`xr/Cargo.toml:7-9` で `default = []`・`openxr` は optional。`openxr_loop.rs:23-28` は `XR_MND_headless` を必須とし、非対応ランタイムでは即 `Err`。「VRAlchemy」を名乗るバイナリ（`app/Cargo.toml:8`）で VR が起動しない。
  > **改善方針**: app に `--xr` フラグで入る経路を作り、`openxr` feature を既定にする。`XR_MND_headless` がなければ通常のグラフィックスバインディングでセッションを張る。
  > 対象ファイル: `client/app/src/main.rs`, `client/xr/Cargo.toml`, `client/xr/src/openxr_loop.rs`

- **クライアントの 52 テストが CI で一度も実行されない** `-3`（前回から継続、リポジトリ分割後も未解消）
  > 分離後の `client/.github/workflows/ci.yml` は `cargo fmt --check` / `cargo clippy --workspace -- -D warnings` / `cargo build -p app` だけで、`cargo test` がない。`clippy` も `--all-targets` なしなのでテストコードはコンパイルすらされない。実在する `#[test]` は 52 件（shared 18 / system_ui 16 / auth_client 8 / network 6 / render_frame_proto 2 / audio 2）。今回、別 target ディレクトリで `cargo test -p shared`（18 pass）と `cargo test -p network --test render_frame_e2e_contract`（1 pass）を実行して通ることは確認した。通るテストがあるのに CI が使っていない。分割は「CI を最初から書き直す」好機だったが、その機会に入らなかった。
  > **改善方針**: `cargo test --workspace` と `cargo clippy --workspace --all-targets` を 1 行ずつ足す。
  > 対象ファイル: `client/.github/workflows/ci.yml`

**client 小計: -21**（shared -5 / network -5 / render -3 / window 0 / audio -1 / app・CI -7）

---

## auth-server

### auth-server/lib/auth

- **メール未検証でも JWT を発行する** `-2`（前回から継続）
  > `login/3` は `pw_verified and user.status == :active` のみを見る（`auth-server/lib/auth/accounts.ex:56-68`）。検証フロー自体は丁寧に作られている（`:157-177`）が、ゲートとしてどこにも効いていない。
  > **改善方針**: 未検証ユーザーは `email_verified: false` を claims に入れて world-server 側で入室を制限するか、ログインを拒否する。
  > 対象ファイル: `auth-server/lib/auth/accounts.ex`

- **リフレッシュトークンのローテーションに競合がある** `-2`（新規）
  > `refresh/1` はトランザクションの**外**でロックなしにレコードを読み（`accounts.ex:114-118`, `get_refresh_token_record/1` は `:360-362`）、`do_refresh/2` 内の `ensure_refresh_token_usable/2` はその古いスナップショットの `revoked_at` を見る（`:307-310,364-372`）。`RefreshToken.revoke` の update は `revoked_at IS NULL` を条件にしない（`accounts/refresh_token.ex:75-77`）。同じ refresh token で 2 リクエストが同時に来ると、両方が「未失効」と判定して両方ローテーションに成功し、同じ family に生きたトークンが 2 本できる。family 再利用検知（プラス側で評価）を通り抜ける経路である。`auth-server/lib/auth/accounts.ex:462-464` の `AccountToken` 側は `FOR UPDATE` を使っているので、同じ手当てが refresh 側だけ抜けている。
  > **改善方針**: `do_refresh` のトランザクション内で `Ash.Query.lock("FOR UPDATE")` 付きで読み直すか、`revoke` を `revoked_at IS NULL` 条件付きの原子的 update にして影響行数 0 なら失敗にする。
  > 対象ファイル: `auth-server/lib/auth/accounts.ex`, `auth-server/lib/auth/accounts/refresh_token.ex`

- **最低年齢ポリシーがない** `-1`（前回から継続）
  > `BirthdayInPast` は未来日付を拒否するだけ（`accounts/validations/birthday_in_past.ex:14-19`）。
  > **改善方針**: 設定可能な最低年齢（例: 13）を検証に足す。
  > 対象ファイル: `auth-server/lib/auth/accounts/validations/birthday_in_past.ex`

- **`account_tokens` が GC されない** `-1`（前回から継続）
  > `TokenCleanup` は `token_revocations` と `refresh_tokens` のみ削除する（`auth/token_cleanup.ex:62-97`）。
  > **改善方針**: `used_at` 済み・期限切れの `account_tokens` を同じ周期で削除する。
  > 対象ファイル: `auth-server/lib/auth/token_cleanup.ex`

- **レート制限が単一ノード ETS** `-1`（前回から継続）
  > `:auth_rate_limit` の named ETS（`auth/rate_limit.ex:10,54-60`）。水平スケール時にバケットが共有されない。
  > **改善方針**: Postgres の upsert カウンタか `Hammer` + Redis バックエンドに差し替え可能にする。
  > 対象ファイル: `auth-server/lib/auth/rate_limit.ex`

- **Dialyzer・依存監査がない** `-1`（前回から継続）
  > `auth-server/mix.exs` の deps に `dialyxir` / `mix_audit` がなく、CI（`auth-server/.github/workflows/ci.yml`）も format / compile / credo / test まで。
  > **改善方針**: `mix hex.audit` と `mix deps.audit` を CI に足す。
  > 対象ファイル: `auth-server/mix.exs`

### auth-server/lib/auth_web

- **`/health` が DB の疎通を見ない** `-1`（前回から継続）
  > `status / service / version` を返すだけ（`auth_web/controllers/health_controller.ex:6-12`）。
  > **改善方針**: `/health/ready` で `Repo.query("SELECT 1")` を見る。
  > 対象ファイル: `auth-server/lib/auth_web/controllers/health_controller.ex`

- **CORS の allowlist がない** `-1`（前回から継続）
  > `endpoint.ex:44-52` に CORS plug がない。SPA・管理画面を足した時点でプリフライトが通らない。
  > **改善方針**: `Corsica` で allowlist を設定する。
  > 対象ファイル: `auth-server/lib/auth_web/endpoint.ex`

- **API 専用サービスに LiveView socket と cookie セッションが残る** `-1`（新規）
  > `socket "/live", Phoenix.LiveView.Socket`（`endpoint.ex:14-16`）と `Plug.Session`（`:51`）が、JSON API しか持たないルータ（`auth_web/router.ex:4-40`）の前に常に挟まる。dev 用 LiveDashboard のための雛形だが、prod でも攻撃面と処理が残る。
  > **改善方針**: `dev_routes` が有効なときだけ socket と session を有効にする。
  > 対象ファイル: `auth-server/lib/auth_web/endpoint.ex`

**auth-server 小計: -11**（lib/auth -8 / lib/auth_web -3）

---

## 横断評価層

### テスト戦略

- **プロパティベース・fuzz・ベンチマークが全体に不在** `-2`（前回から継続）
  > `world-server/mix.lock` に StreamData / benchee がなく（確認済み）、`client` と `world-server/rust` に proptest / criterion / `benches/` がない。バイトコード VM・バイナリ UDP プロトコル・グラフコンパイラ・スナップショット補間という、ランダム入力と時間軸に晒される層を 4 つ持つ構成に対し、例示テストだけでは防御が薄い。
  > **改善方針**: `SnapshotInterpolator` に proptest、`Network.UDP.Protocol.decode/1` と `Core.FormulaGraph` に StreamData、`decode_bytecode` に `cargo fuzz`。
  > 対象ファイル: `world-server/mix.lock`, `client/Cargo.toml`

### 可観測性

- **telemetry が `ConsoleReporter` 止まりで、新しい層にイベントがない** `-2`（前回から継続）
  > `Core.Telemetry` の reporter は `ConsoleReporter` のみ（`core/telemetry.ex:12-14`）。`world-server` の `:telemetry.execute` はフレームドロップなど少数で（`events/game.ex:337`）、JWKS 検証・S2S 取得・UDP セッション淘汰・Zenoh の publish 失敗には何もない。auth-server は LiveDashboard を持つが world-server にはない。
  > **改善方針**: `TelemetryMetricsPrometheus` か OpenTelemetry exporter を足し、認証・ネットワークの失敗をイベント化する。
  > 対象ファイル: `world-server/apps/core/lib/core/telemetry.ex`

### 変更容易性・保守性

- **保証文書・README がリポジトリ分割に追従していない** `-3`（前回から継続・範囲拡大）
  > `.workspace/0_docs/warranty/ci.md:10,13` は依然 `cargo test -p physics` と `cargo bench -p physics`（+10% でブロック）を掲載し、`:46` は `CyclomaticComplexity` を 15 と書くが `world-server/.credo.exs` は 10、`:48` は `AliasUsage` を 3 回以上と書くが実際は無効化。ci.md はスーパープロジェクトに移ったのに、client と auth-server の CI に触れていない。`world-server/README.md:94` も「main のみ `cargo bench` のリグレッション検知」と書く。さらに `world-server/README.md:8,41,50,58,96` は `.workspace/...` へ相対リンクしているが、`.workspace/` はスーパープロジェクトに移っており `world-server/` 内には存在しない（リンク切れ）。評価ルール自体も、技術層の説明に「SoA・SIMD・空間ハッシュ・ARM NEON」を持つ `rust/nif/physics` を残している（`.cursor/rules/evaluation.mdc:52-56`）。
  > **改善方針**: ci.md を「リポジトリごとの CI 表」に書き直し、各 submodule の README のリンクを GitHub の絶対 URL にする。CI を変える PR では ci.md も同時に変える、を PR テンプレートに入れる。
  > 対象ファイル: `.workspace/0_docs/warranty/ci.md`, `world-server/README.md`, `.cursor/rules/evaluation.mdc`

- **分割の残骸（コミットされた CI 出力・不要な apt パッケージ）** `-1`（新規）
  > `world-server/ci_output.txt`（git 管理下、9 月 24 日付）は現行の `mix alchemy.ci` にない `[PASS] mix compile` ステップを含む古い出力である。`world-server/.github/actions/alchemy-ci-setup/action.yml` は「`auth_client` の keyring に必要」として `libasound2-dev libdbus-1-dev` を毎ジョブ入れるが、`auth_client` を含むクライアントクレートは `world-server` から抜けている（`world-server/rust/Cargo.toml` の members は `nif` のみ）。
  > **改善方針**: `ci_output.txt` を削除して `.gitignore` に入れ、apt の依存を外す。
  > 対象ファイル: `world-server/ci_output.txt`, `world-server/.github/actions/alchemy-ci-setup/action.yml`

### 開発者体験（DX）

- **ローカル CI の単一エントリが world-server にしかない** `-2`（新規）
  > `mix alchemy.ci` は `world-server` の Rust（`nif` のみ）と Elixir を回す（`core/lib/mix/tasks/alchemy.ci.ex:26-55,93-107`）。client と auth-server には同等の 1 コマンドがなく、スーパープロジェクトにも全体を回す入口がない。評価ルールが前提とする「`mix alchemy.ci` がエラーゼロで通れば品質が担保される」は、分割後は全体の 1/3 しか見ていない。
  > **改善方針**: スーパープロジェクトに `bin/ci.bat` + `bin/ci.sh`（または `mix` を持たない前提で `just ci`）を置き、3 リポジトリの CI 相当を順に回す。
  > 対象ファイル: `world-server/apps/core/lib/mix/tasks/alchemy.ci.ex`, `bin/`

- **起動手順が Windows の `.bat` 前提** `-1`（新規）
  > スーパープロジェクトの入口は `bin/*.bat` 5 本（`bin/README.md`）で、README は「他 OS は手動手順」とする（`README.md` の前提条件表）。CI はすべて Linux で回っているのに、開発の入口は Windows 専用という逆転がある。
  > **改善方針**: 同じ内容の `bin/*.sh` を足すか、Rust 製の小さなランチャー（README が言及する `alchemy-launcher`）を作る。
  > 対象ファイル: `bin/`

### セキュリティ・配布可能性

- **公式クライアントが RoomToken を取得も付与もしないため、認証を有効にすると遊べない** `-3`（新規）
  > `NetworkRenderBridge` は movement / action / client_info を生の protobuf で put するだけで（`client/network/src/network_render_bridge.rs:125-166`）、`/api/room_token` を呼ぶコードも `RoomAuth.wrap_payload/2` 相当の封筒を作るコードもクライアント全体に存在しない（`client/network/src` を `token` で検索して該当なし）。`auth_client` でログインして JWT を得ても、それを world-server の入室に使う経路がない。`AUTH_REQUIRED=true` にすると `RoomAuth.unwrap_payload/2` が `:missing_token` で全入力を拒否するため（`world-server/apps/network/lib/network/room_auth.ex:55-56`）、**公式クライアントで認証付きサーバに入る方法がない**。`AUTH_REQUIRED` の既定が false のまま動かない理由の一つはこれだと読める。auth-server と world-server 側の検証器はそれぞれ良くできているのに、端から端まで繋がっていない。
  > **改善方針**: client に「`auth_client` の access token → `POST /api/room_token` → 以後の put を封筒化」の 1 経路を足し、`AUTH_REQUIRED=true` で起動したサーバに対する結合テストを置く。
  > 対象ファイル: `client/network/src/network_render_bridge.rs`, `world-server/apps/network/lib/network/room_auth.ex`

- **依存の脆弱性監査が 4 リポジトリのどこにもない** `-2`（前回から継続・範囲拡大）
  > `dependabot.yml` は `world-server` / `client` / `auth-server` / `protocol` のいずれにもなく、CI に `cargo audit` / `cargo deny` / `mix hex.audit` / `mix deps.audit` もない。zenoh 1.9・wgpu 24・rustls・Ash・Phoenix と更新の速い依存を抱える。
  > **改善方針**: 4 リポジトリに dependabot を置き、Rust 側は `cargo deny check advisories`、Elixir 側は `mix hex.audit` を CI に足す。
  > 対象ファイル: `world-server/.github/workflows/ci.yml`, `client/.github/workflows/ci.yml`, `auth-server/.github/workflows/ci.yml`

- **CI が Linux 単一 OS で、配布形態がない** `-2`（前回から継続）
  > 3 リポジトリの CI はすべて `runs-on: ubuntu-latest`。クライアントは Windows（`main.rs:4` の `windows_subsystem`）・macOS Keychain・Linux Secret Service の分岐を持つのに、Linux 以外で一度もビルドされない。インストーラ・署名・自動更新もない。
  > **改善方針**: client の CI に `windows-latest` と `macos-latest` のビルドを足し、`cargo-dist` 等でリリース成果物を作る。
  > 対象ファイル: `client/.github/workflows/ci.yml`

### プロジェクト全体設計（ゲームプレイ完成度）

- **完結したゲームは 2 本、残り 3 本は技術デモ** `-3`（前回から継続）
  > 開始 → プレイ → 終了 → リトライが閉じているのは `Content.Tetris`（`title.ex` / `playing.ex` / `game_over.ex`）と `Content.BulletHell3D`（`playing.ex` / `game_over.ex`）。`BulletHell3D` はタイトルなしで起動即プレイ、敵 1 種、プレイヤーの攻撃手段なし（`bullet_hell_3d.ex:8-14`）。既定コンテンツは OSC サンプル（`config.exs:90`）。
  > **改善方針**: `BulletHell3D` にタイトル・攻撃・敵 2 種を足し、既定にする。
  > 対象ファイル: `world-server/apps/contents/lib/contents/bullet_hell_3d/`

- **視覚・音響アセットが極薄** `-2`（前回から継続）
  > `client/assets/` は音声 6 ファイルと `sprites/atlas.png` 1 枚で、`mini_shooter/` と `vampire_survivor/` は `.gitkeep` のみ。
  > **改善方針**: CC0 アセットで BulletHell3D 用の最小セットを揃える。
  > 対象ファイル: `client/assets/`

**横断評価層 小計: -23**

---

## 総計

| 大分類 | 項目数 | マイナス小計 |
|:---|:---:|:---:|
| プロジェクト全体（アーキテクチャ・ビジョン） | 5 | -13 |
| world-server — apps/contents | 12 | -26 |
| world-server — apps/core | 4 | -6 |
| world-server — apps/network | 9 | -19 |
| world-server — apps/server | 4 | -6 |
| world-server — rust/nif | 4 | -6 |
| client（shared / network / render / window / audio / app） | 12 | -21 |
| auth-server（lib/auth / lib/auth_web） | 9 | -11 |
| 横断評価層 | 11 | -23 |
| **マイナス合計** | **70** | **-131** |

**新規検出のうち重いもの**: `"__quit__"` によるサーバ停止（-4）、binary64 の主張とワイヤの矛盾（-4）、`Events.Game` の catch-all 欠如（-3）、リポジトリ横断検証の不在（-3）、クライアントの RoomToken 未配線（-3）、`:main` の非復元（-2）、refresh の競合（-2）。いずれも今回のリポジトリ分割より前から存在した欠陥（binary64 は文言側が今回変わった）で、前回の第1評価者が見落としていたものである。
