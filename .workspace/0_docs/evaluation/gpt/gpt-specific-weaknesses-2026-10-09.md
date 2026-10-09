# AlchemyEngine 弱点詳細 — GPT-5.6 Sol（2026-10-09）

| 点数 | 基準 |
|:---:|:---|
| -1 | 軽微な改善余地 |
| -2 | 重要な機能・設計の欠如 |
| -3 | バグ・クラッシュ・性能劣化を招き得る明確な欠陥 |
| -4 | 価値命題を損なう重大な欠如 |
| -5 | 根幹を揺るがす致命的欠陥 |

## 技術評価層 — world-server/

### apps/contents

- **全ルームが単一 Scene Stack を共有する** `-4`
  > `Server.Application` は `Contents.Scenes.Stack` を一つだけ起動し、Tetris と BulletHell3D は `flow_runner(_room_id)` で引数を捨てて同じ PID を返す（`server/application.ex:20-30`, `contents/tetris.ex:27`, `contents/bullet_hell_3d.ex:52`）。一方、各ルームの tick は別 GenServer で走るため、複数ルームが同じシーンを更新し状態を相互汚染する。Stack を `RoomSupervisor` の子へ移し、Registry で `{room_id, :scene_stack}` を引く状態分離テストを追加すべきである。
  > 対象ファイル: `world-server/apps/server/lib/server/application.ex`

- **Tetris が権威 tick 設定を無視する** `-2`
  > `@tick_sec 1/60`、フレーム数ベースの落下・入力 cooldown を持ち、`update/2` は context を捨てる（`tetris/playing.ex:10-15,40-49,160-175`）。既定 20Hz では設計速度の約 1/3 になる。`context.dt` と秒単位 accumulator に置換し、10/20/30Hz で同じ落下時間を検証すべきである。
  > 対象ファイル: `world-server/apps/contents/lib/contents/tetris/playing.ex`

- **編集・永続化経路がスタブのまま** `-2`
  > save/load はログを出して無視され（`events/game.ex:104-118`）、旧 frame injection も毎 tick Process Dictionary を初期化した後に no-op へ流れる（同 `410-472`）。Object create/destroy 系にも TODO が残る。死んだ経路は削除し、永続化はユーザー `sub` に束縛した一つの実経路を通すべきである。
  > 対象ファイル: `world-server/apps/contents/lib/events/game.ex`

### apps/core

- **FormulaStore の ETS 所有者が不定** `-2`
  > `ensure_init/0` を最初に呼んだ任意プロセスが named table を所有する（`formula_store.ex:40-49,164-167`）。所有プロセス停止で同期状態が消える。FrameCache と同様に専用 GenServer を Supervisor 配下へ置き、再起動時の復元方針を定義すべきである。
  > 対象ファイル: `world-server/apps/core/lib/core/formula_store.ex`

- **core 契約とメトリクスに撤去済み・コンテンツ固有知識が残る** `-2`
  > `Core.Component` は 60Hz 物理フレーム、Rust world_ref、NIF sync を現行契約として説明する（`component.ex:10-27,54-68`）。`Core.Telemetry` は enemy/level/boss を直接命名する（`telemetry.ex:20-37`）。汎用 tick/queue/runtime 指標へ限定し、ゲーム指標は contents が登録すべきである。
  > 対象ファイル: `world-server/apps/core/lib/core/telemetry.ex`

### apps/network

- **本番も認証が既定無効で、RoomToken がユーザーに束縛されない** `-4`
  > `runtime.exs:50-60` は `AUTH_REQUIRED` 未設定を false にする。RoomToken のペイロードは room_id だけで、署名・検証 API も identity を返さない（`room_token.ex:8-18,33-37,60-76`）。prod は fail-secure にし、JWT `sub` を room token/session に伝播させるべきである。
  > 対象ファイル: `world-server/config/runtime.exs`

- **サーバー側 Zenoh は切断から復旧しない** `-3`
  > init で session/subscriber を宣言するだけで、一般メッセージは debug ログへ落ちる（`zenoh_bridge.ex:51-82,166-170`）。クライアント側にある generation gate と指数バックオフを移植し、再購読・publisher 再生成を telemetry 付きで行うべきである。
  > 対象ファイル: `world-server/apps/network/lib/network/zenoh_bridge.ex`

