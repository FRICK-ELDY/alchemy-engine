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
config :network, Network.Endpoint,
  http: [port: 4000],
  pubsub_server: Network.PubSub,
  server: true

config :network, :json_library, Jason

# ── Network.UDP（UDP トランスポートサーバー）─────────────────────
# デフォルトポート: 4001
# 変更する場合は config/runtime.exs の NETWORK_UDP_PORT を設定する。
config :network, Network.UDP, port: 4001

# ── 使用するコンテンツを指定する。
# Content.VampireSurvivor — ヴァンパイアサバイバークローン
# Content.AsteroidArena   — 小惑星シューター（武器・ボスなし）
# Content.SimpleBox3D     — シンプルな3Dゲーム（Phase R-6 動作検証用）
# Content.BulletHell3D    — 3D 弾幕避けゲーム
# Content.VRTest          — VR 動作検証（Phase A: マウスで見回し）
config :server, :current, Content.SimpleBox3D
config :server, :map, :plain
config :server, :game_events_module, Contents.GameEvents

# セーブデータの HMAC 署名鍵（デフォルト値）。
# 本番ビルド時は環境変数 SAVE_HMAC_SECRET で上書きすることを推奨する（config/runtime.exs）。
# ローカルゲームの性質上、完全な改ざん防止は不可能だが、
# 環境ごとに鍵を変えることで配布バイナリ間の互換性を制御できる。
config :core, :save_hmac_secret, "alchemy-engine-save-secret-v1"

# VR 対応 NIF をビルドする場合: features: ["xr"]
# mix compile 時に nif に --features xr が渡される。
config :core, Core.NifBridge, features: []
