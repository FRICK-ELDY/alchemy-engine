defmodule Core.StatsTest do
  use ExUnit.Case, async: false

  setup do
    pid = Process.whereis(Core.Stats)

    if is_pid(pid) do
      Core.Stats.new_session()
      _ = :sys.get_state(pid)
    end

    :ok
  end

  test "increment / set で汎用カウンタを記録する（kills 等の語彙なし）" do
    pid = Process.whereis(Core.Stats)
    assert is_pid(pid)

    Core.Stats.increment(:hits)
    Core.Stats.increment(:hits, 2)
    Core.Stats.set(:max_combo, 7)
    _ = :sys.get_state(pid)

    summary = Core.Stats.session_summary()
    assert summary.counters.hits == 3
    assert summary.values.max_combo == 7
    refute Map.has_key?(summary, :total_kills)
    refute Map.has_key?(summary, :kills_by_enemy)
  end

  test "EventBus の {:stat, key} / {:stat_set, key, value} を受け付ける" do
    pid = Process.whereis(Core.Stats)
    assert is_pid(pid)

    Core.EventBus.broadcast([{:stat, :pickups}, {:stat, :pickups, 2}, {:stat_set, :level, 4}])
    # cast → send の非同期を待つ
    _ = :sys.get_state(Process.whereis(Core.EventBus))
    _ = :sys.get_state(pid)

    summary = Core.Stats.session_summary()
    assert summary.counters.pickups == 3
    assert summary.values.level == 4
  end
end
