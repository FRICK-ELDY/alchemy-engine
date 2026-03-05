import Config

# ── Network.Endpoint（実行時設定）────────────────────────────────
# NETWORK_PORT 環境変数でポートを上書きできる。
# 例: NETWORK_PORT=8080 mix run --no-halt
if port_str = System.get_env("NETWORK_PORT") do
  config :network, Network.Endpoint,
    http: [port: String.to_integer(port_str)]
end

# ── Network.UDP（実行時設定）─────────────────────────────────────
if udp_port_str = System.get_env("NETWORK_UDP_PORT") do
  config :network, Network.UDP,
    port: String.to_integer(udp_port_str)
end

# ── Network.Endpoint secret_key_base（本番向け）──────────────────
# 本番では mix phx.gen.secret で生成した値を SECRET_KEY_BASE に設定すること。
if secret = System.get_env("SECRET_KEY_BASE") do
  config :network, Network.Endpoint, secret_key_base: secret
end

# ── セーブデータ HMAC 署名鍵（実行時設定）────────────────────────────
# 本番環境では必ず環境変数で上書きすること。
if secret = System.get_env("SAVE_HMAC_SECRET") do
  config :core, :save_hmac_secret, secret
end
