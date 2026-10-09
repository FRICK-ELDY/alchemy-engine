# Opus 評価 — 提案（0点）詳細一覧

評価日: 2026-08-25 / 評価者: Claude Opus 5（第1評価者）
検証対象コミット: engine `8f35a57`（main、作業ツリークリーン）

ここに挙げるのは「現時点では存在しないが、実装すればプロジェクトの価値を高める」項目である。批判ではなく次のステップとして記述する。したがって加点も減点もしない。
既にマイナス点として計上した欠如（CI のクライアント Rust テスト未実行、リリース定義の不在、依存脆弱性監査、可観測性の乖離、`predict` 未配線など）は改善方針をマイナス点文書側に書いたため、ここでは重複させず、その次の段に来る提案を挙げる。

## 採点基準

| 点数 | 基準 |
|:---:|:---|
| 0 | 現時点では存在しないが、実装すればプロジェクトの価値を高める提案 |

---

## テスト・検証

- **決定論的リプレイ基盤（入力ログの記録と再生）** `0`
  > 権威 tick が Elixir、入力が `{:move_input, ...}` / `{:ui_action, ...}` に正規化済み（`apps/network/lib/network/channel.ex:122-124`）、ゲームロジックが dt ベース（`apps/contents/lib/events/game.ex:575-581`）という 3 条件が揃っているため、「入力列 + 初期シードを保存して再生すれば同じ結果になる」土台はすでにある。ここにリプレイを載せると 3 つの価値が同時に立つ。(1) バグ再現がリプレイファイル 1 個で済む、(2) 回帰テストとして「既知のリプレイを流して最終状態のハッシュを比較」という高カバレッジのテストが 1 本で書ける、(3) 将来チート検出やハイライト共有の基盤になる。実装イメージ: `Contents.Events.Game` の入力受理点で `{frame_count, input}` を追記し、リプレイモードでは Zenoh / UDP の代わりにログから供給する。参考: Rocket League / Dota 2 のリプレイ、`quake3` の demo 形式。
  > 対象ファイル: `engine/apps/contents/lib/events/game.ex`

- **E2E スモークテスト（zenohd + server + ヘッドレスクライアント）** `0`
  > 現在のテストは Elixir 側 180 件・Rust 側 58 件がすべてプロセス内で完結しており、「3 プロセスを起動して実際に 1 フレーム往復する」経路を検証するものがない。`README.md:81` が「zenohd + サーバー + VRAlchemy の 3 プロセスが必要」と書いているとおり、実行時構成の破綻（Zenoh キーの不一致、protobuf のフィールド番号ずれ、`ASSETS_ID` の未設定）は単体テストをすべて通り抜ける。`render` クレートに feature `headless` のオフスクリーン描画があり（`rust/client/render/src/headless.rs:1-16`）、`mix alchemy.router` で zenohd を起動できるので、部品は揃っている。実装イメージ: CI ジョブで zenohd → `mix run --no-halt` → ヘッドレスクライアントを起動し、1 フレーム受信して DrawCommand 数が 0 でないことを確認して終了。5 分以内に収まる。
  > 対象ファイル: `engine/rust/client/render/src/headless.rs`, `engine/apps/core/lib/mix/tasks/alchemy.router.ex`

- **Formula の純 Elixir 参照インタプリタによる differential testing** `0`
  > OpCode 0–13 は Elixir 側（`apps/core/lib/core/formula.ex:13-20`）と Rust 側（`rust/nif/src/formula/opcode.rs:7-36`）で同じ意味に固定されている。同じ意味論を Elixir で素朴に実装した参照インタプリタを 200 行程度書けば、「同じバイトコードと入力に対して Rust VM と参照実装が同じ結果を返す」という差分テストが書ける。型昇格（`I32/I32` のみ整数除算、それ以外は f32 昇格）や `f32::EPSILON` 比較といった、仕様が微妙で回帰しやすい箇所（`rust/nif/src/formula/vm.rs:123-196`）を機械的に守れるようになる。NIF ビルドなしで Formula の意味論を確認できる副産物もある。参考: WebAssembly の spec interpreter、SQLite の SQL Logic Test。
  > 対象ファイル: `engine/apps/core/lib/core/formula.ex`, `engine/rust/nif/src/formula/vm.rs`

