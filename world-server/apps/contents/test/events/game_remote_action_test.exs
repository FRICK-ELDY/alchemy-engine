defmodule Contents.Events.GameRemoteActionTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Contents.Events.RemoteActionFixture

  @room_id "remote_action_test"

  setup do
    ensure_room_registry!()
    ensure_scene_registry!()

    stack =
      case Contents.Scenes.Stack.start_link(
             content_module: RemoteActionFixture,
             room_id: @room_id
           ) do
        {:ok, pid} -> pid
        {:error, {:already_started, pid}} -> pid
      end

    pid =
      case Contents.Events.Game.start_link(room_id: @room_id) do
        {:ok, pid} -> pid
        {:error, {:already_started, pid}} -> pid
      end

    on_exit(fn ->
      if Process.alive?(pid), do: GenServer.stop(pid, :normal, 1000)
      if Process.alive?(stack), do: GenServer.stop(stack, :normal, 1000)
    end)

    {:ok, pid: pid, stack: stack}
  end

  test "リモートの終了と未知メッセージではルームが落ちず、許可された action はシーンを更新する", %{
    pid: pid,
    stack: stack
  } do
    previous = Application.get_env(:server, :current)
    Application.put_env(:server, :current, RemoteActionFixture)

    on_exit(fn ->
      Application.put_env(:server, :current, previous)
      clear_scene_flags(stack)
    end)

    %{frame_count: before_count} = :sys.get_state(pid)
    blob = :binary.copy(<<1>>, 10_000)

    log =
      capture_log(fn ->
        send(pid, {:ui_action, "__quit__"})
        send(pid, {:ui_action, 1})
        send(pid, {:blob, blob})
        send(pid, :quit_requested)
        send(pid, {:ui_action, "__retry__"})
        send(pid, {:ui_action, "__ping__"})
        _ = :sys.get_state(pid)
      end)

    assert Process.alive?(pid)
    assert log =~ "rejected ui_action=\"__quit__\""
    assert log =~ "ignoring unknown message"
    assert log =~ "ignored :quit_requested"
    refute log =~ "rejected ui_action=\"__retry__\""
    refute log =~ "rejected ui_action=\"__ping__\""
    assert byte_size(log) < 4_000

    scene = Contents.Scenes.Stack.get_scene_state(stack, :playing)
    assert scene.retry == true
    assert scene.pinged == true
    refute Map.has_key?(scene, :quit_ran)

    send(pid, :elixir_frame_tick)
    %{frame_count: after_count} = :sys.get_state(pid)
    assert after_count > before_count
  end

  defp clear_scene_flags(stack) do
    if is_pid(stack) and Process.alive?(stack) do
      Contents.Scenes.Stack.update_by_scene_type(stack, :playing, fn state ->
        state
        |> Map.delete(:retry)
        |> Map.delete(:pinged)
        |> Map.delete(:quit_ran)
      end)
    end
  end

  defp ensure_scene_registry! do
    case Process.whereis(Contents.Scenes.Registry) do
      nil ->
        case Registry.start_link(keys: :unique, name: Contents.Scenes.Registry) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
        end

      _pid ->
        :ok
    end
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
