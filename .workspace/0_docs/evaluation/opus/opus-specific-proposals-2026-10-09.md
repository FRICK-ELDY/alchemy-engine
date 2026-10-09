# Opus 評価 — 提案詳細一覧（2026-10-09）

評価日: 2026-10-09 / 評価者: **Claude Opus 5.5**（第1評価者・独立評価）

ここに挙げるのは、現状を批判する項目ではなく「この先こうすると良くなる」という前向きな提案である。マイナス点の改善方針と重なるものは、より大きな設計の単位にまとめ直した。点数はすべて 0（総計に影響しない）。並びはおおむね優先度順である。

## 採点基準

| 点数 | 基準 |
|:---:|:---|
| 0 | 提案（加点・減点の対象外） |

---

## 堅牢性・セキュリティ

### マルチルームと入力境界

- **ルームごとのサブツリー（Game + Scenes.Stack）を `scene_stack_spec/1` で起動する** `0`
  > `ContentBehaviour.scene_stack_spec/1` は既に定義されている（`behaviour/content.ex:135`）。`RoomSupervisor.start_room/1` が `{Game, Stack}` を `one_for_all` の子として起動し、`flow_runner/1` を Registry 経由にすれば、シーンスタック共有の解消と `Device.Helpers` の `:main` 固定の撤去が同時に済む。Phoenix の `DynamicSupervisor` + `Registry` の定番構成そのもので、新しい概念は要らない。
  > 対象ファイル: `world-server/apps/core/lib/core/room_supervisor.ex`, `world-server/apps/contents/lib/behaviour/content.ex`

- **ネットワーク由来 UI action の許可リストと特権 action の分離** `0`
  > `Network` 層で `{:ui_action, name}` を転送する前に、コンテンツが宣言した `allowed_ui_actions/0` と照合する。`__quit__` / `__save__` / `__load__` はローカル管理経路専用にする。Godot の RPC `authority` / `any_peer` 指定と同じ考え方で、経路ごとに「誰が呼べるか」をデータとして持たせる。
  > 対象ファイル: `world-server/apps/network/lib/network/channel.ex`, `world-server/apps/contents/lib/components/category/device/keyboard.ex`

- **クライアントの RoomToken フローと Zenoh の ACL / TLS** `0`
  > `auth_client` の access token → `POST /api/room_token`（`sub` 付き）→ 以後の put を封筒化、の 1 経路を client に足す。あわせて zenohd の access control と TLS を有効にし、`game/room/*/input/**` に put できる主体を制限する。これで `AUTH_REQUIRED=true` を既定にできる。
  > 対象ファイル: `client/network/src/network_render_bridge.rs`, `world-server/apps/network/lib/network/room_token.ex`

- **`ZenohBridge` の死活監視とバックオフ再接続** `0`
  > `handle_continue(:connect)` でバックオフ接続し、定期的にセッションの生存を確認する。クライアント側の実装（`client/network/src/platform/desktop.rs:280-331`）と同じ方針に揃える。
  > 対象ファイル: `world-server/apps/network/lib/network/zenoh_bridge.ex`

### Formula VM

- **gas メータリングと DirtyCpu スケジューリング** `0`
  > 命令ごとに gas を消費し、上限で `{:error, :out_of_gas}` を返す。NIF は `schedule = "DirtyCpu"` にする。将来ループ・分岐命令を足す前提で、Ethereum EVM や Luau のインタプリタ制限と同じ発想。
  > 対象ファイル: `world-server/rust/nif/src/formula/vm.rs`, `world-server/rust/nif/src/nif/formula_nif.rs`

---

## リポジトリ横断の品質保証

- **スーパープロジェクトの integration CI** `0`
  > (1) 2 つの `PROTOCOL_PIN` の一致検査、(2) world-server で RenderFrame の golden を `mix` タスクで再生成、(3) client で `cargo test --workspace`、(4) world-server を `AUTH_REQUIRED=true` で起動して headless クライアントが 1 フレーム受信・入力 1 件送信できるかの smoke test。4 リポジトリ分割の価値は、この 1 本で初めて担保される。
  > 対象ファイル: `world-server/PROTOCOL_PIN`, `client/PROTOCOL_PIN`, `client/network/tests/render_frame_e2e_contract.rs`

- **プロパティベース・fuzz テストの導入** `0`
  > `SnapshotInterpolator` に proptest（任意順の push で sample が単調・有限）、`Network.UDP.Protocol.decode/1` と `Core.FormulaGraph` に StreamData、`decode_bytecode` に `cargo fuzz`。
  > 対象ファイル: `client/shared/src/interp.rs`, `world-server/apps/network/lib/network/udp/protocol.ex`, `world-server/rust/nif/src/formula/decode.rs`

