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

auth_jwks_url_env = System.get_env("AUTH_JWKS_URL")
auth_base_url_env = System.get_env("AUTH_BASE_URL")
jwt_issuer_env = System.get_env("JWT_ISSUER")
jwt_audience_env = System.get_env("JWT_AUDIENCE")

jwks_ok? = is_binary(auth_jwks_url_env) and String.trim(auth_jwks_url_env) != ""

if jwks_ok? do
  config :network, :auth_jwks_url, String.trim(auth_jwks_url_env)
end

base_ok? = is_binary(auth_base_url_env) and String.trim(auth_base_url_env) != ""

if base_ok? do
  config :network, :auth_base_url, String.trim_trailing(String.trim(auth_base_url_env), "/")
end

if is_binary(jwt_issuer_env) and String.trim(jwt_issuer_env) != "" do
  config :network, :jwt_issuer, String.trim(jwt_issuer_env)
end

if is_binary(jwt_audience_env) and String.trim(jwt_audience_env) != "" do
  config :network, :jwt_audience, String.trim(jwt_audience_env)
end

if auth_required? and not (jwks_ok? or base_ok?) do
  raise """
  AUTH_REQUIRED is enabled but neither AUTH_JWKS_URL nor AUTH_BASE_URL is set.
  Example: AUTH_BASE_URL=http://localhost:4002
  """
end

# ── 連合 read-only S2S ─────────────────────────────────────────────
# S2S_ENABLED=true|1 で GET /.well-known/alchemy-s2s.json と
# GET /api/s2s/worlds（呼び出し元インスタンス JWT 必須）を公開する。
# 環境変数が無い項目は config.exs の値を維持する。
s2s_opts = []

s2s_opts =
  case System.get_env("S2S_ENABLED") do
    v when v in ~w(true 1) -> Keyword.put(s2s_opts, :enabled, true)
    v when v in ~w(false 0) -> Keyword.put(s2s_opts, :enabled, false)
    _ -> s2s_opts
  end

s2s_domain_env = System.get_env("S2S_DOMAIN")

s2s_opts =
  if is_binary(s2s_domain_env) and String.trim(s2s_domain_env) != "" do
    Keyword.put(s2s_opts, :domain, String.trim(s2s_domain_env))
  else
    s2s_opts
  end

s2s_canonical_env = System.get_env("S2S_CANONICAL_URL")

s2s_opts =
  if is_binary(s2s_canonical_env) and String.trim(s2s_canonical_env) != "" do
    Keyword.put(
      s2s_opts,
      :canonical_url,
      String.trim_trailing(String.trim(s2s_canonical_env), "/")
    )
  else
    s2s_opts
  end

s2s_status_env = System.get_env("S2S_MAX_CONTENT_STATUS")

s2s_opts =
  if is_binary(s2s_status_env) and String.trim(s2s_status_env) != "" do
    Keyword.put(s2s_opts, :max_content_status, String.trim(s2s_status_env))
  else
    s2s_opts
  end

s2s_pem_env = System.get_env("S2S_PRIVATE_KEY_PEM")
s2s_path_env = System.get_env("S2S_PRIVATE_KEY_PATH")

s2s_opts =
  cond do
    is_binary(s2s_pem_env) and String.trim(s2s_pem_env) != "" ->
      Keyword.put(s2s_opts, :private_key_pem, s2s_pem_env)

    is_binary(s2s_path_env) and String.trim(s2s_path_env) != "" ->
      Keyword.put(s2s_opts, :private_key_path, String.trim(s2s_path_env))

    true ->
      s2s_opts
  end

if s2s_opts != [] do
  existing_s2s = Application.get_env(:network, Network.S2S, [])
  config :network, Network.S2S, Keyword.merge(existing_s2s, s2s_opts)
end
