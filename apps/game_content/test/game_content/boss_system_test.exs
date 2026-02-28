defmodule GameContent.VampireSurvivor.BossSystemTest do
  use ExUnit.Case, async: true

  alias GameContent.VampireSurvivor.BossSystem

  describe "check_spawn/2" do
    test "180 秒経過で slime_king をスポーンする" do
      assert {:spawn, :slime_king, _name} = BossSystem.check_spawn(180, [])
    end

    test "360 秒経過で bat_lord をスポーンする" do
      assert {:spawn, :bat_lord, _name} = BossSystem.check_spawn(360, [:slime_king])
    end

    test "540 秒経過で stone_golem をスポーンする" do
      assert {:spawn, :stone_golem, _name} =
               BossSystem.check_spawn(540, [:slime_king, :bat_lord])
    end

    test "既にスポーン済みのボスは再スポーンしない" do
      assert :no_boss = BossSystem.check_spawn(180, [:slime_king])
    end

    test "全ボスがスポーン済みのとき :no_boss を返す" do
      all_spawned = [:slime_king, :bat_lord, :stone_golem]
      assert :no_boss = BossSystem.check_spawn(9999, all_spawned)
    end

    test "180 秒未満では :no_boss を返す" do
      assert :no_boss = BossSystem.check_spawn(179, [])
    end

    test "スポーン時に名前文字列を返す" do
      {:spawn, :slime_king, name} = BossSystem.check_spawn(180, [])
      assert is_binary(name)
      assert String.length(name) > 0
    end
  end

  describe "alert_duration_ms/0" do
    test "3000 ms を返す" do
      assert BossSystem.alert_duration_ms() == 3_000
    end
  end

  describe "boss_label/1" do
    test "既知のボス種別に対して文字列を返す" do
      assert is_binary(BossSystem.boss_label(:slime_king))
      assert is_binary(BossSystem.boss_label(:bat_lord))
      assert is_binary(BossSystem.boss_label(:stone_golem))
    end

    test "未知の種別は to_string で変換する" do
      assert BossSystem.boss_label(:unknown_boss) == "unknown_boss"
    end
  end
end
