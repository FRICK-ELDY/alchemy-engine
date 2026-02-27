defmodule GameEngine.RoomSupervisor do
  @moduledoc """
  ルーム単位で GameEvents を管理する DynamicSupervisor。
  """

  use DynamicSupervisor
  require Logger

  @default_room :main

  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def start_room(room_id) when is_binary(room_id) or is_atom(room_id) do
    case GameEngine.RoomRegistry.get_loop(room_id) do
      {:ok, _pid} ->
        {:error, :already_started}

      :error ->
        child_spec =
          {GameEngine.GameEvents, [room_id: room_id]}
          |> Supervisor.child_spec(id: {:game_events, room_id})

        case DynamicSupervisor.start_child(__MODULE__, child_spec) do
          {:ok, pid} ->
            Logger.info("[ROOM] Started room #{inspect(room_id)}")
            {:ok, pid}

          other ->
            other
        end
    end
  end

  def stop_room(room_id) when is_binary(room_id) or is_atom(room_id) do
    case GameEngine.RoomRegistry.get_loop(room_id) do
      {:ok, pid} ->
        DynamicSupervisor.terminate_child(__MODULE__, pid)
        Logger.info("[ROOM] Stopped room #{inspect(room_id)}")
        :ok

      :error ->
        {:error, :not_found}
    end
  end

  def list_rooms do
    GameEngine.RoomRegistry.list_rooms()
  end

  def default_room, do: @default_room

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