- **UDP が入口制限・replay/順序・断片化を保証しない** `-3`
  > active socket が任意 datagram を受け、sessions は上限なし、INPUT/ACTION の seq は捨てられる（`udp/server.ex:120-148,240-276`）。送信 FRAME も単一 datagram である。サイズ・セッション・レート上限と受信 seq 検証を入れ、MTU 超過は QUIC/WebTransport 等へ委譲すべきである。
  > 対象ファイル: `world-server/apps/network/lib/network/udp/server.ex`

- **分散探索が全ノード RPC、S2S は平文 HTTP を許す** `-2`
  > `find_room_node/1` は呼び出しごとに全ノードの room list を走査する（`distributed.ex:239-247`）。S2S client は URL scheme を制限せず例にも HTTP を示す（`s2s/client.ex:8-21`）。配置表を分散 registry に持ち、本番 peer は HTTPS のみに制限すべきである。
  > 対象ファイル: `world-server/apps/network/lib/network/distributed.ex`

### apps/server

- **起動木がグローバル状態を固定し、release/smoke 保証がない** `-3`
  > Application 起動時に global Stack/EventBus/Stats を一個ずつ起動してから `:main` room を追加する（`application.ex:20-46`）。umbrella `mix.exs` に release 定義もなく、server test も存在しない。room subtree に所有権を寄せ、起動・停止・再起動を検証する smoke test と release を用意すべきである。
  > 対象ファイル: `world-server/apps/server/lib/server/application.ex`

### rust/nif（physics を含む）

- **ビジョンが保証する物理基盤の実装が存在しない** `-4`
  > 現行 `rust/nif` は Formula VM の9ファイルだけで、physics/ECS/SoA/SIMD/衝突 API はない。これは整理としては明快だが、「物理の基盤」を保証する現行 vision と評価ルールに対しては未実装である。保証を撤回するか、contents 定義を受ける決定論的な汎用 physics 実行層を別 crate として実装すべきである。
  > 対象ファイル: `world-server/rust/nif/src/lib.rs`

- **通常 scheduler NIF に入力・命令・実行上限がない** `-3`
  > decode は bytecode 終端まで無制限に `Vec` へ命令を積み（`decode.rs:52-60,165-171`）、NIF は `#[rustler::nif]` のまま（`formula_nif.rs:25-31`）。byte長・命令数・store項目数を制限し、DirtyCpu または yielding NIF と gas を導入すべきである。
  > 対象ファイル: `world-server/rust/nif/src/formula/decode.rs`

- **ABI/version 契約とエラー分類が弱い** `-2`
  > bytecode version header がなく、入力 map の一部エラーだけ `rustler::Error::Term`、range error と VM error は `{:error, ...}` になる（`formula_nif.rs:32-67,183-223`）。magic/version/feature bits を設け、呼出し型違いとドメインエラーを一貫した契約に分離すべきである。
  > 対象ファイル: `world-server/rust/nif/src/nif/formula_nif.rs`

## 技術評価層 — client/

### shared

- **安定 entity ID がなく補間が O(N×M) の最近傍推測** `-3`
  > `find_nearest_prev` は距離3以内を線形探索し、コメント自身が O(N×M) を認める（`interp.rs:307-340`）。密集・交差・teleport で別個体を結び付け、sample は RenderFrame を毎回 clone する（同 `580-613`）。protocol に entity_id/tick を追加し ID join、Arc 化へ移行すべきである。
  > 対象ファイル: `client/shared/src/interp.rs`

- **クライアント予測が恒等関数** `-2`
  > `predict_input` は入力をそのまま返すだけである（`predict.rs:8-12`）。20Hz authority と80〜250ms buffer の構成では自機操作遅延が残る。input seq、server ack、reconciliation を含む予測を実装すべきである。
  > 対象ファイル: `client/shared/src/predict.rs`

### network

- **AUTH_REQUIRED 時に出荷クライアントが入室不能** `-4`
  > `NetworkRenderBridge` は movement/action/client_info を生 protobuf のまま publish する（`network_render_bridge.rs:123-166`）。サーバーは AUTH_REQUIRED 時に RoomToken envelope を必須にするが、app は auth login と room token 取得を通信へ接続していない。Bearer→room token→envelope の経路をE2Eで通すべきである。
  > 対象ファイル: `client/network/src/network_render_bridge.rs`

