# Opus 評価 — プラス点詳細一覧（2026-10-09）

評価日: 2026-10-09 / 評価者: **Claude Opus 5.5**（第1評価者・独立評価）
対象: スーパープロジェクト `alchemy-engine` と submodule `world-server` / `client` / `auth-server` / `protocol`（2026-10-09 時点の作業ツリー）

前回の自系統詳細（`opus/archive/2026-08-25/`）は「再確認すべき長所の一覧」として使い、全項目について現行ソースを開き直して残存を確認した。前回あって今回消えたもの（`assets` サービス関連の長所 +7 相当）は計上していない。リポジトリ分割で新たに生まれた長所は新規として加えた。

## 採点基準

| 点数 | 基準 |
|:---:|:---|
| +1 | 標準的な実装。特筆すべき点はないが問題もない |
| +2 | 丁寧な実装。一般的なベストプラクティスに沿っている |
| +3 | 優れた設計判断。明確な意図と効果がある |
| +4 | 卓越した実装。同規模の OSS では稀なレベル |
| +5 | 業界トップレベル。他プロジェクトの模範になりうる |

---

## プロジェクト全体（アーキテクチャ・設計判断）

- **二層 SSoT（Elixir = 権威状態、クライアント = 描画）が実装で守られている** `+3`
  > 権威 tick は `Contents.Events.Game` が持ち（`world-server/apps/contents/lib/events/game.ex:350-433`）、クライアントは `RenderFrame` を受けて補間・描画するだけ（`client/network/src/network_render_bridge.rs`）。ゲームルールが Rust 側に漏れていない。Bevy や Godot のような「ローカルエンジン + 後付けネットワーク」ではなく、最初からサーバ権威で組んでいる。
  > 対象ファイル: `world-server/apps/contents/lib/events/game.ex`, `client/network/src/network_render_bridge.rs`

- **NIF を Formula VM だけに絞り、物理・SoA・SIMD を撤去した判断** `+4`
  > `world-server/rust/Cargo.toml` の members は `nif` のみ、`lib.rs` は `formula` と `nif` の 2 モジュールだけである。NIF のクラッシュが BEAM を巻き込むリスク面を最小にし、「Elixir = SSoT」を構造で強制した。抱えていた資産を捨てる判断は難しく、同規模の OSS ではまず見ない。ビジョン側の追従漏れは別途マイナスで計上した。
  > 対象ファイル: `world-server/rust/nif/src/lib.rs`

- **層間依存を MFA の config 注入で切っている** `+3`
  > `:formula_store_broadcast` と `:zenoh_frame_publish` を `config.exs` で `{mod, fun, args}` として注入し、core / contents が network を直接呼ばない（`core/formula_store.ex:185-208`、`events/game.ex:521-546`）。テストでは差し替えられ、Zenoh を無効にしても core は動く。
  > 対象ファイル: `world-server/config/config.exs`, `world-server/apps/core/lib/core/formula_store.ex`

- **4 リポジトリ分割と `PROTOCOL_PIN` の sha 検証付き解決** `+3`（新規）
  > `world-server` / `client` / `auth-server` / `protocol` に分け、protocol はタグ（`v0.1.0`〜`v0.1.2`）で版を切る。各消費側は `PROTOCOL_PIN` の tag と sha を読み、`client/proto_resolve/src/lib.rs` が clone 後に sha を照合して不一致なら失敗、空 sha も拒否、ロックファイルで並行ビルドを直列化する。Cargo の git 依存よりも明示的で、protobuf スキーマの破壊的変更をピンの更新として PR に可視化できる。
  > 対象ファイル: `client/proto_resolve/src/lib.rs`, `world-server/PROTOCOL_PIN`, `client/PROTOCOL_PIN`

- **認証をサービスとして切り出し、JWT / JWKS 契約で疎結合にした** `+2`
  > `auth-server` は RS256 JWT を発行して JWKS を公開し、`world-server` は `Network.AuthVerifier` で JWKS を引いて検証するだけ。両者の取り決めは `auth-server/.workspace/0_docs/jwt-jwks-engine-contract.md` に文書化されている。
  > 対象ファイル: `world-server/apps/network/lib/network/auth_verifier.ex`, `auth-server/.workspace/0_docs/jwt-jwks-engine-contract.md`

