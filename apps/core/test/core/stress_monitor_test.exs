defmodule Core.StressMonitorTest do
  use ExUnit.Case, async: false

  setup do
    Core.FrameCache.init()
    Core.FrameCache.delete(:main)
    Core.FrameCache.delete("other")

    if pid = Process.whereis(Core.StressMonitor) do
      # 空き FrameCache で sample すると rooms が prune され、テスト間の状態汚染を防ぐ
      send(pid, :sample)
      _ = :sys.get_state(pid)
    end

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

  test "physics_ms が整数でも Float.round でクラッシュしない" do
    pid = Process.whereis(Core.StressMonitor)
    assert is_pid(pid)

    hud = {100.0, 100.0, 0, 0.0}
    assert :ok = Core.FrameCache.put(:main, 1, 0, 3, hud)

    send(pid, :sample)
    _ = :sys.get_state(pid)
    stats = Core.StressMonitor.get_stats()

    assert stats.rooms[:main].peak_physics_ms == 3.0
    assert is_float(stats.rooms[:main].peak_physics_ms)
  end

  test "physics_ms が nil でもクラッシュせず 0.0 として扱う" do
    pid = Process.whereis(Core.StressMonitor)
    assert is_pid(pid)

    # put/7 経由では nil を入れにくいので ETS に直接不完全エントリを書く
    true =
      :ets.insert(:frame_cache, {
        :main,
        %{
          enemy_count: 0,
          bullet_count: 0,
          physics_ms: nil,
          hud_data: {100.0, 100.0, 0, 0.0}
        }
      })

    send(pid, :sample)
    _ = :sys.get_state(pid)
    stats = Core.StressMonitor.get_stats()

    assert stats.rooms[:main].peak_physics_ms == 0.0
  end
end

