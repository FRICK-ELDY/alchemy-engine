import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :auth, Auth.Repo,
  username: "alchemy_auth",
  password: "alchemy_auth",
  hostname: "localhost",
  port: String.to_integer(System.get_env("PGPORT") || "5433"),
  database: "alchemy_auth_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :auth, AuthWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "z+t7ChW1NN1CoZeKB7vESrcxhknbffGzkYWgCshZz1QHIHeGf7TN44KID7We1DrU",
  server: false

# In test we don't send emails
config :auth, Auth.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

config :auth, :jwt_private_key_path, "test/support/fixtures/jwt_private.pem"
config :auth, :jwt_verification_key_paths, []
config :auth, :jwt_generate_key_on_startup, false
config :auth, :trusted_proxies, ["127.0.0.1", "::1"]

config :auth, Auth.RateLimit,
  limits: %{
    login: %{
      ip: %{limit: 10_000, period_ms: 60_000},
      identifier: %{limit: 10_000, period_ms: 60_000}
    },
    register: %{
      ip: %{limit: 10_000, period_ms: 3_600_000},
      email: %{limit: 10_000, period_ms: 3_600_000}
    },
    refresh: %{
      ip: %{limit: 10_000, period_ms: 60_000},
      token: %{limit: 10_000, period_ms: 60_000}
    },
    resend_verification: %{
      ip: %{limit: 10_000, period_ms: 3_600_000},
      email: %{limit: 10_000, period_ms: 3_600_000}
    },
    forgot_password: %{
      ip: %{limit: 10_000, period_ms: 3_600_000},
      email: %{limit: 10_000, period_ms: 3_600_000}
    },
    reset_password: %{
      ip: %{limit: 10_000, period_ms: 3_600_000}
    },
    verify_email: %{
      ip: %{limit: 10_000, period_ms: 3_600_000}
    }
  }