- **headless 描画の golden image 回帰テスト** `0`
  > `render_frame_offscreen`（`client/render/src/headless.rs:382`）の出力をハッシュまたは許容誤差付きで比較する。`render` クレートの回帰テストゼロを一気に解消できる。
  > 対象ファイル: `client/render/src/headless.rs`

- **依存監査（dependabot / cargo-deny / mix_audit）と Dialyzer** `0`
  > 4 リポジトリに dependabot、Rust に `cargo deny check advisories licenses`、Elixir に `mix hex.audit` / `mix deps.audit` と `dialyxir`。
  > 対象ファイル: `world-server/.github/workflows/ci.yml`, `client/.github/workflows/ci.yml`, `auth-server/.github/workflows/ci.yml`

---

## ビジョンの具体化

- **binary64 の保証を浮動原点で実装する（または文言を書き分ける）** `0`
  > 権威座標は Elixir の float（binary64）で持ち、ワイヤには `int64` のセル座標 + `float` のローカルオフセットを載せる。クライアントはカメラ近傍のセルを原点に取り直す。Godot 4 の large world coordinates、Unreal 5 の LWC、Star Citizen の 64bit 座標系と同じ系譜。当面やらないなら「サーバ内部は binary64、ワイヤは binary32」と保証範囲を書き分ける。
  > 対象ファイル: `protocol/proto/render_frame/draw_commands.proto`, `.workspace/0_docs/vision.md`

- **DrawCommand に安定した `entity_id` を足す** `0`
  > 補間の誤対応を原理的に解消し、クライアント予測・エフェクトの追従・選択 UI の土台になる。`optional uint64 entity_id` なら後方互換を保てる。
  > 対象ファイル: `protocol/proto/render_frame/draw_commands.proto`, `client/shared/src/interp.rs`

- **自機のクライアント予測と reconciliation** `0`
  > `entity_id` を前提に、自機だけローカルで先行させ、権威スナップショットの seq で再適用する。Gabriel Gambetta の "Fast-Paced Multiplayer" の定石どおり。
  > 対象ファイル: `client/shared/src/predict.rs`

- **「物理の器」を純 Elixir で core に置く** `0`
  > 空間ハッシュ + AABB / 球判定を `Core.Spatial` として提供し、`BulletHell3D` の自前判定を置き換える。NIF に戻さず、まず Elixir で器の形を確定させる。
  > 対象ファイル: `world-server/apps/core/lib/core/`, `.workspace/0_docs/vision.md`

- **永続化バックエンドを 1 本通す** `0`
  > world-server に Ecto（Postgres は auth-server と共有可能）で `room_snapshots` を持ち、`__save__` / `__load__` を管理経路から呼べるようにする。
  > 対象ファイル: `world-server/apps/contents/lib/events/game.ex`

- **QUIC / WebTransport への移行検討** `0`
  > 自作 UDP の信頼性・再送・断片化を QUIC に任せ、ブラウザクライアント（WASM スタブの解消）にも道を開く。
  > 対象ファイル: `world-server/apps/network/lib/network/udp/`, `client/network/src/platform/web.rs`

---

## 運用・配布

- **world-server の release・Dockerfile・全体の docker compose** `0`
  > `releases:` と multi-stage Dockerfile を足し、スーパープロジェクトに zenohd + Postgres + auth-server + world-server の compose を置く。auth-server の Dockerfile が雛形になる。
  > 対象ファイル: `world-server/mix.exs`, `auth-server/Dockerfile`

- **Prometheus / OpenTelemetry と LiveDashboard** `0`
  > `Core.Telemetry` に Prometheus exporter を足し、認証失敗・Zenoh publish 失敗・UDP セッション淘汰をイベント化する。world-server にも LiveDashboard を付ける。
  > 対象ファイル: `world-server/apps/core/lib/core/telemetry.ex`

- **クロスプラットフォームの起動スクリプト** `0`
  > `bin/*.bat` と同等の `bin/*.sh`、または 1 バイナリのランチャーで zenohd・サーバ・クライアントを起動する。CI も Linux / Windows / macOS のマトリクスにする。
  > 対象ファイル: `bin/`

---

## 総計

| 大分類 | 項目数 | 点数 |
|:---|:---:|:---:|
| 堅牢性・セキュリティ | 5 | 0 |
| リポジトリ横断の品質保証 | 4 | 0 |
| ビジョンの具体化 | 6 | 0 |
| 運用・配布 | 3 | 0 |
| **提案合計** | **18** | **0** |
