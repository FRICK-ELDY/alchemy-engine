defmodule Core.StressMonitorTest do
  use ExUnit.Case, async: false

  setup do
    Core.FrameCache.init()
    Core.FrameCache.delete(:main)
    Core.FrameCache.delete("other")

    on_exit(fn ->
      Core.FrameCache.delete(:main)
      Core.FrameCache.delete("other")
    end)

    :ok
  end

  test "ルーム別の peak / samples を独立に保持し :main をトップレベルへミラーする" do
    pid = Process.whereis(Core.StressMonitor)
    assert is_pid(pid)

    hud_main = {100.0, 100.0, 10, 1.0}
    hud_other = {80.0, 100.0, 20, 2.0}

    assert :ok = Core.FrameCache.put(:main, 5, 1, 1.0, hud_main)
    assert :ok = Core.FrameCache.put("other", 100, 2, 2.0, hud_other)

    send(pid, :sample)
    _ = :sys.get_state(pid)
    stats = Core.StressMonitor.get_stats()

    assert stats.rooms[:main].last_enemy_count == 5
    assert stats.rooms[:main].peak_enemies == 5
    assert stats.rooms[:main].samples == 1

    assert stats.rooms["other"].last_enemy_count == 100
    assert stats.rooms["other"].peak_enemies == 100
    assert stats.rooms["other"].samples == 1

    # :main ミラー（後方互換）
    assert stats.last_enemy_count == 5
    assert stats.peak_enemies == 5
    assert stats.samples == 1

    # other の peak が :main のログ用 peak を汚染していない
    refute stats.peak_enemies == 100
  end
end