- **protocol リポジトリが自前のコンパイル検証 CI を持つ** `+1`（新規）
  > `protocol/.github/workflows/proto-verify.yml` で全 `.proto` を protoc でコンパイルする。スキーマ単体の健全性は消費側に依存せず守られる。
  > 対象ファイル: `protocol/.github/workflows/proto-verify.yml`

**プロジェクト全体 小計: +16**

---

## world-server — apps/core

- **`Core.FormulaGraph`（DAG → バイトコードのコンパイラ）** `+4`
  > ノードグラフを Kahn 法でトポロジカルソートし、循環を検出してエラーにし（`core/formula_graph.ex:73,139-155`）、レジスタ割り当てを伴うバイトコードを出す。ゲームロジックのビジュアル編集を見据えた「定義は Elixir、実行は VM」の分離が、コンパイラの形で具体化している。
  > 対象ファイル: `world-server/apps/core/lib/core/formula_graph.ex`

- **バイトコード契約が Elixir と Rust の両側で明文化されている** `+4`
  > opcode・オペランド幅・レジスタ数（64）を Elixir のエンコーダと Rust の `decode.rs` が同じ前提で扱い、Rust 側は全読み出しを境界検査する（`rust/nif/src/formula/decode.rs:53-171`）。言語境界の契約として丁寧である。
  > 対象ファイル: `world-server/apps/core/lib/core/formula.ex`, `world-server/rust/nif/src/formula/decode.rs`

- **`FormulaStore` の local / synced スコープ設計** `+3`
  > 値ごとにスコープを持ち、synced は MFA 経由でブロードキャストする（`core/formula_store.ex:185-208`）。backend はビヘイビアで差し替え可能（`LocalBackend`）。ETS 所有の問題は別途マイナスで計上した。
  > 対象ファイル: `world-server/apps/core/lib/core/formula_store.ex`

- **`Core.Component` ビヘイビアによるコンポーネント合成** `+2`
  > コンテンツは `components/0` でコンポーネントを並べるだけで入力・描画・物理フックが合成される。Bevy の Plugin に近い粒度。moduledoc が古い点は別途マイナス。
  > 対象ファイル: `world-server/apps/core/lib/core/component.ex`

- **`RoomSupervisor` + `RoomRegistry` によるルームのプロセス分離** `+2`
  > ルームごとに `DynamicSupervisor` の子として起動し、Registry で引く（`core/room_supervisor.ex:15-62`）。シーンスタック共有は別途マイナスだが、土台は OTP の定石どおり。
  > 対象ファイル: `world-server/apps/core/lib/core/room_supervisor.ex`, `world-server/apps/core/lib/core/room_registry.ex`

- **tick レートのホワイトリストと起動時 raise** `+2`
  > `@allowed_tick_hz [10, 20, 30, 60]` 以外は起動時に例外（`core/config.ex:12-43`）。不正な設定が静かに走り続けることがない。
  > 対象ファイル: `world-server/apps/core/lib/core/config.ex`

- **`FrameCache` の ETS 所有をルームより先に起動する規律** `+2`
  > `Server.Application` の子の並びで FrameCache を最初に置き、ルームが落ちてもキャッシュが残る（`server/application.ex:20-31`）。
  > 対象ファイル: `world-server/apps/core/lib/core/frame_cache.ex`

- **`StressMonitor` による負荷監視** `+2`
  > tick 遅延・メールボックス深さを定期監視し、ログに出す。運用時の第一報になる。
  > 対象ファイル: `world-server/apps/core/lib/core/stress_monitor.ex`

- **`EventBus` が購読者を monitor して自動解除する** `+1`
  > 購読者が落ちても配信先に残らない。
  > 対象ファイル: `world-server/apps/core/lib/core/event_bus.ex`

**apps/core 小計: +22**

---

## world-server — apps/contents

- **メールボックス深さによるバックプレッシャーとフレームドロップ telemetry** `+4`
  > 閾値 `max(tick_hz * 2, 120)` を超えたら tick を間引き、`[:game, :frame_dropped]` を発火する（`events/game.ex:329-345`）。BEAM の GenServer ループで「遅れたら追いつこうとして雪崩れる」を構造的に防いでいる。Phoenix PubSub のような汎用層には無い、ゲームループ固有の配慮。
  > 対象ファイル: `world-server/apps/contents/lib/events/game.ex`

