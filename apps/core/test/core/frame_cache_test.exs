defmodule Core.FrameCacheTest do
  use ExUnit.Case, async: false

  test "init/0 は冪等で、複数回呼んでも例外にならない" do
    assert :ok = Core.FrameCache.init()
    assert :ok = Core.FrameCache.init()
    assert :ets.whereis(:frame_cache) != :undefined
  end
end
