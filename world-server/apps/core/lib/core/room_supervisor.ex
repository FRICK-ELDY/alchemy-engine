defmodule Core.RoomSupervisor do
  @moduledoc """
  ルーム単位のサブツリー（`config :server, :room_module`）を管理する DynamicSupervisor。

  子はイベントループそのものではない。各ルームのスーパーバイザが
  シーンスタックとイベントループを持つ。
  """

  use DynamicSupervisor
  require Logger

  @default_room :main

  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def start_room(room_id) when is_binary(room_id) or is_atom(room_id) do
    cond do
      match?({:ok, _}, Core.RoomRegistry.get_room(room_id)) ->
        {:error, :already_started}

      match?({:ok, _}, Core.RoomRegistry.get_loop(room_id)) ->
        {:error, :already_started}

      true ->
        module =
          Application.get_env(:server, :room_module) ||
            raise "config :server, :room_module is required"

        child_spec = %{
          id: {:room, room_id},
          start: {module, :start_link, [[room_id: room_id]]},
          type: :supervisor,
          restart: :permanent
        }

        case DynamicSupervisor.start_child(__MODULE__, child_spec) do
          {:ok, pid} ->
            Logger.info("[ROOM] Started room #{inspect(room_id)}")
            {:ok, pid}

          other ->
            normalize_start_error(other)
        end
    end
  end

  # Supervisor は子の {:already_started, pid} を
  # {:shutdown, {:failed_to_start_child, id, reason}} で包む。
  # MainRoom は包む前の形で「名前が空くまで待つ」を判断する。
  defp normalize_start_error(
         {:error, {:shutdown, {:failed_to_start_child, _id, {:already_started, pid}}}}
       ) do
    {:error, {:already_started, pid}}
  end

  defp normalize_start_error({:error, {:already_started, pid}}) do
    {:error, {:already_started, pid}}
  end

  defp normalize_start_error(other), do: other

  def stop_room(room_id) when is_binary(room_id) or is_atom(room_id) do
    case Core.RoomRegistry.get_room(room_id) do
      {:ok, pid} ->
        DynamicSupervisor.terminate_child(__MODULE__, pid)
        Core.FrameCache.delete(room_id)
        Logger.info("[ROOM] Stopped room #{inspect(room_id)}")
        :ok

      :error ->
        stop_stray_loop(room_id)
    end
  end

  # ルームサブツリーが無いのにループだけ Registry に残っている。
  # start_room/1 はこれを起動済みとみなすので、停止でも同じキーを外す。
  defp stop_stray_loop(room_id) do
    case Core.RoomRegistry.get_loop(room_id) do
      {:ok, pid} ->
        stop_stray_pid(room_id, pid)

      :error ->
        {:error, :not_found}
    end
  end

  defp stop_stray_pid(room_id, pid) do
    ref = Process.monitor(pid)

    try do
      if Process.alive?(pid), do: GenServer.stop(pid, :normal, 1_000)
    catch
      :exit, _ -> Process.exit(pid, :kill)
    end

    case await_loop_gone(room_id, pid, ref, 50) do
      :ok ->
        Core.FrameCache.delete(room_id)
        Logger.info("[ROOM] Stopped stray loop #{inspect(room_id)}")
        :ok

      {:error, :not_stopped} ->
        Logger.error("[ROOM] stray loop #{inspect(room_id)} did not leave the registry")
        {:error, :not_stopped}
    end
  end

  # kill は非同期で、Registry のキーもプロセスの DOWN のあとで外れる。
  # ここが :ok を返す時点で start_room/1 は同じ room_id を起動できる。
  defp await_loop_gone(room_id, pid, ref, attempts) do
    receive do
      {:DOWN, ^ref, :process, ^pid, _} -> :ok
    after
      20 -> :ok
    end

    case Core.RoomRegistry.get_loop(room_id) do
      {:ok, ^pid} when attempts > 0 ->
        await_loop_gone(room_id, pid, ref, attempts - 1)

      {:ok, ^pid} ->
        Process.demonitor(ref, [:flush])
        {:error, :not_stopped}

      _ ->
        Process.demonitor(ref, [:flush])
        :ok
    end
  end

  def list_rooms do
    Core.RoomRegistry.list_rooms()
  end

  def default_room, do: @default_room

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