- **`context.dt` による tick レート非依存のロジック** `+2`
  > `build_context` が `dt` を渡し（`events/game.ex:571-602`）、Tetris 以外の 4 コンテンツは秒単位で動く。
  > 対象ファイル: `world-server/apps/contents/lib/events/game.ex`

- **Zenoh への配信を MFA で注入し、contents から transport を消した** `+3`
  > `events/game.ex:521-546` は `:zenoh_frame_publish` の MFA を呼ぶだけで、Zenoh の API を知らない。
  > 対象ファイル: `world-server/apps/contents/lib/events/game.ex`

- **VR 入力の防御的ガード** `+2`
  > head / hand 姿勢の入力を型・有限値で検証してから state に入れる。
  > 対象ファイル: `world-server/apps/contents/lib/components/category/device/`

- **差し替え可能な 5 コンテンツ** `+3`
  > `BulletHell3D` / `Tetris` / `CanvasTest` / `FormulaTest` / `SampleOsc` が同じ `ContentBehaviour` で起動でき、`config :server, :current` 1 行で切り替わる（`config.exs:90`）。
  > 対象ファイル: `world-server/apps/contents/lib/contents/`

- **`ContentBehaviour` の契約** `+2`
  > 必須と optional を分け、各コールバックに doc を付けている（`behaviour/content.ex`）。不要な武器系コールバックの残存は別途マイナス。
  > 対象ファイル: `world-server/apps/contents/lib/behaviour/content.ex`

- **`FrameEncoder` による RenderFrame の protobuf 化** `+3`
  > DrawCommand / Camera / UI / mesh 定義 / audio を protobuf にまとめ、クライアント側の golden テストと突き合わせられる形にしている。
  > 対象ファイル: `world-server/apps/contents/lib/contents/frame_encoder.ex`

- **シーンスタック API（push / pop / replace）** `+2`
  > `Contents.Scenes.Stack` は room_id 付き登録にも対応済み（`scenes/stack.ex:203-214`）。使われていない点は別途マイナス。
  > 対象ファイル: `world-server/apps/contents/lib/scenes/stack.ex`

- **Nodes / Structs による定義の構造化** `+2`
  > ゲームロジックの部品をノードとして型付きで並べ、Formula に繋げる下地になっている。
  > 対象ファイル: `world-server/apps/contents/lib/nodes/`

- **パラメータをコンテンツ側に集約** `+2`
  > 速度・HP・出現間隔などの数値が contents に置かれ、Rust に一切ない。
  > 対象ファイル: `world-server/apps/contents/lib/contents/bullet_hell_3d/`

- **命名の一貫性** `+1`
  > `Content.*` / `Contents.*` / `Core.*` / `Network.*` の名前空間が層と一致している。
  > 対象ファイル: `world-server/apps/contents/lib/`

- **OSC 連携がテスト付きで実装されている** `+2`
  > `SampleOsc` の OSC 送受信は GenServer に catch-all を持ち、テストもある。
  > 対象ファイル: `world-server/apps/contents/lib/contents/sample_osc/`

**apps/contents 小計: +28**

---

## world-server — apps/network

- **3 つのトランスポートが同じルームメッセージに収束する** `+4`
  > Zenoh（`zenoh_bridge.ex:260-272`）・UDP（`udp/server.ex:259-276`）・Phoenix Channel（`channel.ex:133-145`）がすべて `send(pid, {:move_input, ...} / {:ui_action, ...})` に落ちる。ゲームロジックはトランスポートを知らない。境界での検証が薄い点は別途マイナス。
  > 対象ファイル: `world-server/apps/network/lib/network/`

- **UDP バイナリプロトコルの設計** `+3`
  > 固定ヘッダ・種別・seq を持つ明快なフレーミング（`udp/protocol.ex`）。
  > 対象ファイル: `world-server/apps/network/lib/network/udp/protocol.ex`

- **zlib 展開の 64KB 上限（zip bomb 対策）** `+3`
  > `safeInflate` で展開量を制限する（`udp/protocol.ex:226-260`）。見落とされがちな防御。
  > 対象ファイル: `world-server/apps/network/lib/network/udp/protocol.ex`

- **UDP セッションの期限切れ掃除** `+2`
  > 一定時間無通信のセッションを定期的に破棄する。
  > 対象ファイル: `world-server/apps/network/lib/network/udp/server.ex`