- **`cargo-fuzz` による decode 系のファジング** `0`
  > 外部から任意のバイト列を受ける入口が 3 つある。Formula バイトコードの `decode_bytecode`（`rust/nif/src/formula/decode.rs:53-170`）、UDP パケットの `Protocol.decode`（`apps/network/lib/network/udp/protocol.ex:39-47`）、protobuf の `decode_pb_render_frame`（`rust/client/render_frame_proto/src/protobuf_render_frame/mod.rs`）。いずれも現状は example-based テストのみである。Rust 側 2 つは `cargo-fuzz` のターゲットを 20 行書けば回り始め、`DecodeError` を返す以外の結果（panic / 無限ループ / メモリ膨張）が出ないことをコーパスで確認できる。Elixir 側は同じ入力コーパスを流す ExUnit テストで代替できる。
  > 対象ファイル: `engine/rust/nif/src/formula/decode.rs`, `engine/rust/client/render_frame_proto/src/`

---

## ネットワーク

- **QUIC / WebTransport への移行検討** `0`
  > 現在の UDP 経路は断片化・再送・順序制御を持たない（`apps/network/lib/network/udp/protocol.ex:113-117,169-173`）。これを自作すると、輻輳制御・MTU 探索・パス検証まで含めて相当量の実装とテストが必要になる。一方 QUIC の datagram 拡張（RFC 9221）を使えば、暗号化・パス検証・輻輳制御を既製のスタックに任せたまま「信頼性なしの低遅延データグラム」を得られ、WebTransport 経由でブラウザからも同じ経路に乗れる。`platform/web.rs` が未実装スタブになっている問題（`rust/client/network/src/platform/web.rs:1-29`）に対しても、Zenoh over WebSocket を自作するより現実的な解になりうる。実装イメージ: Elixir 側は `quicer`、Rust 側は `quinn`。まず既存 UDP と並列に 1 経路として足し、比較してから寄せる。
  > 対象ファイル: `engine/apps/network/lib/network/udp/protocol.ex`, `engine/rust/client/network/src/platform/web.rs`

- **RenderFrame の差分送信と AOI（Area of Interest）** `0`
  > 現在は毎 tick フル `RenderFrame` を送っている。「1000 人規模のプレイヤーが交差する大規模ネットワーク」（`README.md:46`）を目標に置くなら、送信量は参加者数 × エンティティ数で二乗的に伸びるため、どこかで差分化と関心領域の絞り込みが必要になる。順序としては AOI（各クライアントの視界・距離でエンティティを選別）が先で、これはサーバが DrawCommand を生成している現構造（`apps/contents/lib/contents/frame_encoder.ex:37-48`）ならクライアント改修なしに導入できる。差分化はその後、`seq` を使った ack ベースのベースライン管理として載せる。参考: Overwatch の GDC 講演、Valve の Source Engine の snapshot delta。
  > 対象ファイル: `engine/apps/contents/lib/contents/frame_encoder.ex`

- **予測 → 照合 → ロールバックの段階導入** `0`
  > 補間が入った今（`rust/client/shared/src/interp.rs`）、次の段は自機の予測とサーバ照合である。予測の未配線自体はマイナス側に計上したが、その先の設計として「入力に `seq` を付けてサーバが ack を返し、乖離が閾値を超えたときだけ位置を補正する」段階と、「ロールバック + 再シミュレーション」の段階を分けて計画しておく価値がある。前者はサーバ改修が `seq` の反射だけで済み、後者は決定論的リプレイ基盤（上記）と同じ仕組みを必要とする。この 2 つを別タスクとして順序づけておくと、VR で効く体感遅延を段階的に削れる。
  > 対象ファイル: `engine/rust/client/shared/src/predict.rs`

---

## Formula / コンテンツ

