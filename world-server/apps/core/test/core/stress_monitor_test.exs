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

    assert :ok =
             Core.FrameCache.put(:main, %{
               physics_ms: 1.0,
               label: "wave1",
               counters: %{enemies: 5, bullets: 1},
               meta: %{score: 10, hp_pct: 100.0}
             })

    assert :ok =
             Core.FrameCache.put("other", %{
               physics_ms: 2.0,
               label: "wave2",
               counters: %{enemies: 100, bullets: 2},
               meta: %{score: 20, hp_pct: 80.0}
             })

    send(pid, :sample)
    _ = :sys.get_state(pid)
    stats = Core.StressMonitor.get_stats()

    assert stats.rooms[:main].last_counters.enemies == 5
    assert stats.rooms[:main].peak_counters.enemies == 5
    assert stats.rooms[:main].samples == 1

    assert stats.rooms["other"].last_counters.enemies == 100
    assert stats.rooms["other"].peak_counters.enemies == 100
    assert stats.rooms["other"].samples == 1

    # :main ミラー（後方互換）
    assert stats.last_counters.enemies == 5
    assert stats.peak_counters.enemies == 5
    assert stats.samples == 1

    # other の peak が :main のログ用 peak を汚染していない
    refute stats.peak_counters.enemies == 100
  end

  test "physics_ms が整数でも Float.round でクラッシュしない" do
    pid = Process.whereis(Core.StressMonitor)
    assert is_pid(pid)

    assert :ok = Core.FrameCache.put(:main, %{physics_ms: 3, counters: %{entities: 1}})

    send(pid, :sample)
    _ = :sys.get_state(pid)
    stats = Core.StressMonitor.get_stats()

    assert stats.rooms[:main].peak_physics_ms == 3.0
    assert is_float(stats.rooms[:main].peak_physics_ms)
  end

  test "physics_ms が nil でもクラッシュせず 0.0 として扱う" do
    pid = Process.whereis(Core.StressMonitor)
    assert is_pid(pid)

    # put/2 経由では physics_ms 必須のため、ETS に直接不完全エントリを書く
    true =
      :ets.insert(:frame_cache, {
        :main,
        %{
          physics_ms: nil,
          counters: %{},
          meta: %{}
        }
      })

    send(pid, :sample)
    _ = :sys.get_state(pid)
    stats = Core.StressMonitor.get_stats()

    assert stats.rooms[:main].peak_physics_ms == 0.0
  end

  test "コンテンツモジュールを呼ばずに label メタデータだけをログ用に使う" do
    pid = Process.whereis(Core.StressMonitor)
    assert is_pid(pid)

    # Core.Config.current/0 を呼ばないこと（wave_label 等の contents 語彙に触れない）
    assert :ok =
             Core.FrameCache.put(:main, %{
               physics_ms: 1.0,
               label: "injected-label",
               counters: %{entities: 3}
             })

    send(pid, :sample)
    _ = :sys.get_state(pid)
    stats = Core.StressMonitor.get_stats()

    assert stats.rooms[:main].last_counters.entities == 3
    assert stats.rooms[:main].peak_counters.entities == 3
  end

  test "meta にネスト map があってもログでクラッシュしない" do
    pid = Process.whereis(Core.StressMonitor)
    assert is_pid(pid)

    assert :ok =
             Core.FrameCache.put(:main, %{
               physics_ms: 1.0,
               meta: %{nested: %{a: 1}, list: [1, 2, 3]}
             })

    send(pid, :sample)
    state = :sys.get_state(pid)
    assert state.rooms[:main].samples == 1
  end
end
