defmodule AuthWeb.Router do
  use AuthWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :rate_limited do
    plug AuthWeb.Plugs.RateLimit
  end

  pipeline :authenticated do
    plug AuthWeb.Plugs.Authenticate
  end

  scope "/api/v1/auth", AuthWeb do
    pipe_through [:api, :rate_limited]

    post "/register", AuthController, :register
    post "/login", AuthController, :login
    post "/refresh", AuthController, :refresh
    post "/verify-email", AuthController, :verify_email
    post "/resend-verification", AuthController, :resend_verification
    post "/forgot-password", AuthController, :forgot_password
    post "/reset-password", AuthController, :reset_password
  end

  scope "/api/v1/auth", AuthWeb do
    pipe_through [:api, :authenticated]

    post "/logout", AuthController, :logout
    post "/change-password", AuthController, :change_password
    post "/deactivate", AuthController, :deactivate
    get "/me", AuthController, :me
  end

  scope "/", AuthWeb do
    get "/health", HealthController, :index
    get "/.well-known/jwks.json", JwksController, :index
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:auth, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through [:fetch_session, :protect_from_forgery]

      live_dashboard "/dashboard", metrics: AuthWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
