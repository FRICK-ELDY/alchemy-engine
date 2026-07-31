import Config

# ── 権威 tick Hz（実行時）───────────────────────────────────────
# 例: TICK_HZ=10 mix run --no-halt
# 許容: 10 / 20 / 30 / 60。不正値は Core.Config が 20 にフォールバック。
if tick_hz_str = System.get_env("TICK_HZ") do
  case Integer.parse(String.trim(tick_hz_str)) do
    {hz, ""} -> config :server, :tick_hz, hz
    _ -> :ok
  end
end

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
# RoomToken（Phoenix.Token）はこの値で署名される。
# prod で未設定のまま config.exs の公開固定値で起動するとトークン偽造が可能になるため、
# auth と同様に fail-fast する。生成: mix phx.gen.secret
if config_env() == :prod do
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  config :network, Network.Endpoint, secret_key_base: secret_key_base
else
  if secret = System.get_env("SECRET_KEY_BASE") do
    config :network, Network.Endpoint, secret_key_base: secret
  end
end
