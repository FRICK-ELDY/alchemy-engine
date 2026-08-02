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
# 下記は dev/test 用の固定値。prod は runtime.exs が SECRET_KEY_BASE 必須（未設定時 raise）。
config :network, Network.Endpoint,
  http: [port: 4000],
  pubsub_server: Network.PubSub,
  server: true,
  secret_key_base: "alchemy-engine-secret-key-base-dev-test-minimum-64-chars-required-xxxx"

config :network, :json_library, Jason

# ── Network.UDP（UDP トランスポートサーバー）─────────────────────
# デフォルトポート: 4001
# 変更する場合は config/runtime.exs の NETWORK_UDP_PORT を設定する。
# session_timeout_ms: JOIN 後の無通信でセッション除去（ping / input / action で延長）
# sweep_interval_ms: 淘汰スイープの間隔
config :network, Network.UDP,
  port: 4001,
  session_timeout_ms: 30_000,
  sweep_interval_ms: 5_000

# ── Network.ZenohBridge（Zenoh フレーム配信・入力受信）────────────────
# true にすると game/room/{room_id}/frame へ publish、
# game/room/*/input/movement, game/room/*/input/action を subscribe する。
# client_desktop 等のリモートクライアント接続時に有効化。
# dev/prod では true、テストでは zenohd を起動しないため false。
config :network, :zenoh_enabled, Mix.env() != :test

# zenohd への接続先。未指定時は Zenohex.Config.default()（マルチキャスト scouting）を使用。
# デフォルトは tcp/127.0.0.1:7447（IPv4 localhost）。リモート zenohd の場合は適宜変更。
config :network, :zenoh_connect, "tcp/localhost:7447"

# ── auth ↔ engine（room_token の JWT 必須化）────────────────────
# AUTH_REQUIRED=true のとき POST /api/room_token に Bearer JWT が必須。
# 既定 false（ローカル・お披露目デモは auth なしで入場可）。
# JWKS: AUTH_JWKS_URL 優先。未設定時は AUTH_BASE_URL + /.well-known/jwks.json。
config :network, :auth_required, false
config :network, :auth_base_url, nil
config :network, :auth_jwks_url, nil
config :network, :jwt_issuer, "alchemy-auth"
config :network, :jwt_audience, "alchemy-platform"

# ── 連合 read-only S2S（運営者間。libcluster スケールアウトとは別層）────
# 既定オフ。有効化は S2S_ENABLED=true（runtime.exs）または下記 enabled: true。
# ワールド一覧はゲーム状態ではなくメタデータのみ（カタログ）。
config :network, Network.S2S,
  enabled: false,
  domain: "alchemy.localhost",
  canonical_url: "http://localhost:4000",
  max_content_status: "General",
  # private_key_pem / private_key_path 未設定時は起動時にエフェメラル RSA を生成（開発用）
  ephemeral_keys: true,
  worlds: [
    %{
      id: "bullet-hell-3d",
      title: "Bullet Hell 3D",
      status: "General",
      path: "/worlds/bullet-hell-3d"
    }
  ],
  peers: []

# ── 使用するコンテンツを指定する（必須。core にコンテンツ名のフォールバックは持たない）。
# 第一級コンテンツ（維持）:
#   Content.CanvasTest    — Canvas / ワールド空間 UI デバッグ
#   Content.BulletHell3D  — 3D 弾幕避け（開発既定）
#   Content.FormulaTest   — Formula / Nodes 検証（`config/formula_test.exs` 参照）
# ローカル開発・動作検証時は上記いずれかに切り替える。本番は config/runtime.exs で設定すること。
config :server, :current, Content.BulletHell3D
config :server, :map, :plain
config :server, :game_events_module, Contents.Events.Game

# 権威 tick（主時間）。許容: 10 / 20 / 30 / 60。デフォルト 20（推奨）。
# 60 は非推奨（ハードリアルタイム保証なし）。実行時は TICK_HZ で上書き可（runtime.exs）。
config :server, :tick_hz, 20

# FormulaStore の synced 更新をネットワークブロードキャストする MFA。
# 形式: {Mod, Fun, []}。apply(Mod, Fun, [room_id, event]) が呼ばれる。
# 未設定・nil のときはブロードキャストしない。
# core 単体利用（network 未ロード）の場合は config/test.exs のように nil を設定すること。
config :core, :formula_store_broadcast, {Network.Distributed, :broadcast, []}

import_config "#{config_env()}.exs"