- **`ZenohBridge` の DoS 対策** `+3`
  > client_info を最大 100 ルームに制限し（`zenoh_bridge.ex:286-345`）、room_id を正規表現で検査し（`:330`）、`safe_to_string` で atom 生成を避ける（`:428-439`）。
  > 対象ファイル: `world-server/apps/network/lib/network/zenoh_bridge.ex`

- **`AuthVerifier` の JWKS RS256 検証** `+3`
  > JWKS を取得・キャッシュし、`kid` で鍵を選んで検証する。鍵ローテーションに追従できる。
  > 対象ファイル: `world-server/apps/network/lib/network/auth_verifier.ex`

- **WebSocket は `AUTH_REQUIRED` に関係なく常に RoomToken 必須** `+3`
  > Channel の join は RoomToken の検証を必ず通す。最も到達しやすい経路を既定で閉じている。
  > 対象ファイル: `world-server/apps/network/lib/network/channel.ex`

- **network の分離テスト（102 件）** `+3`
  > トランスポート・認証・S2S・プロトコルを個別にテストしている。world-server で最も厚い。
  > 対象ファイル: `world-server/apps/network/test/`

- **protobuf の往復契約テスト** `+2`
  > Input / ClientInfo / FrameInjection の encode → decode を検査する（`protobuf_contract_test.exs`）。
  > 対象ファイル: `world-server/apps/network/test/network/proto/protobuf_contract_test.exs`

- **分散時のフォールバック** `+2`
  > クラスタ未構成でもローカル単独で動く（`distributed.ex`）。
  > 対象ファイル: `world-server/apps/network/lib/network/distributed.ex`

- **S2S の discovery エンドポイント** `+2`
  > `/.well-known/alchemy-s2s.json` と `/api/s2s/worlds` で、連合の最初の一歩を規約化している（`router.ex:32-93`）。
  > 対象ファイル: `world-server/apps/network/lib/network/router.ex`

**apps/network 小計: +30**

---

## world-server — apps/server

- **prod の設定欠落で起動を止める fail-fast** `+2`
  > `SECRET_KEY_BASE` 未設定、および認証必須なのに JWKS URL がない場合に `raise`（`config/runtime.exs`）。
  > 対象ファイル: `world-server/config/runtime.exs`

- **薄いエントリポイント** `+2`
  > `Server.Application` は子の並びとコンテンツ選択だけを持つ（`server/application.ex:10-43`）。
  > 対象ファイル: `world-server/apps/server/lib/server/application.ex`

**apps/server 小計: +4**

---

## world-server — rust/nif（Formula VM）

- **NIF のエラー境界（panic させず term で返す）** `+4`
  > `error_to_term` で全 VM エラーを Elixir の term に写像し（`formula_nif.rs:183-226`）、ホットパスに `unwrap` がない。NIF の panic は BEAM ごと落ちうるので、ここを守っていることの価値は大きい。
  > 対象ファイル: `world-server/rust/nif/src/nif/formula_nif.rs`

- **decode の全境界検査** `+3`
  > 途中終端・レジスタ番号超過・未知 opcode をすべて `Err` にする（`decode.rs:53-171`）。
  > 対象ファイル: `world-server/rust/nif/src/formula/decode.rs`

- **型昇格のテスト** `+2`
  > 整数と浮動小数の混在演算の昇格規則をテストで固定している。
  > 対象ファイル: `world-server/rust/nif/src/formula/vm.rs`

- **saturating / checked 演算** `+2`
  > 整数オーバーフローを wrap させず、ゼロ除算をエラーにする（`vm.rs` のテスト 6 件で確認。今回 `cargo test -p nif` で 6 pass を実行確認）。
  > 対象ファイル: `world-server/rust/nif/src/formula/vm.rs`

- **Elixir 側からの結合テスト** `+2`
  > `apps/core/test` から実 NIF を呼んで Formula の結果を検査する。
  > 対象ファイル: `world-server/apps/core/test/`

**rust/nif 小計: +13**

---

## client（Rust クライアント）

### client/shared

- **`SnapshotInterpolator`（適応的な補間遅延）** `+5`
  > ジッタに応じて補間遅延を 80〜250ms で動的に調整し、外挿の上限・スナップの閾値を定数で明示する（`client/shared/src/interp.rs:14-41`）。`push`（`:528`）と `sample`（`:581-615`）の分離も明快で、テスト 18 件（今回 `cargo test -p shared` で 18 pass を実行確認）。Valve の Source エンジンの補間（`cl_interp`）を固定値でなく適応で実装しており、同規模の OSS では稀。最近傍対応付けの限界は別途マイナス。
  > 対象ファイル: `client/shared/src/interp.rs`

