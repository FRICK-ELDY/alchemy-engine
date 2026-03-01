import Config

# ── GameNetwork.Endpoint（Phoenix WebSocket サーバー）────────────────
# ポートはコンパイル時固定値として設定する。
# 実行時に変更したい場合は config/runtime.exs の GAME_NETWORK_PORT を使用する。
config :game_network, GameNetwork.Endpoint,
  http: [port: 4000],
  pubsub_server: GameNetwork.PubSub,
  server: true

config :game_network, :json_library, Jason

# ── GameNetwork.UDP（UDP トランスポートサーバー）─────────────────────
# デフォルトポート: 4001
# 変更する場合は config/runtime.exs の GAME_NETWORK_UDP_PORT を設定する。
config :game_network, GameNetwork.UDP,
  port: 4001

# ── 使用するコンテンツを指定する。
# GameContent.VampireSurvivor — ヴァンパイアサバイバークローン
# GameContent.AsteroidArena   — 小惑星シューター（武器・ボスなし）
config :game_server, :current, GameContent.VampireSurvivor
config :game_server, :map, :plain

# セーブデータの HMAC 署名鍵（デフォルト値）。
# 本番ビルド時は環境変数 SAVE_HMAC_SECRET で上書きすることを推奨する（config/runtime.exs）。
# ローカルゲームの性質上、完全な改ざん防止は不可能だが、
# 環境ごとに鍵を変えることで配布バイナリ間の互換性を制御できる。
config :game_engine, :save_hmac_secret, "alchemy-engine-save-secret-v1"
