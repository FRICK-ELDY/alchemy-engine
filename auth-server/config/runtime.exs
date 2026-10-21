import Config

database_ssl? = System.get_env("DATABASE_SSL") in ~w(true 1)
database_ssl_ca = System.get_env("DATABASE_SSL_CA_CERT")

repo_ssl_verify_opts = [
  verify: :verify_peer,
  customize_hostname_check: [
    match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
  ]
]

repo_ssl =
  cond do
    database_ssl? && is_binary(database_ssl_ca) && database_ssl_ca != "" ->
      [ssl: [cacertfile: database_ssl_ca] ++ repo_ssl_verify_opts]

    database_ssl? ->
      [ssl: true]

    true ->
      []
  end

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/auth start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :auth, AuthWeb.Endpoint, server: true
end

config :auth, AuthWeb.Endpoint, http: [port: String.to_integer(System.get_env("PORT", "4002"))]

if config_env() != :test and System.get_env("DATABASE_URL") do
  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :auth,
         Auth.Repo,
         Keyword.merge(
           [
             url: System.get_env("DATABASE_URL"),
             pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
             socket_options: maybe_ipv6
           ],
           repo_ssl
         )
end

if config_env() != :test and System.get_env("BIND_ALL") in ~w(true 1) do
  config :auth, AuthWeb.Endpoint,
    http: [
      ip: {0, 0, 0, 0},
      port: String.to_integer(System.get_env("PORT", "4002"))
    ],
    server: true
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :auth,
         Auth.Repo,
         Keyword.merge(
           [
             url: database_url,
             pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
             # For machines with several cores, consider starting multiple pools of `pool_size`
             # pool_count: 4,
             socket_options: maybe_ipv6
           ],
           repo_ssl
         )

  config :auth,
         :jwt_private_key_path,
         System.get_env("JWT_PRIVATE_KEY_PATH") || "priv/jwt_private.pem"

  jwt_verification_key_paths =
    case System.get_env("JWT_VERIFICATION_KEY_PATHS") do
      nil ->
        []

      "" ->
        []

      value ->
        value
        |> String.split(",", trim: true)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
    end

  config :auth, :jwt_verification_key_paths, jwt_verification_key_paths

  if issuer = System.get_env("JWT_ISSUER") do
    config :auth, :jwt_issuer, issuer
  end

  if audience = System.get_env("JWT_AUDIENCE") do
    config :auth, :jwt_audience, audience
  end

  config :auth, :jwt_generate_key_on_startup, false

  trusted_proxies =
    case System.get_env("TRUSTED_PROXIES") do
      nil -> []
      "" -> []
      value -> String.split(value, ",", trim: true)
    end

  config :auth, :trusted_proxies, trusted_proxies

  rate_limit_env_integer = fn name, default ->
    case System.get_env(name) do
      nil -> default
      value -> String.to_integer(value)
    end
  end

  rate_limit_limits = %{
    login: %{
      ip: %{
        limit: rate_limit_env_integer.("AUTH_RATE_LIMIT_LOGIN_IP_LIMIT", 30),
        period_ms: rate_limit_env_integer.("AUTH_RATE_LIMIT_LOGIN_IP_PERIOD_MS", 60_000)
      },
      identifier: %{
        limit: rate_limit_env_integer.("AUTH_RATE_LIMIT_LOGIN_IDENTIFIER_LIMIT", 10),
        period_ms: rate_limit_env_integer.("AUTH_RATE_LIMIT_LOGIN_IDENTIFIER_PERIOD_MS", 60_000)
      }
    },
    register: %{
      ip: %{
        limit: rate_limit_env_integer.("AUTH_RATE_LIMIT_REGISTER_IP_LIMIT", 10),
        period_ms: rate_limit_env_integer.("AUTH_RATE_LIMIT_REGISTER_IP_PERIOD_MS", 3_600_000)
      },
      email: %{
        limit: rate_limit_env_integer.("AUTH_RATE_LIMIT_REGISTER_EMAIL_LIMIT", 5),
        period_ms: rate_limit_env_integer.("AUTH_RATE_LIMIT_REGISTER_EMAIL_PERIOD_MS", 3_600_000)
      }
    },
    refresh: %{
      ip: %{
        limit: rate_limit_env_integer.("AUTH_RATE_LIMIT_REFRESH_IP_LIMIT", 60),
        period_ms: rate_limit_env_integer.("AUTH_RATE_LIMIT_REFRESH_IP_PERIOD_MS", 60_000)
      },
      token: %{
        limit: rate_limit_env_integer.("AUTH_RATE_LIMIT_REFRESH_TOKEN_LIMIT", 20),
        period_ms: rate_limit_env_integer.("AUTH_RATE_LIMIT_REFRESH_TOKEN_PERIOD_MS", 60_000)
      }
    },
    resend_verification: %{
      ip: %{
        limit: rate_limit_env_integer.("AUTH_RATE_LIMIT_RESEND_VERIFICATION_IP_LIMIT", 10),
        period_ms:
          rate_limit_env_integer.("AUTH_RATE_LIMIT_RESEND_VERIFICATION_IP_PERIOD_MS", 3_600_000)
      },
      email: %{
        limit: rate_limit_env_integer.("AUTH_RATE_LIMIT_RESEND_VERIFICATION_EMAIL_LIMIT", 5),
        period_ms:
          rate_limit_env_integer.(
            "AUTH_RATE_LIMIT_RESEND_VERIFICATION_EMAIL_PERIOD_MS",
            3_600_000
          )
      }
    },
    forgot_password: %{
      ip: %{
        limit: rate_limit_env_integer.("AUTH_RATE_LIMIT_FORGOT_PASSWORD_IP_LIMIT", 10),
        period_ms:
          rate_limit_env_integer.("AUTH_RATE_LIMIT_FORGOT_PASSWORD_IP_PERIOD_MS", 3_600_000)
      },
      email: %{
        limit: rate_limit_env_integer.("AUTH_RATE_LIMIT_FORGOT_PASSWORD_EMAIL_LIMIT", 5),
        period_ms:
          rate_limit_env_integer.("AUTH_RATE_LIMIT_FORGOT_PASSWORD_EMAIL_PERIOD_MS", 3_600_000)
      }
    },
    reset_password: %{
      ip: %{
        limit: rate_limit_env_integer.("AUTH_RATE_LIMIT_RESET_PASSWORD_IP_LIMIT", 20),
        period_ms:
          rate_limit_env_integer.("AUTH_RATE_LIMIT_RESET_PASSWORD_IP_PERIOD_MS", 3_600_000)
      }
    },
    verify_email: %{
      ip: %{
        limit: rate_limit_env_integer.("AUTH_RATE_LIMIT_VERIFY_EMAIL_IP_LIMIT", 30),
        period_ms: rate_limit_env_integer.("AUTH_RATE_LIMIT_VERIFY_EMAIL_IP_PERIOD_MS", 3_600_000)
      }
    }
  }

  config :auth, Auth.RateLimit, limits: rate_limit_limits

  if frontend_url = System.get_env("AUTH_FRONTEND_URL") do
    config :auth, :auth_frontend_url, frontend_url
  end

  config :auth, :configure_mailer_at_startup, true

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :auth, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :auth, AuthWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://bandit.hexdocs.pm/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :auth, AuthWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :auth, AuthWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end

if config_env() == :dev and System.get_env("SMTP_RELAY_HOST") do
  relay = System.get_env("SMTP_RELAY_HOST")
  port = String.to_integer(System.get_env("SMTP_RELAY_PORT", "1025"))
  tls? = System.get_env("SMTP_TLS") in ~w(true 1)
  ssl? = System.get_env("SMTP_SSL") in ~w(true 1)

  config :auth, Auth.Mailer,
    adapter: Swoosh.Adapters.SMTP,
    relay: relay,
    port: port,
    ssl: ssl?,
    tls: if(tls?, do: :always, else: :never),
    auth: :never

  config :swoosh, :api_client, false
end