- **制御フロー命令と gas メータリング** `0`
  > 現在の OpCode は算術・比較・入出力・Store の 14 種で、分岐もループもない（`rust/nif/src/formula/opcode.rs:7-36`）。「ユーザーがルールを書く」ことを目指すなら条件分岐は避けられない。ここで重要なのは順序で、分岐を入れると停止性が失われるため、命令実行数の上限（gas）と `DirtyCpu` 指定を先に入れる必要がある（この 2 つの欠如はマイナス側に計上した）。gas を先に入れてから `Jump` / `JumpIfFalse` を足せば、ユーザーコンテンツの実行時間を上限付きで保証したまま表現力を上げられる。参考: EVM の gas、Lua の instruction hook、Wasm の fuel（wasmtime）。
  > 対象ファイル: `engine/rust/nif/src/formula/opcode.rs`, `engine/rust/nif/src/formula/decode.rs`

- **ノードグラフのビジュアルエディタ** `0`
  > `Core.FormulaGraph` がグラフ → バイトコードのコンパイラを持ち（`apps/core/lib/core/formula_graph.ex:139,198-200`）、`nodes/` に 20 種のノード実装がある（`apps/contents/lib/nodes/`）。一方でグラフを組む手段はコードのみで、ビジュアル編集はない。クライアントには egui ベースの `system_ui` クレート（1237 行、16 テスト）があるので、ノードエディタを載せる土台はすでに手元にある。実装イメージ: `egui_snarl` などのノードエディタ crate でグラフを編集し、JSON として `assets` サービスに保存、engine 側が `FormulaGraph` に流す。「A platform for worlds. You bring the rules.」という看板に対して、ルールを持ち込む手段が GUI で存在することの意味は大きい。
  > 対象ファイル: `engine/apps/core/lib/core/formula_graph.ex`, `engine/rust/client/system_ui/`

- **コンテンツの外部化とホットリロード** `0`
  > 現在コンテンツは umbrella 内の `apps/contents/lib/contents/` にコンパイル時に同居し、切り替えは `config :server, :current` の再起動を伴う（`config/config.exs:90`）。コンテンツ交換可能性は 5 実装で実証済みなので（プラス点参照）、次は「エンジンをビルドせずにコンテンツを差し込める」段に進める価値がある。Elixir なら別 OTP アプリとして動的ロードする、あるいは `Contents.Behaviour.Content` を満たすモジュールを実行時にコード読み込みする形が取れる。開発中のイテレーション速度が直接上がるほか、「他人が作ったワールドを自分のインスタンスに置く」という連合構想の前提にもなる。
  > 対象ファイル: `engine/apps/contents/lib/behaviour/content.ex`

---

## 描画・クライアント

- **サーバ側フラスタムカリングと LOD** `0`
  > DrawCommand をサーバが生成している構造（`apps/contents/lib/contents/frame_encoder.ex:37-48`）は、カリングをサーバ側で行えるという他エンジンにない利点を持つ。クライアント側で捨てる前に送らない判断ができるため、GPU 負荷と帯域の両方が同時に下がる。カメラパラメータはすでに `CameraParams` として送信対象に含まれている（`rust/client/shared/src/render_frame/mod.rs`）ので、サーバはクライアントごとの視錐台を知る手段を持っている。距離による LOD（遠方は `Box3D` を簡略メッシュに置換）も同じ判定点に載せられる。
  > 対象ファイル: `engine/apps/contents/lib/contents/frame_encoder.ex`

- **入力抽象の統合（`XrInputEvent` と `KeyState` / `MouseMotion`）** `0`
  > デスクトップ入力は `window` クレートで `KeyState` などに正規化され（`rust/client/window/src/desktop_loop.rs:193-198`）、XR 入力は `xr` クレートの `XrInputEvent`（HeadPose / ControllerPose / ControllerButton / TrackerPose）として別系統で定義されている（`rust/client/xr/src/lib.rs:1-101`）。この 2 つを 1 つの入力イベント型に束ねてから `RenderBridge` に渡す層を挟むと、XR を app に配線する際にサーバ側プロトコルを触らずに済み、ゲームパッド追加時も同じ場所で済む。今のうちに型を統合しておくほど安い作業である。
  > 対象ファイル: `engine/rust/client/xr/src/lib.rs`, `engine/rust/client/window/src/desktop_loop.rs`

---

## 運用・連合

