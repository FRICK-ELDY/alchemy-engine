defmodule AuthWeb.HealthController do
  use AuthWeb, :controller

  @service "alchemy-auth"

  def index(conn, _params) do
    json(conn, %{
      status: "ok",
      service: @service,
      version: app_version()
    })
  end

  defp app_version do
    case Application.spec(:auth, :vsn) do
      nil -> "unknown"
      vsn -> to_string(vsn)
    end
  end
end
