defmodule Auth.Repo do
  use AshPostgres.Repo,
    otp_app: :auth

  @impl true
  def installed_extensions do
    ["ash-functions", "citext", "uuid-ossp"]
  end

  @impl true
  def min_pg_version do
    %Version{major: 16, minor: 0, patch: 0}
  end
end
