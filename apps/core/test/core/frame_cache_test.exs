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
    hud = {100.0, 100.0, 0, 0.0}

    assert :ok = Core.FrameCache.put(:room_a, 1, 2, 1.0, hud)
    assert :ok = Core.FrameCache.put(:room_b, 3, 4, 2.0, hud)

    assert {:ok, %{enemy_count: 1, bullet_count: 2, physics_ms: 1.0}} =
             Core.FrameCache.get(:room_a)

    assert {:ok, %{enemy_count: 3, bullet_count: 4, physics_ms: 2.0}} =
             Core.FrameCache.get(:room_b)
  end

  test "delete/1 でルームのスナップショットを消せる" do
    hud = {100.0, 100.0, 0, 0.0}
    assert :ok = Core.FrameCache.put("room_c", 1, 0, 3.0, hud)
    assert {:ok, _} = Core.FrameCache.get("room_c")
    assert :ok = Core.FrameCache.delete("room_c")
    assert :empty = Core.FrameCache.get("room_c")
  end

  test "list/0 は全ルームを返す" do
    hud = {100.0, 100.0, 0, 0.0}
    assert :ok = Core.FrameCache.put(:room_a, 1, 0, 1.0, hud)
    assert :ok = Core.FrameCache.put(:room_b, 2, 0, 2.0, hud)

    rooms =
      Core.FrameCache.list()
      |> Enum.map(fn {room_id, _} -> room_id end)
      |> MapSet.new()

    assert MapSet.subset?(MapSet.new([:room_a, :room_b]), rooms)
  end
end