### client/network

- **Zenoh セッションの指数バックオフ再接続と publisher キャッシュ** `+4`
  > セッション切断を検知して指数バックオフで張り直し、publisher を再宣言する（`client/network/src/platform/desktop.rs:19-21,280-331`）。
  > 対象ファイル: `client/network/src/platform/desktop.rs`

- **Elixir が生成した golden バイト列による E2E 契約テスト** `+3`
  > Elixir の `FrameEncoder` が出したバイト列を Rust でデコードして検査する（`client/network/tests/render_frame_e2e_contract.rs`。今回 1 pass を実行確認）。言語をまたぐ契約をバイト単位で固定する発想は良い。world-server 側で再生成・照合されない点は別途マイナス。
  > 対象ファイル: `client/network/tests/render_frame_e2e_contract.rs`

### client/render

- **GPU バッファの再利用とサイズ拡張** `+3`
  > 頂点・インスタンスバッファを使い回し、足りないときだけ伸ばす。
  > 対象ファイル: `client/render/src/renderer/`

- **インスタンシングと WGSL シェーダの分離** `+3`
  > シェーダを `assets/shaders` から読み、見つからなければ組み込みにフォールバックする（`app/src/main.rs:123-138`）。
  > 対象ファイル: `client/render/src/renderer/pipeline_3d/mod.rs`, `client/app/src/main.rs`

- **headless のオフスクリーン描画** `+2`
  > `render_frame_offscreen`（`render/src/headless.rs:382`）があり、golden image テストの下地がある。
  > 対象ファイル: `client/render/src/headless.rs`

- **Surface lost からの復帰** `+1`
  > `SurfaceError::Lost` で再設定する。
  > 対象ファイル: `client/render/src/`

### client/window

- **winit イベントの正規化** `+2`
  > OS 依存のイベントをエンジン用の入力に変換して他クレートから winit を隠す。
  > 対象ファイル: `client/window/src/`

### client/audio

- **オーディオデバイス不在時のフォールバック** `+3`
  > 出力デバイスが開けなくても起動を止めず無音で続行する。
  > 対象ファイル: `client/audio/src/audio.rs`

- **アセット読み込みのパストラバーサル検査** `+3`
  > `..` や絶対パスを拒否する（`client/audio/src/asset/mod.rs:172,177`）。
  > 対象ファイル: `client/audio/src/asset/mod.rs`

### client/app・その他クレート

- **認証クライアントの失敗で起動をブロックしない** `+2`
  > auth-server が落ちていてもゲストとして起動する（`app/src/main.rs:58-70`）。
  > 対象ファイル: `client/app/src/main.rs`

- **11 クレートへの責務分割** `+3`
  > `shared` / `network` / `render` / `window` / `audio` / `app` / `auth_client` / `system_ui` / `xr` / `render_frame_proto` / `proto_resolve`（`client/Cargo.toml`）。transport が render に依存する点は別途マイナス。
  > 対象ファイル: `client/Cargo.toml`

- **`auth_client` のトークンを OS キーリングに保存** `+4`
  > Windows Credential Manager / macOS Keychain / Linux Secret Service に保存し、平文ファイルを使わない（`auth_client/src/token_store.rs`）。テスト 8 件。ゲームクライアントで稀な配慮。
  > 対象ファイル: `client/auth_client/src/token_store.rs`

- **`system_ui` のテスト（16 件）** `+2`
  > UI レイアウト・入力処理を単体でテストしている。
  > 対象ファイル: `client/system_ui/`

- **`unsafe` が `xr` クレートに閉じている** `+2`
  > FFI が必要な OpenXR 以外に `unsafe` がない。
  > 対象ファイル: `client/xr/src/`

- **OpenXR ループの雛形** `+1`
  > headless 拡張でのセッション・フレームループの流れは書けている（`xr/src/openxr_loop.rs`）。app 未配線は別途マイナス。
  > 対象ファイル: `client/xr/src/openxr_loop.rs`

- **client CI で fmt / clippy / app ビルドを強制** `+1`
  > `client/.github/workflows/ci.yml`。テスト未実行は別途マイナス。
  > 対象ファイル: `client/.github/workflows/ci.yml`

