defmodule Core.RoomRegistry do
  @moduledoc """
  ルーム ID → GameEvents pid のマッピング用 Registry。
  """

  @registry __MODULE__

  def get_loop(room_id) when is_binary(room_id) or is_atom(room_id) do
    case Registry.lookup(@registry, room_id) do
      [{pid, _}] when is_pid(pid) -> {:ok, pid}
      [] -> :error
    end
  end

  def list_rooms do
    @registry
    |> Registry.select([
      {{:"$1", :_, :_}, [{:orelse, {:is_atom, :"$1"}, {:is_binary, :"$1"}}], [:"$1"]}
    ])
  end

  @doc """
  ルームスーパーバイザ（`Server.Room`）の pid。イベントループとは別キー。
  """
  def get_room(room_id) when is_binary(room_id) or is_atom(room_id) do
    case Registry.lookup(@registry, {:room_sup, room_id}) do
      [{pid, _}] when is_pid(pid) -> {:ok, pid}
      [] -> :error
    end
  end

  def register(room_id) when is_binary(room_id) or is_atom(room_id) do
    case Registry.register(@registry, room_id, []) do
      {:ok, _} -> :ok
      {:error, {:already_registered, _pid}} -> :ok
      other -> other
    end
  end

  def unregister(room_id) when is_binary(room_id) or is_atom(room_id) do
    Registry.unregister(@registry, room_id)
  end
end
