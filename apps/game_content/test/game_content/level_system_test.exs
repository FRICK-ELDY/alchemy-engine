defmodule GameContent.VampireSurvivor.LevelSystemTest do
  use ExUnit.Case, async: true

  alias GameContent.VampireSurvivor.LevelSystem

  @max_weapon_level 8
  @max_weapon_slots 6
  @all_weapons [:magic_wand, :garlic, :axe, :cross, :whip, :fireball, :lightning]

  describe "generate_weapon_choices/1" do
    test "空の weapon_levels で最大 3 択を返す" do
      choices = LevelSystem.generate_weapon_choices(%{})
      assert length(choices) <= 3
      assert length(choices) > 0
    end

    test "全武器が最大レベルのとき空リストを返す" do
      all_maxed = Map.new(@all_weapons, fn w -> {w, @max_weapon_level} end)
      assert LevelSystem.generate_weapon_choices(all_maxed) == []
    end

    test "スロットが満杯（6 枠）のとき未所持武器を選択肢に含めない" do
      weapon_levels = Map.new(Enum.take(@all_weapons, @max_weapon_slots), fn w -> {w, 1} end)
      choices = LevelSystem.generate_weapon_choices(weapon_levels)

      Enum.each(choices, fn w ->
        assert Map.has_key?(weapon_levels, w),
               "スロット満杯時は未所持武器 #{w} を選択肢に含めてはいけない"
      end)
    end

    test "未所持武器（lv=0）が所持済み武器より優先される" do
      weapon_levels = %{magic_wand: 3, garlic: 2}
      choices = LevelSystem.generate_weapon_choices(weapon_levels)

      unowned = Enum.filter(choices, fn w -> not Map.has_key?(weapon_levels, w) end)
      owned   = Enum.filter(choices, fn w -> Map.has_key?(weapon_levels, w) end)

      assert length(unowned) >= length(owned),
             "未所持武器が所持済み武器より先に並ぶべき"
    end

    test "返り値は全て @all_weapons に含まれる atom" do
      choices = LevelSystem.generate_weapon_choices(%{magic_wand: 1})
      Enum.each(choices, fn w ->
        assert w in @all_weapons, "#{w} は有効な武器名であるべき"
      end)
    end

    test "最大レベルの武器は選択肢に含まれない" do
      weapon_levels = %{magic_wand: @max_weapon_level}
      choices = LevelSystem.generate_weapon_choices(weapon_levels)
      refute :magic_wand in choices
    end

    test "重複する武器を選択肢に含めない" do
      choices = LevelSystem.generate_weapon_choices(%{})
      assert length(choices) == length(Enum.uniq(choices))
    end
  end

  describe "max_weapon_level/0" do
    test "8 を返す" do
      assert LevelSystem.max_weapon_level() == 8
    end
  end
end
