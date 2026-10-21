defmodule Core.FrameCacheTest do
  use ExUnit.Case, async: false

  setup do
    assert :ok = Core.FrameCache.init()

    on_exit(fn ->
      Core.FrameCache.delete(:room_a)
      Core.FrameCache.delete(:room_b)
      Core.FrameCache.delete("room_c")
    end)

    :ok
  end

  test "init/0 は冪等で、複数回呼んでも例外にならない" do
    assert :ok = Core.FrameCache.init()
    assert :ok = Core.FrameCache.init()
    assert :ets.whereis(:frame_cache) != :undefined
  end

  test "put/get は room_id ごとに独立する" do
    assert :ok =
             Core.FrameCache.put(:room_a, %{
               physics_ms: 1.0,
               counters: %{enemies: 1, bullets: 2}
             })

    assert :ok =
             Core.FrameCache.put(:room_b, %{
               physics_ms: 2.0,
               counters: %{enemies: 3, bullets: 4}
             })

    assert {:ok, %{physics_ms: 1.0, counters: %{enemies: 1, bullets: 2}}} =
             Core.FrameCache.get(:room_a)

    assert {:ok, %{physics_ms: 2.0, counters: %{enemies: 3, bullets: 4}}} =
             Core.FrameCache.get(:room_b)
  end

  test "delete/1 でルームのスナップショットを消せる" do
    assert :ok = Core.FrameCache.put("room_c", %{physics_ms: 3.0, counters: %{enemies: 1}})
    assert {:ok, _} = Core.FrameCache.get("room_c")
    assert :ok = Core.FrameCache.delete("room_c")
    assert :empty = Core.FrameCache.get("room_c")
  end

  test "list/0 は全ルームを返す" do
    assert :ok = Core.FrameCache.put(:room_a, %{physics_ms: 1.0})
    assert :ok = Core.FrameCache.put(:room_b, %{physics_ms: 2.0})

    rooms =
      Core.FrameCache.list()
      |> Enum.map(fn {room_id, _} -> room_id end)
      |> MapSet.new()

    assert MapSet.subset?(MapSet.new([:room_a, :room_b]), rooms)
  end

  test "put/2 は :physics_ms 必須" do
    assert_raise ArgumentError, ~r/physics_ms/, fn ->
      Core.FrameCache.put(:room_a, %{counters: %{enemies: 1}})
    end
  end
end
