defmodule Auth.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    maybe_configure_mailer()

    children = [
      AuthWeb.Telemetry,
      Auth.RateLimit,
      Auth.Repo,
      Auth.TokenCleanup,
      Auth.Token.Keys,
      {DNSCluster, query: Application.get_env(:auth, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Auth.PubSub},
      # Start a worker by calling: Auth.Worker.start_link(arg)
      # {Auth.Worker, arg},
      # Start to serve requests, typically the last entry
      AuthWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Auth.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp maybe_configure_mailer do
    if Application.get_env(:auth, :configure_mailer_at_startup, false) do
      Auth.MailConfig.configure!()
    end

    :ok
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    AuthWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
