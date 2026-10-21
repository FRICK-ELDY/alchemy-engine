# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :auth,
  ecto_repos: [Auth.Repo],
  ash_domains: [Auth.Domain],
  generators: [timestamp_type: :utc_datetime],
  jwt_issuer: "alchemy-auth",
  jwt_audience: "alchemy-platform",
  jwt_ttl_seconds: 900,
  jwt_private_key_path: "priv/jwt_private.pem",
  jwt_verification_key_paths: [],
  jwt_generate_key_on_startup: true,
  refresh_token_inactivity_days: 7,
  refresh_token_reuse_grace_seconds: 10,
  refresh_token_gc_grace_days: 7,
  token_cleanup_interval_ms: 3_600_000,
  tos_version: "2026-07-03",
  tos_url: "https://alchemy.frick-eldy.com/terms",
  privacy_policy_url: "https://alchemy.frick-eldy.com/privacy",
  auth_frontend_url: "http://localhost:4000",
  email_verification_token_ttl_hours: 24,
  password_reset_token_ttl_hours: 1,
  mail_from: {"Alchemy Auth", "noreply@alchemy.frick-eldy.com"}

config :auth, :trusted_proxies, []

config :auth, Auth.RateLimit,
  enabled: true,
  limits: %{
    login: %{
      ip: %{limit: 30, period_ms: 60_000},
      identifier: %{limit: 10, period_ms: 60_000}
    },
    register: %{
      ip: %{limit: 10, period_ms: 3_600_000},
      email: %{limit: 5, period_ms: 3_600_000}
    },
    refresh: %{
      ip: %{limit: 60, period_ms: 60_000},
      token: %{limit: 20, period_ms: 60_000}
    },
    resend_verification: %{
      ip: %{limit: 10, period_ms: 3_600_000},
      email: %{limit: 5, period_ms: 3_600_000}
    },
    forgot_password: %{
      ip: %{limit: 10, period_ms: 3_600_000},
      email: %{limit: 5, period_ms: 3_600_000}
    },
    reset_password: %{
      ip: %{limit: 20, period_ms: 3_600_000}
    },
    verify_email: %{
      ip: %{limit: 30, period_ms: 3_600_000}
    }
  }

# Configure the endpoint
config :auth, AuthWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: AuthWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Auth.PubSub,
  live_view: [signing_salt: "PiklzKln"]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :auth, Auth.Mailer, adapter: Swoosh.Adapters.Local

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