- **Web transport は API だけ存在する空実装** `-2`
  > WASM ClientSession は open/put が常に error、subscriber は空 thread を返す（`platform/web.rs:1-28`）。対応プラットフォームとして見せず feature を無効化するか、WebSocket/WebTransport 実装と browser contract test を追加すべきである。
  > 対象ファイル: `client/network/src/platform/web.rs`

### render

- **性能上限がコンテンツ知識の固定値で、回帰テストもない** `-3`
  > renderer は Player/Boss/Enemies 等の内訳から `MAX_INSTANCES=14510` をハードコードする（`renderer/mod.rs:98-105`）。カリングなしで超過分は黙って打ち切る（同 `670-682`）。汎用 capacity growth・frustum/距離 culling・drop metricを実装し、headless golden testをCIに載せるべきである。
  > 対象ファイル: `client/render/src/renderer/mod.rs`

### window

- **復旧可能な初期化失敗で panic する** `-1`
  > window creation と Renderer GPU 初期化は `expect` を使う（`desktop_loop.rs:124-141`, `renderer/mod.rs:164-189`）。ヘッドレス/adapter fallback またはユーザー向け error に変換し、event loop の Result 境界まで返すべきである。
  > 対象ファイル: `client/window/src/desktop_loop.rs`

### audio

- **キュー・同時発音・空間音響に上限/設計がない** `-2`
  > 標準の無界 `mpsc::channel` を使い、SE ごとに Sink を生成して detach する（`audio.rs:50-61,120-139`）。負荷時のメモリ/voice増加を防ぐ bounded queue、優先度、voice stealing、3D位置・距離減衰を導入すべきである。
  > 対象ファイル: `client/audio/src/audio.rs`

### app

- **認証・XR・ネットワーク統合が出荷経路で閉じていない** `-3`
  > app は System UI に AuthClient を渡すが、NetworkRenderBridge は room_id だけで即接続する（`main.rs:23-55,60-69`）。認証結果を room token と Zenoh envelope に接続し、XR選択も同じ entrypoint から起動できるよう統合すべきである。
  > 対象ファイル: `client/app/src/main.rs`

## 技術評価層 — auth-server/

### lib/auth

- **メール未検証ユーザーにも access/refresh token を発行する** `-3`
  > register controller は作成直後に `issue_session` を呼び、login は status だけを見る（`accounts.ex:55-66,82-101`; `auth_controller.ex:27-41`）。verification flow を持ちながら認可に効いていない。`email_verified_at` を session 発行の必須条件にするか、未検証専用の制限 token に分けるべきである。
  > 対象ファイル: `auth-server/lib/auth/accounts.ex`

- **年齢ポリシーと account token GC が欠ける** `-1`
  > birthday validation は未来日だけ拒否する（`birthday_in_past.ex:9-21`）。TokenCleanup は revocation と refresh token だけを削除する（`token_cleanup.ex:62-96`）。サービス要件に沿う最低年齢を明示し、使用済み/期限切れ account token も回収すべきである。
  > 対象ファイル: `auth-server/lib/auth/token_cleanup.ex`

### lib/auth_web

- **health が readiness ではなく、CORS 方針もない** `-2`
  > `/health` は常に status ok と version を返し DB/鍵/メール依存を確認しない（`health_controller.ex:5-18`）。Endpointにも明示 CORS allowlist がない。liveness/readinessを分離し、外部Web UI向けorigin policyを明文化すべきである。
  > 対象ファイル: `auth-server/lib/auth_web/controllers/health_controller.ex`

## 横断評価層

### テスト戦略

- **クライアントの61テストが CI で実行されない** `-4`
  > client には shared 18、system_ui 16、auth_client等を含む61個の Rust test があるが、CI は fmt/clippy と `cargo build -p app` だけで `cargo test` がない（`client/.github/workflows/ci.yml:11-33`）。world-server の local CI も `-p nif` のみ（`alchemy.ci.ex:92-107`）。各子repoで workspace test を必須化すべきである。
  > 対象ファイル: `client/.github/workflows/ci.yml`

