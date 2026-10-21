defmodule Auth.TokenCleanup do
  @moduledoc """
  Periodically removes expired JWT revocation records and stale refresh tokens.
  """

  use GenServer

  require Logger

  import Ecto.Query

  alias Auth.Accounts.{RefreshToken, TokenRevocation}
  alias Auth.Repo

  @type cleanup_result :: %{
          revocations: non_neg_integer(),
          refresh_tokens: non_neg_integer()
        }

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec run() :: cleanup_result()
  def run do
    GenServer.call(__MODULE__, :run)
  end

  @doc false
  @spec run_now() :: cleanup_result()
  def run_now do
    do_run()
  end

  @impl true
  def init(_opts) do
    schedule_cleanup()
    {:ok, %{}}
  end

  @impl true
  def handle_call(:run, _from, state) do
    {:reply, do_run(), state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    result = do_run()

    Logger.info(
      inspect(%{
        event: "auth.token_cleanup.completed",
        revocations: result.revocations,
        refresh_tokens: result.refresh_tokens
      })
    )

    schedule_cleanup()
    {:noreply, state}
  end

  defp do_run do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %{
      revocations: delete_expired_revocations(now),
      refresh_tokens: delete_stale_refresh_tokens(now)
    }
  end

  defp delete_expired_revocations(now) do
    {count, _} =
      from(r in TokenRevocation, where: r.expires_at < ^now)
      |> Repo.delete_all()

    count
  end

  defp delete_stale_refresh_tokens(now) do
    inactivity_days = Application.fetch_env!(:auth, :refresh_token_inactivity_days)
    grace_days = Application.fetch_env!(:auth, :refresh_token_gc_grace_days)

    revoked_cutoff = DateTime.add(now, -grace_days * 86_400, :second)

    inactive_cutoff =
      DateTime.add(now, -(inactivity_days + grace_days) * 86_400, :second)

    {count, _} =
      from(r in RefreshToken,
        where:
          (not is_nil(r.revoked_at) and r.revoked_at < ^revoked_cutoff) or
            r.last_used_at < ^inactive_cutoff
      )
      |> Repo.delete_all()

    count
  end

  defp schedule_cleanup do
    interval_ms = Application.fetch_env!(:auth, :token_cleanup_interval_ms)
    Process.send_after(self(), :cleanup, interval_ms)
  end
end