**client 小計: +44**（shared +5 / network +7 / render +9 / window +2 / audio +6 / app・その他 +15）

---

## auth-server

### auth-server/lib/auth

- **RS256 の複数鍵 JWKS とローテーション** `+5`
  > 署名鍵を複数持ち、`kid` 付きで JWKS に公開し、旧鍵で署名済みのトークンも検証できる（`auth/token.ex:14-31`）。Phoenix アプリでここまで運用を見据えた鍵管理は稀で、Keycloak や Auth0 の公開仕様と同じ形をとっている。
  > 対象ファイル: `auth-server/lib/auth/token.ex`

- **リフレッシュトークンの family ローテーションと再利用検知** `+4`
  > 使用済みトークンの再提示で family 全体を失効させ、10 秒の猶予を設定で持つ（`config.exs`）。競合の穴は別途マイナス。
  > 対象ファイル: `auth-server/lib/auth/accounts.ex`

- **Argon2 によるパスワードハッシュ** `+4`
  > 現行の推奨アルゴリズムを採用している。
  > 対象ファイル: `auth-server/lib/auth/password.ex`

- **`jti` による失効とアカウント状態の検査** `+3`
  > JWT 検証時に失効リストとユーザー状態を見る（`auth/token.ex:90-125`）。
  > 対象ファイル: `auth-server/lib/auth/token.ex`

- **トークンを SHA-256 ハッシュで保存** `+3`
  > リフレッシュトークン・アカウントトークンを平文で DB に置かない（`accounts.ex:399-402,506-508`）。
  > 対象ファイル: `auth-server/lib/auth/accounts.ex`

- **短い JWT TTL（15 分）** `+1`
  > `jwt_ttl 900`（`auth-server/config/config.exs`）。
  > 対象ファイル: `auth-server/config/config.exs`

- **アカウントのライフサイクル操作** `+4`
  > 停止・削除・復帰などを状態遷移として実装している（`accounts.ex:191-274`）。
  > 対象ファイル: `auth-server/lib/auth/accounts.ex`

- **メール検証フローの `FOR UPDATE` ロック** `+3`
  > 検証トークンの消費を行ロックで原子化している（`accounts.ex:459-475`）。
  > 対象ファイル: `auth-server/lib/auth/accounts.ex`

- **Ash リソースによる宣言的バリデーション** `+3`
  > 入力検証をリソース定義に集約している。
  > 対象ファイル: `auth-server/lib/auth/accounts/user.ex`

- **利用規約の同意記録** `+3`
  > 同意したバージョンと日時を保存する。
  > 対象ファイル: `auth-server/lib/auth/accounts/user.ex`

- **`TokenCleanup` による期限切れデータの定期削除** `+2`
  > 失効リストと refresh token を周期的に掃除する。
  > 対象ファイル: `auth-server/lib/auth/token_cleanup.ex`

- **release 定義と Dockerfile** `+3`
  > `mix.exs` の `releases/0` と Dockerfile で配布できる。world-server に無い点との対比で目立つ。
  > 対象ファイル: `auth-server/mix.exs`

- **runtime 設定の fail-fast** `+2`
  > 必須の環境変数がなければ起動時に `raise`（`config/runtime.exs:74,229`）。
  > 対象ファイル: `auth-server/config/runtime.exs`

### auth-server/lib/auth_web

- **12 バケットのレート制限** `+4`
  > ログイン・登録・リフレッシュ・パスワードリセットなどを個別のバケットで制限する（`auth/rate_limit.ex`）。単一ノード限定は別途マイナス。
  > 対象ファイル: `auth-server/lib/auth/rate_limit.ex`

- **`Authenticate` plug の失敗情報の扱い** `+3`
  > 失敗理由はログにだけ残し、レスポンスは一律の 401 / 403 にする。
  > 対象ファイル: `auth-server/lib/auth_web/plugs/authenticate.ex`

- **アカウント列挙を防ぐ応答** `+2`
  > 存在しないメールでも同じ応答を返す。
  > 対象ファイル: `auth-server/lib/auth_web/controllers/`

- **`ClientIp` の信頼プロキシ設定** `+2`
  > `X-Forwarded-For` を信頼済みプロキシからのみ採用する。
  > 対象ファイル: `auth-server/lib/auth_web/client_ip.ex`