- **重要境界に property/fuzz/benchmark と統合テストがない** `-2`
  > benches/fuzz ディレクトリはなく、server smoke、render golden、認証付き app→server E2E がない。Formula decoder、protobuf、interpolator、UDP は特に任意入力へ晒されるため proptest/cargo-fuzz と性能budget testを追加すべきである。
  > 対象ファイル: `world-server/rust/nif/src/formula/decode.rs`

### 可観測性・デバッグ容易性

- **観測点が局所ログと console reporter に留まる** `-3`
  > world-server の telemetry execute は frame/tick/drop 程度、Reporter は console のみ（`core/telemetry.ex:10-17`）。Zenoh再接続、JWT/JWKS、UDP session、補間delay、render/audio dropをOTel/Prometheusへ出し、room/user相関IDを統一すべきである。
  > 対象ファイル: `world-server/apps/core/lib/core/telemetry.ex`

### エラーハンドリング戦略

- **フォールバックはあるが重要失敗を黙って捨てる** `-2`
  > audio command sender は send error を無視し（`audio.rs:86-90`）、rendererはGPU初期化でpanic、Zenoh serverは切断後に生存したまま復旧しない。回復可能/再試行/停止を型とsupervision policyで明示し、dropをmetric化すべきである。
  > 対象ファイル: `client/audio/src/audio.rs`

### 変更容易性・保守性

- **旧パス・死んだ語彙・TODO検査無効が現状理解を妨げる** `-2`
  > Rustファイルヘッダは `native/...`、Component docsは旧60Hz/NIF、Credoは TagTODO を無効化し、objects/core に実装待ちが残る。移行完了コードを削除し、TODOをissue ID必須にして機械検査すべきである。
  > 対象ファイル: `world-server/apps/core/lib/core/component.ex`

### 開発者体験（DX）

- **CI保証文書が実体と一致しない** `-3`
  > `warranty/ci.md` は存在しない root workflow、`cargo test/bench -p physics`、旧 Credo 閾値を保証として記載する（`ci.md:1-15,40-55`）。現在は子repoごとの workflow である。実行可能なコマンドから文書を生成するか、各repo CIへの正確なリンクへ書き換えるべきである。
  > 対象ファイル: `.workspace/0_docs/warranty/ci.md`

- **単一の全体保証入口が実質 world-server 限定** `-2`
  > `mix alchemy.ci` は world-server の Rust NIF と umbrella だけを対象にし、client/auth/protocolを検査しない（`alchemy.ci.ex:27-43,92-148`）。superproject用 orchestrator を用意し、子repoの正本CIを順に呼ぶべきである。
  > 対象ファイル: `world-server/apps/core/lib/mix/tasks/alchemy.ci.ex`

### セキュリティ・配布可能性

- **依存監査・OS matrix・クライアント配布がない** `-3`
  > workflow群に cargo audit/hex audit、Windows/macOS matrix、署名済みinstaller/SBOMがない。authだけrelease定義を持ち、world-serverとclientの配布経路は確定していない。Dependabot、監査、3OS check、署名成果物をrelease workflowへ追加すべきである。
  > 対象ファイル: `auth-server/mix.exs`

### プロジェクト全体設計

- **「IEEE 754 binary64 3D」をクライアント契約が守らない** `-4`
  > vision は binary64 3D座標を最上位保証とする（`vision.md:10-28`）が、クライアントのMeshVertex・DrawCommand・Cameraは f32 である（`render_frame/mod.rs:131-137,145-163`）。ネットワーク境界で精度を落とすなら保証範囲と原点rebasingを明記し、そうでなければf64契約へ揃えるべきである。
  > 対象ファイル: `client/shared/src/render_frame/mod.rs`

- **Hub・リアルタイム編集という中心価値がコード経路になっていない** `-3`
  > vision は Hub とランタイム component 追加・変更・削除を目標にする（`vision.md:97-109,182-214`）が、出荷appは固定roomへ接続し、serverは起動時に固定contentを読む。content manifest、権限付き編集protocol、hot reload、rollbackを縦に一本通すべきである。
  > 対象ファイル: `client/app/src/main.rs`

**合計: -90点（34項目）**