- **OpenTelemetry による分散トレーシング** `0`
  > 現在の可観測性はメトリクス（telemetry イベント 3 件 + ConsoleReporter）に寄っており、「ある入力が tick に反映されてフレームとして届くまで」を 1 本の trace として追う手段がない。engine / auth / assets の 3 サービス構成になった今、`traceparent` を Bearer トークンと同じ経路で伝播させれば、「ログインが遅い」「入室でこける」という報告を跨サービスで切り分けられる。Elixir は `opentelemetry_phoenix` / `opentelemetry_ecto`、Rust は `tracing` + `opentelemetry` で、Zenoh 経路はメッセージヘッダに trace id を載せる形になる。メトリクスの外部エクスポート（PromEx など）とは別軸の投資として価値がある。
  > 対象ファイル: `engine/apps/core/lib/core/telemetry.ex`, `auth/lib/auth_web/telemetry.ex`

- **auth の監査ログ（重要操作の追記専用記録）** `0`
  > `auth` はログイン・パスワード変更・退会・トークン失効といった重要操作を持ち、レート制限の throttle は telemetry に出る（`auth/lib/auth/rate_limit.ex:93-97`）。一方で「いつ・どの IP から・どのアカウントに何をしたか」を後から辿れる追記専用の記録はない。ユーザーへの「不審なログインがありました」通知や、インシデント時の影響範囲特定に直結する。`TokenRevocation` と同様の Ash リソースを 1 つ追加し、`TokenCleanup` と同じ形で保持期間を管理すれば実装は素直である。連合として複数運営者にサービスを配るなら、運営者が説明責任を果たすための道具でもある。
  > 対象ファイル: `auth/lib/auth/accounts.ex`

- **assets の署名付き URL とキャッシュ配信** `0`
  > 現在 BLOB は `GET /api/v1/objects/*path` が毎回 Bearer 検証を通して本体を返す形で（`assets/lib/assets_web/controllers/object_controller.ex:34-115`）、アバターやワールドのメッシュのように「サイズが大きく変更頻度が低い」データには不向きである。短命な署名付き URL を発行して本体配信は CDN / 静的サーバに任せる形にすると、認証の負荷とレイテンシを同時に下げられ、`ETag` / `Cache-Control` による差分取得も効く。`AssetMetadata` に `byte_size` / `content_type` / `uri` が既にあるので（`assets/lib/assets/inventory/asset_metadata.ex:16-66`）、必要なのは署名の発行と検証だけである。
  > 対象ファイル: `assets/lib/assets_web/controllers/object_controller.ex`

- **`.well-known` からの相互発見とインスタンス一覧** `0`
  > S2S は自己記述（`GET /.well-known/alchemy-s2s.json`）と署名付き worlds カタログまで到達した（`apps/network/lib/network/s2s/instance.ex:1-16`）。次の段として、既知インスタンスのリストを設定で持ち、定期的に `Client.fetch_worlds` して結果をキャッシュする「ディレクトリ」機能を置くと、ユーザーから見て初めて連合が体験になる（他インスタンスのワールドが一覧に並ぶ）。訪問トークンによる実際の入室はその次で、まず「見える」ところまでを 1 段として切ると、連合の価値を早く検証できる。
  > 対象ファイル: `engine/apps/network/lib/network/s2s/client.ex`, `engine/apps/network/lib/network/s2s/catalog.ex`

---

## 総計

提案項目数: **16 件**（前回 15 件）。

| 分類 | 件数 |
|:---|:---:|
| テスト・検証 | 4 |
| ネットワーク | 3 |
| Formula / コンテンツ | 3 |
| 描画・クライアント | 2 |
| 運用・連合 | 4 |

このうち費用対効果が最も高いと考える 3 件は、**決定論的リプレイ基盤**（テスト・デバッグ・将来機能の 3 方向に効く）、**E2E スモークテスト**（部品が揃っており実装が小さいのに、単体テストが構造的に見逃す種類の破綻を捕まえる）、**Formula の gas メータリング + 制御フロー**（ユーザーコンテンツ実行という価値命題の中核を、安全側から順序どおりに広げられる）である。
