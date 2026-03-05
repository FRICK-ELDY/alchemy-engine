defmodule Core.EventBusTest do
  use ExUnit.Case, async: false

  alias Core.EventBus

  setup do
    # EventBus は Server.Application で既に起動済みの場合がある
    pid =
      case EventBus.start_link() do
        {:ok, p} -> p
        {:error, {:already_started, p}} -> p
      end

    %{event_bus: pid}
  end

  describe "subscribe/1 and broadcast/1" do
    test "サブスクライバーにイベントが配信される", %{event_bus: _} do
      EventBus.subscribe()
      EventBus.broadcast([:event_a, :event_b])

      assert_receive {:game_events, [:event_a, :event_b]}, 100
    end

    test "複数サブスクライバーに同内容が配信される", %{event_bus: _} do
      parent = self()
      pid1 = spawn(fn -> wait_for_events(parent) end)
      pid2 = spawn(fn -> wait_for_events(parent) end)

      EventBus.subscribe(pid1)
      EventBus.subscribe(pid2)
      EventBus.broadcast([:foo])

      # 両方のプロセスがメッセージを受信する
      assert_receive {:received, ^pid1, [:foo]}, 100
      assert_receive {:received, ^pid2, [:foo]}, 100
    end

    test "空リストの broadcast も配信される", %{event_bus: _} do
      EventBus.subscribe()
      EventBus.broadcast([])
      assert_receive {:game_events, []}, 100
    end

    test "サブスクライバーが終了しても EventBus は正常に動作し続ける", %{event_bus: _} do
      parent = self()

      subscriber =
        spawn(fn ->
          EventBus.subscribe()
          send(parent, :subscribed)

          receive do
            :exit -> :ok
          end
        end)

      assert_receive :subscribed, 500
      send(subscriber, :exit)

      # DOWN が EventBus に届くまで数ミリ秒かかる可能性があるため、subscribe+broadcast で生存確認
      EventBus.subscribe()
      EventBus.broadcast([:after_down])
      assert_receive {:game_events, [:after_down]}, 500
    end
  end

  defp wait_for_events(parent) do
    receive do
      {:game_events, events} -> send(parent, {:received, self(), events})
    after
      500 -> send(parent, {:timeout, self()})
    end
  end
end
