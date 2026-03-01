import Config

# ── GameNetwork.Endpoint（実行時設定）────────────────────────────────
# GAME_NETWORK_PORT 環境変数でポートを上書きできる。
# 例: GAME_NETWORK_PORT=8080 mix run --no-halt
if port_str = System.get_env("GAME_NETWORK_PORT") do
  config :game_network, GameNetwork.Endpoint,
    http: [port: String.to_integer(port_str)]
end

# ── セーブデータ HMAC 署名鍵（実行時設定）────────────────────────────
# 本番環境では必ず環境変数で上書きすること。
if secret = System.get_env("SAVE_HMAC_SECRET") do
  config :game_engine, :save_hmac_secret, secret
end
