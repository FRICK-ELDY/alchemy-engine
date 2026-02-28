defmodule GameContent.VampireSurvivor.SpawnSystemTest do
  use ExUnit.Case, async: true

  alias GameContent.VampireSurvivor.SpawnSystem

  describe "current_wave/1" do
    test "0 秒のとき Wave 1 のパラメータを返す" do
      {interval_ms, count} = SpawnSystem.current_wave(0)
      assert is_integer(interval_ms) or is_float(interval_ms)
      assert count > 0
    end

    test "各ウェーブ開始時刻で正しいフェーズに切り替わる" do
      {i0, _}  = SpawnSystem.current_wave(0)
      {i10, _} = SpawnSystem.current_wave(10)
      {i20, _} = SpawnSystem.current_wave(20)
      {i40, _} = SpawnSystem.current_wave(40)
      {i60, _} = SpawnSystem.current_wave(60)

      assert i0  >= i10
      assert i10 >= i20
      assert i20 >= i40
      assert i40 >= i60
    end
  end

  describe "wave_label/1" do
    test "0 秒のとき Wave 1 ラベルを返す" do
      label = SpawnSystem.wave_label(0)
      assert String.contains?(label, "Wave 1")
    end

    test "10 秒のとき Wave 2 ラベルを返す" do
      label = SpawnSystem.wave_label(10)
      assert String.contains?(label, "Wave 2")
    end

    test "20 秒のとき Wave 3 ラベルを返す" do
      label = SpawnSystem.wave_label(20)
      assert String.contains?(label, "Wave 3")
    end

    test "40 秒のとき Wave 4 ラベルを返す" do
      label = SpawnSystem.wave_label(40)
      assert String.contains?(label, "Wave 4")
    end

    test "60 秒のとき Wave 5（ELITE）ラベルを返す" do
      label = SpawnSystem.wave_label(60)
      assert String.contains?(label, "Wave 5")
    end

    test "全ウェーブで文字列を返す" do
      for sec <- [0, 10, 20, 40, 60, 120] do
        assert is_binary(SpawnSystem.wave_label(sec))
      end
    end
  end

  describe "enemy_kind_for_wave/1" do
    test "0 秒のとき slime か bat を返す" do
      kind = SpawnSystem.enemy_kind_for_wave(0)
      assert kind in [:slime, :bat]
    end

    test "10 秒のとき slime/bat/skeleton のいずれかを返す" do
      kind = SpawnSystem.enemy_kind_for_wave(10)
      assert kind in [:slime, :bat, :skeleton]
    end

    test "20 秒のとき slime/bat/skeleton/ghost のいずれかを返す" do
      kind = SpawnSystem.enemy_kind_for_wave(20)
      assert kind in [:slime, :bat, :skeleton, :ghost]
    end

    test "40 秒以降は全種別が出現しうる" do
      kind = SpawnSystem.enemy_kind_for_wave(40)
      assert kind in [:slime, :bat, :skeleton, :ghost, :golem]
    end
  end
end
