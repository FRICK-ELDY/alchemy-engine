defmodule Server.MainRoom do
  @moduledoc """
  起動時、および `Core.RoomSupervisor` の再起動後に `:main` を生成する。

  `init/1` は待たずに戻る。`:main` の生成と、旧プロセスが名前を離すまでの再試行は
  `handle_info` で行う。待ちはスーパーバイザの起動を止めない。
  """

  use GenServer

  # 旧 :main が Registry とローカル名を離すまでの再試行。100 * 50ms。
  @max_attempts 100
  @retry_ms 50

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    send(self(), {:ensure_default_room, @max_attempts})
    {:ok, %{}}
  end

  @impl true
  def handle_info({:ensure_default_room, 0}, state) do
    {:stop, :main_room_not_started, state}
  end

  def handle_info({:ensure_default_room, attempts}, state) do
    case try_start_default_room() do
      :ok ->
        {:noreply, state}

      :wait ->
        Process.send_after(self(), {:ensure_default_room, attempts - 1}, @retry_ms)
        {:noreply, state}

      {:error, reason} ->
        {:stop, reason, state}
    end
  end

  defp try_start_default_room do
    case Core.RoomRegistry.get_loop(:main) do
      {:ok, pid} ->
        if supervised_main?(pid), do: :ok, else: :wait

      :error ->
        start_or_wait()
    end
  end

  defp start_or_wait do
    case Core.RoomSupervisor.start_room(:main) do
      {:ok, pid} ->
        if supervised_main?(pid), do: :ok, else: :wait

      {:error, :already_started} ->
        :wait

      # :main の Game は Contents.Events.Game というローカル名を取る。
      # 旧プロセスが名前を離す前は {:already_started, pid} になる。その pid が
      # 今の RoomSupervisor 配下でなければ、死ぬまで待ってから作り直す。
      {:error, {:already_started, pid}} ->
        if supervised_main?(pid), do: :ok, else: :wait

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp supervised_main?(pid) when is_pid(pid) do
    Process.alive?(pid) and Enum.any?([pid | ancestors(pid)], &room_supervisor_child?/1)
  end

  # `$ancestors` の先頭だけだと、Game と RoomSupervisor の間にプロセスが増えたときに
  # 生きている :main を監督下と認めない。
  defp ancestors(pid) do
    case Process.info(pid, :dictionary) do
      {:dictionary, dict} ->
        dict
        |> Keyword.get(:"$ancestors", [])
        |> Enum.filter(&is_pid/1)

      _ ->
        []
    end
  end

  defp room_supervisor_child?(pid) do
    Core.RoomSupervisor
    |> DynamicSupervisor.which_children()
    |> Enum.any?(fn {_id, child, _type, _modules} -> child == pid end)
  catch
    :exit, _ -> false
  end
end