- **CI と `mix precommit`** `+2`
  > Postgres サービス付きで format / compile / credo / test を回す（`auth-server/.github/workflows/ci.yml`）。
  > 対象ファイル: `auth-server/.github/workflows/ci.yml`

- **テスト 107 件** `+4`
  > 16 ファイルで認証・ライフサイクル・レート制限を検査する。4 リポジトリで最も厚い。
  > 対象ファイル: `auth-server/test/`

- **world-server との契約文書** `+2`
  > `jwt-jwks-engine-contract.md` に claims と検証手順を明記している。
  > 対象ファイル: `auth-server/.workspace/0_docs/jwt-jwks-engine-contract.md`

- **統一されたエラー JSON** `+1`
  > `ErrorJSON` で形式を揃えている。
  > 対象ファイル: `auth-server/lib/auth_web/controllers/error_json.ex`

**auth-server 小計: +60**（lib/auth +40 / lib/auth_web +20）

---

## 横断評価層

### テスト戦略

- **層ごとにテストの責務を分けている** `+3`
  > core は Formula、network はトランスポート、client は補間・UI、auth は認証フローと、守るべきものに沿ってテストを置いている。
  > 対象ファイル: `world-server/apps/*/test/`, `auth-server/test/`

### 開発者体験（DX）

- **`mix alchemy.ci` によるローカル CI の 1 コマンド化** `+3`
  > Rust（`cargo test -p nif`）と Elixir（format / credo --strict / test --warnings-as-errors）を順に回す（`core/lib/mix/tasks/alchemy.ci.ex:93-106`）。world-server に閉じている点は別途マイナス。今回は実行していない。
  > 対象ファイル: `world-server/apps/core/lib/mix/tasks/alchemy.ci.ex`

- **world-server CI の proto-verify（生成物の差分検査）** `+3`
  > protobuf 生成物を再生成して `git diff` で差分を検出する（`world-server/.github/workflows/ci.yml`）。
  > 対象ファイル: `world-server/.github/workflows/ci.yml`

- **protoc / protobuf のバージョン固定** `+1`
  > 生成器の版を固定し、生成物の揺れを防ぐ。
  > 対象ファイル: `world-server/.github/workflows/ci.yml`

- **CI セットアップの composite action 化** `+2`
  > `alchemy-ci-setup` で各ジョブの準備を共通化している。
  > 対象ファイル: `world-server/.github/actions/alchemy-ci-setup/action.yml`

### 変更容易性・保守性

- **moduledoc の充実** `+2`
  > 主要モジュールに目的と前提が書かれている（一部が古い点は別途マイナス）。
  > 対象ファイル: `world-server/apps/`

### エラーハンドリング

- **エラー契約の明示（NIF・auth）** `+2`
  > NIF は term、auth は統一 JSON と、境界ごとにエラーの形を決めている。
  > 対象ファイル: `world-server/rust/nif/src/nif/formula_nif.rs`, `auth-server/lib/auth_web/controllers/error_json.ex`

### プロセス

- **作業レーン（backlog / doing / done）による計画管理** `+2`
  > `.workspace/1_backlog` などで作業の状態を管理している。
  > 対象ファイル: `.workspace/`

- **自己評価サイクルの仕組み** `+2`
  > 評価 → 改善計画 → 実装のループを文書として持っている（回っていない点は別途マイナス）。
  > 対象ファイル: `.workspace/0_reference/improvement-plan.md`

### 可観測性

- **構造化ログ** `+2`
  > room_id などのメタデータを付けてログを出す。
  > 対象ファイル: `world-server/apps/`

### 技術的負債の管理

- **技術的負債を文書で追跡** `+1`
  > 未実施項目を `0_reference` に書き出している。
  > 対象ファイル: `.workspace/0_reference/`

**横断評価層 小計: +23**

---

## 総計

| 大分類 | 項目数 | プラス小計 |
|:---|:---:|:---:|
| プロジェクト全体 | 6 | +16 |
| world-server — apps/core | 9 | +22 |
| world-server — apps/contents | 12 | +28 |
| world-server — apps/network | 11 | +30 |
| world-server — apps/server | 2 | +4 |
| world-server — rust/nif | 5 | +13 |
| client | 17 | +44 |
| auth-server | 21 | +60 |
| 横断評価層 | 11 | +23 |
| **プラス合計** | **94** | **+240** |
