defmodule Contents.Events.GameMultiRoomTickTest do
  use ExUnit.Case, async: false

  @moduletag :multi_room_tick

  @room_id "multi_room_tick_test"

  setup do
    ensure_room_registry!()

    case Contents.Events.Game.start_link(room_id: @room_id) do
      {:ok, pid} ->
        on_exit(fn ->
          if Process.alive?(pid), do: GenServer.stop(pid, :normal, 1000)
        end)

        {:ok, pid: pid}

      {:error, {:already_started, pid}} ->
        {:ok, pid: pid}
    end
  end

  test "非 :main ルームでも :elixir_frame_tick で frame_count が進む", %{pid: pid} do
    %{room_id: @room_id, frame_count: before_count} = :sys.get_state(pid)

    # 権威 tick（既定 20Hz = 50ms）を数回待つ
    Process.sleep(Core.Config.tick_ms() * 3 + 30)

    %{frame_count: after_count} = :sys.get_state(pid)
    assert after_count > before_count
  end

  defp ensure_room_registry! do
    case Process.whereis(Core.RoomRegistry) do
      nil ->
        case Registry.start_link(keys: :unique, name: Core.RoomRegistry) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
        end

      _pid ->
        :ok
    end
  end
end
