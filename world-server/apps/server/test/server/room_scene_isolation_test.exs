defmodule Server.RoomSceneIsolationTest do
  use ExUnit.Case, async: false

  @a "scene_iso_a"
  @b "scene_iso_b"

  setup do
    assert {:ok, sup_a} = Core.RoomSupervisor.start_room(@a)
    assert {:ok, sup_b} = Core.RoomSupervisor.start_room(@b)

    on_exit(fn ->
      Core.RoomSupervisor.stop_room(@a)
      Core.RoomSupervisor.stop_room(@b)
    end)

    {:ok, sup_a: sup_a, sup_b: sup_b}
  end

  test "2 ルームのスコアとシーンは互いを上書きしない", %{sup_a: sup_a, sup_b: sup_b} do
    content = Application.fetch_env!(:server, :current)
    runner_a = content.flow_runner(@a)
    runner_b = content.flow_runner(@b)
    runner_main = content.flow_runner(:main)

    assert is_pid(runner_a)
    assert is_pid(runner_b)
    assert is_pid(runner_main)
    assert runner_a != runner_b
    assert runner_a != runner_main
    assert runner_b != runner_main

    assert stack_child?(sup_a, runner_a)
    assert stack_child?(sup_b, runner_b)
    refute stack_child?(sup_a, runner_b)

    assert {:ok, %{scene_type: type_b}} = Contents.Scenes.Stack.current(runner_b)
    assert {:ok, %{scene_type: type_main}} = Contents.Scenes.Stack.current(runner_main)

    playing = content.playing_scene()

    :ok =
      Contents.Scenes.Stack.update_by_scene_type(runner_a, playing, fn state ->
        Map.put(state, :score, 42)
      end)

    # SampleOsc の game_over_scene/0 は :playing を返す。シーンの分離は
    # scene_init が受け付ける :game_over を積んで確認する。
    :ok = Contents.Scenes.Stack.push_scene(runner_a, :game_over, %{})

    assert Contents.Scenes.Stack.get_scene_state(runner_a, playing).score == 42
    assert {:ok, %{scene_type: :game_over}} = Contents.Scenes.Stack.current(runner_a)

    b_playing = Contents.Scenes.Stack.get_scene_state(runner_b, playing)
    refute Map.get(b_playing, :score) == 42
    assert {:ok, %{scene_type: ^type_b}} = Contents.Scenes.Stack.current(runner_b)

    main_playing = Contents.Scenes.Stack.get_scene_state(runner_main, playing)
    refute Map.get(main_playing, :score) == 42
    assert {:ok, %{scene_type: ^type_main}} = Contents.Scenes.Stack.current(runner_main)
  end

  test ":main がソケットを保持し、後から起動したルームは待受しない" do
    {:ok, probe} = :gen_udp.open(0, [:binary])
    {:ok, port} = :inet.port(probe)
    :gen_udp.close(probe)

    previous = Application.get_env(:contents, :osc_listen_port)
    Application.put_env(:contents, :osc_listen_port, port)

    on_exit(fn ->
      restore_osc_port(previous)
      Core.RoomSupervisor.stop_room("listen_hold_a")
      Core.RoomSupervisor.stop_room("listen_hold_b")
      Core.RoomSupervisor.stop_room(:main)
      Core.RoomSupervisor.start_room(:main)
    end)

    assert :ok = Core.RoomSupervisor.stop_room(:main)
    assert {:ok, _} = await_main()

    content = Application.fetch_env!(:server, :current)
    playing = content.playing_scene()
    runner_main = content.flow_runner(:main)
    assert receiver_listening?(runner_main, playing)

    assert {:ok, _} = Core.RoomSupervisor.start_room("listen_hold_a")
    assert {:ok, _} = Core.RoomSupervisor.start_room("listen_hold_b")

    refute receiver_listening?(content.flow_runner("listen_hold_a"), playing)
    refute receiver_listening?(content.flow_runner("listen_hold_b"), playing)
    assert receiver_listening?(runner_main, playing)
  end

  test "ループが落ちてもシーン state は残る", %{sup_a: sup_a} do
    content = Application.fetch_env!(:server, :current)
    runner = content.flow_runner(@a)
    playing = content.playing_scene()

    :ok =
      Contents.Scenes.Stack.update_by_scene_type(runner, playing, fn state ->
        Map.put(state, :score, 7)
      end)

    {:ok, loop} = Core.RoomRegistry.get_loop(@a)
    ref = Process.monitor(loop)
    Process.exit(loop, :kill)
    assert_receive {:DOWN, ^ref, :process, ^loop, :killed}, 1_000

    new_loop = wait_loop(loop, 20)
    assert new_loop != loop
    assert Process.alive?(runner)
    assert stack_child?(sup_a, runner)
    assert Contents.Scenes.Stack.get_scene_state(runner, playing).score == 7
  end

  test "stop が届かない迷子ループも Registry から外してから起動できる" do
    id = "stuck_loop_only"
    parent = self()

    pid =
      spawn(fn ->
        :ok = Core.RoomRegistry.register(id)
        send(parent, :registered)
        Process.sleep(:infinity)
      end)

    assert_receive :registered, 1_000

    on_exit(fn ->
      if Process.alive?(pid), do: Process.exit(pid, :kill)
      Core.RoomSupervisor.stop_room(id)
    end)

    assert {:error, :already_started} = Core.RoomSupervisor.start_room(id)
    assert :ok = Core.RoomSupervisor.stop_room(id)
    refute Process.alive?(pid)
    assert :error = Core.RoomRegistry.get_loop(id)

    assert {:ok, _sup} = Core.RoomSupervisor.start_room(id)
  end

  test "ループだけの room_id は stop_room で外してから起動できる" do
    id = "stray_loop_only"
    {:ok, pid} = Contents.Events.Game.start_link(room_id: id)

    on_exit(fn ->
      Core.RoomSupervisor.stop_room(id)
    end)

    assert {:error, :already_started} = Core.RoomSupervisor.start_room(id)
    assert :ok = Core.RoomSupervisor.stop_room(id)
    refute Process.alive?(pid)

    assert {:ok, _sup} = Core.RoomSupervisor.start_room(id)
    assert {:ok, _} = Core.RoomRegistry.get_room(id)
    assert {:ok, loop} = Core.RoomRegistry.get_loop(id)
    assert is_pid(Application.fetch_env!(:server, :current).flow_runner(id))
    assert loop != pid
  end

  defp wait_loop(_old, 0), do: flunk("loop was not restarted")

  defp wait_loop(old, attempts) do
    case Core.RoomRegistry.get_loop(@a) do
      {:ok, pid} when pid != old ->
        pid

      _ ->
        Process.sleep(50)
        wait_loop(old, attempts - 1)
    end
  end

  defp await_main(attempts \\ 20)
  defp await_main(0), do: flunk(":main was not started")

  defp await_main(attempts) do
    case Core.RoomSupervisor.start_room(:main) do
      {:ok, pid} ->
        {:ok, pid}

      {:error, :already_started} ->
        case Core.RoomRegistry.get_loop(:main) do
          {:ok, pid} ->
            {:ok, pid}

          :error ->
            Process.sleep(50)
            await_main(attempts - 1)
        end

      {:error, {:already_started, pid}} ->
        {:ok, pid}
    end
  end

  defp restore_osc_port(nil), do: Application.delete_env(:contents, :osc_listen_port)
  defp restore_osc_port(port), do: Application.put_env(:contents, :osc_listen_port, port)

  defp receiver_listening?(runner, playing) do
    state = Contents.Scenes.Stack.get_scene_state(runner, playing)
    pid = Map.get(state, :receiver)

    is_pid(pid) and Process.alive?(pid) and
      Contents.Components.Category.Network.Osc.Receiver.fields(pid).is_listening
  end

  defp stack_child?(sup, stack) when is_pid(sup) and is_pid(stack) do
    sup
    |> Supervisor.which_children()
    |> Enum.any?(fn {_id, pid, _type, _modules} -> pid == stack end)
  end
end
