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
# "" は Elixir では truthy なので、nil だけでなく空・空白のみも拒否する。
if config_env() == :prod do
  secret_key_base = System.get_env("SECRET_KEY_BASE")

  if is_nil(secret_key_base) or String.trim(secret_key_base) == "" do
    raise """
    environment variable SECRET_KEY_BASE is missing.
    You can generate one by calling: mix phx.gen.secret
    """
  end

  config :network, Network.Endpoint, secret_key_base: secret_key_base
else
  secret = System.get_env("SECRET_KEY_BASE")

  if is_binary(secret) and String.trim(secret) != "" do
    config :network, Network.Endpoint, secret_key_base: secret
  end
end

# ── auth ↔ engine（AUTH_REQUIRED / JWKS）─────────────────────────
# AUTH_REQUIRED=true|1 で POST /api/room_token に Bearer JWT 必須。
# 未設定・空・それ以外は false（デモ・ローカル既定）。
auth_required? =
  case System.get_env("AUTH_REQUIRED") do
    v when v in ~w(true 1) -> true
    _ -> false
  end

config :network, :auth_required, auth_required?

if jwks_url = System.get_env("AUTH_JWKS_URL") do
  if is_binary(jwks_url) and String.trim(jwks_url) != "" do
    config :network, :auth_jwks_url, String.trim(jwks_url)
  end
end

if base_url = System.get_env("AUTH_BASE_URL") do
  if is_binary(base_url) and String.trim(base_url) != "" do
    config :network, :auth_base_url, String.trim_trailing(String.trim(base_url), "/")
  end
end

if issuer = System.get_env("JWT_ISSUER") do
  if is_binary(issuer) and String.trim(issuer) != "" do
    config :network, :jwt_issuer, String.trim(issuer)
  end
end

if audience = System.get_env("JWT_AUDIENCE") do
  if is_binary(audience) and String.trim(audience) != "" do
    config :network, :jwt_audience, String.trim(audience)
  end
end

if auth_required? do
  jwks = System.get_env("AUTH_JWKS_URL")
  base = System.get_env("AUTH_BASE_URL")

  jwks_ok? = is_binary(jwks) and String.trim(jwks) != ""
  base_ok? = is_binary(base) and String.trim(base) != ""

  unless jwks_ok? or base_ok? do
    raise """
    AUTH_REQUIRED is enabled but neither AUTH_JWKS_URL nor AUTH_BASE_URL is set.
    Example: AUTH_BASE_URL=http://localhost:4002
    """
  end
end
