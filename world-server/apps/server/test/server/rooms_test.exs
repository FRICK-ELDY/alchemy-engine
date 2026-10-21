defmodule Server.RoomsTest do
  use ExUnit.Case, async: false

  test "RoomSupervisor 再起動後に :main が新しいスーパーバイザの子として戻る" do
    assert {:ok, old_pid} = Core.RoomRegistry.get_loop(:main)
    sup = Process.whereis(Core.RoomSupervisor)
    assert is_pid(sup)

    ref = Process.monitor(sup)
    Process.exit(sup, :kill)
    assert_receive {:DOWN, ^ref, :process, ^sup, :killed}, 1_000

    new_sup = wait_for_new_supervisor(sup, 100)
    new_pid = wait_for_supervised_main(old_pid, 100)
    assert new_pid != old_pid
    assert Process.alive?(new_pid)
    assert supervised_under?(new_sup, new_pid)
  end

  test "Registry に残った生きている旧 pid を :main とみなさない" do
    on_exit(&ensure_supervised_main/0)

    stop_supervised_main!()
    {:ok, decoy} = Server.RoomsTest.Decoy.start_link()
    assert {:ok, ^decoy} = Core.RoomRegistry.get_loop(:main)
    refute child_of?(Process.whereis(Core.RoomSupervisor), decoy)

    assert {:ok, _main_room} = restart_main_room()

    pid = wait_for_supervised_main(decoy, 100)
    assert pid != decoy
    refute Process.alive?(decoy)
  end

  test "ローカル名が残っている間は already_started を待ってから :main を作る" do
    on_exit(&ensure_supervised_main/0)

    stop_supervised_main!()
    assert :error = Core.RoomRegistry.get_loop(:main)

    {:ok, holder} = Server.RoomsTest.NameHolder.start_link()
    assert Process.whereis(Contents.Events.Game) == holder

    assert {:ok, _main_room} = restart_main_room()

    pid = wait_for_supervised_main(holder, 100)
    assert pid != holder
    assert Process.whereis(Contents.Events.Game) == pid
    assert supervised_under?(Process.whereis(Core.RoomSupervisor), pid)
  end

  defp restart_main_room do
    :ok = Supervisor.terminate_child(Server.Rooms, Server.MainRoom)
    Supervisor.restart_child(Server.Rooms, Server.MainRoom)
  end

  defp stop_supervised_main! do
    sup = Process.whereis(Core.RoomSupervisor)

    case Core.RoomRegistry.get_loop(:main) do
      {:ok, pid} ->
        if supervised_game?(sup, pid) do
          assert :ok = Core.RoomSupervisor.stop_room(:main)
        end

      :error ->
        :ok
    end
  end

  defp ensure_supervised_main do
    sup = Process.whereis(Core.RoomSupervisor)

    case Core.RoomRegistry.get_loop(:main) do
      {:ok, pid} ->
        if supervised_game?(sup, pid) do
          :ok
        else
          if Process.alive?(pid), do: GenServer.stop(pid, :normal, 1_000)
          Core.RoomSupervisor.start_room(:main)
        end

      :error ->
        Core.RoomSupervisor.start_room(:main)
    end
  end

  defp wait_for_new_supervisor(_old_sup, 0) do
    flunk("RoomSupervisor was not restarted")
  end

  defp wait_for_new_supervisor(old_sup, attempts) do
    case Process.whereis(Core.RoomSupervisor) do
      pid when is_pid(pid) and pid != old_sup ->
        pid

      _ ->
        pause(fn -> wait_for_new_supervisor(old_sup, attempts - 1) end)
    end
  end

  defp wait_for_supervised_main(_excluded, 0) do
    flunk(":main was not restored as a child of RoomSupervisor")
  end

  defp wait_for_supervised_main(excluded, attempts) do
    sup = Process.whereis(Core.RoomSupervisor)

    case Core.RoomRegistry.get_loop(:main) do
      {:ok, pid} when is_pid(pid) and pid != excluded ->
        if Process.alive?(pid) and supervised_game?(sup, pid) do
          pid
        else
          pause(fn -> wait_for_supervised_main(excluded, attempts - 1) end)
        end

      _ ->
        pause(fn -> wait_for_supervised_main(excluded, attempts - 1) end)
    end
  end

  defp supervised_game?(sup, game_pid) when is_pid(sup) and is_pid(game_pid) do
    supervised_under?(sup, game_pid)
  end

  defp supervised_under?(sup, pid) when is_pid(sup) and is_pid(pid) do
    Enum.any?([pid | ancestors(pid)], &child_of?(sup, &1))
  end

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

  defp child_of?(sup, pid) when is_pid(sup) and is_pid(pid) do
    sup
    |> DynamicSupervisor.which_children()
    |> Enum.any?(fn {_id, child, _type, _modules} -> child == pid end)
  catch
    :exit, _ -> false
  end

  defp child_of?(_, _), do: false

  defp pause(continue) do
    receive do
    after
      50 -> continue.()
    end
  end
end
