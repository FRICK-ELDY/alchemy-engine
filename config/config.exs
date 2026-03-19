import Config

# ── libcluster（複数ノードクラスタリング）────────────────────────
# デフォルトは空（単一ノード）。複数ノードでクラスタ形成する場合は config/runtime.exs 等で設定。
#
# 例（2ノードで epmd 接続）:
#   config :libcluster,
#     topologies: [
#       network: [
#         strategy: Cluster.Strategy.Epmd,
#         config: [hosts: [:"a@127.0.0.1", :"b@127.0.0.1"]]
#       ]
#     ]
#
# 起動例: elixir --name a@127.0.0.1 -S mix run と elixir --name b@127.0.0.1 -S mix run
config :libcluster,
  topologies: []

# ── Network.Endpoint（Phoenix WebSocket サーバー）────────────────
# ポートはコンパイル時固定値として設定する。
# 実行時に変更したい場合は config/runtime.exs の NETWORK_PORT を使用する。
# secret_key_base は Phoenix.Token（ルーム参加認証）で使用する。
# 本番では config/runtime.exs の SECRET_KEY_BASE で上書きすること。
config :network, Network.Endpoint,
  http: [port: 4000],
  pubsub_server: Network.PubSub,
  server: true,
  secret_key_base: "alchemy-engine-secret-key-base-dev-test-minimum-64-chars-required-xxxx"

config :network, :json_library, Jason

# ── Network.UDP（UDP トランスポートサーバー）─────────────────────
# デフォルトポート: 4001
# 変更する場合は config/runtime.exs の NETWORK_UDP_PORT を設定する。
config :network, Network.UDP, port: 4001

# ── Network.ZenohBridge（Zenoh フレーム配信・入力受信）────────────────
# true にすると game/room/{room_id}/frame へ publish、
# game/room/*/input/movement, game/room/*/input/action を subscribe する。
# client_desktop 等のリモートクライアント接続時に有効化。
# dev/prod では true、テストでは zenohd を起動しないため false。
config :network, :zenoh_enabled, Mix.env() != :test

# zenohd への接続先。未指定時は Zenohex.Config.default()（マルチキャスト scouting）を使用。
# デフォルトは tcp/127.0.0.1:7447（IPv4 localhost）。リモート zenohd の場合は適宜変更。
config :network, :zenoh_connect, "tcp/localhost:7447"

# ── 使用するコンテンツを指定する。
# Content.VampireSurvivor — ヴァンパイアサバイバークローン
# Content.AsteroidArena   — 小惑星シューター（武器・ボスなし）
# Content.SimpleBox3D     — シンプルな3Dゲーム（Phase R-6 動作検証用）
# Content.BulletHell3D    — 3D 弾幕避けゲーム
# Content.FormulaTest     — Formula エンジン検証（Elixir→Rust→Elixir）
# Content.RollingBall     — ローリングボール迷路（Phase 6 移行済み）
# ローカル開発・動作検証時は上記いずれかに切り替える。本番は config/runtime.exs で設定すること。
config :server, :current, Content.RollingBall
config :server, :map, :plain
config :server, :game_events_module, Contents.Events.Game

# セーブデータの HMAC 署名鍵（デフォルト値）。
# 本番ビルド時は環境変数 SAVE_HMAC_SECRET で上書きすることを推奨する（config/runtime.exs）。
# ローカルゲームの性質上、完全な改ざん防止は不可能だが、
# 環境ごとに鍵を変えることで配布バイナリ間の互換性を制御できる。
config :core, :save_hmac_secret, "alchemy-engine-save-secret-v1"

# FormulaStore の synced 更新をネットワークブロードキャストする MFA。
# 形式: {Mod, Fun, []}。apply(Mod, Fun, [room_id, event]) が呼ばれる。
# 未設定・nil のときはブロードキャストしない。
# core 単体利用（network 未ロード）の場合は config/test.exs のように nil を設定すること。
config :core, :formula_store_broadcast, {Network.Distributed, :broadcast, []}

# VR 対応 NIF をビルドする場合: features: ["xr"]
# mix compile 時に nif に --features xr が渡される。
config :core, Core.NifBridge, features: []
