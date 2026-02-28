defmodule GameContent.VampireSurvivor.SpawnComponentTest do
  use ExUnit.Case, async: true

  alias GameContent.VampireSurvivor.SpawnComponent

  describe "entity_registry/0" do
    setup do
      %{registry: SpawnComponent.entity_registry()}
    end

    test "enemies/weapons/bosses キーを持つ", %{registry: r} do
      assert Map.has_key?(r, :enemies)
      assert Map.has_key?(r, :weapons)
      assert Map.has_key?(r, :bosses)
    end

    test "enemies の値は atom → non_neg_integer のマップ", %{registry: r} do
      Enum.each(r.enemies, fn {k, v} ->
        assert is_atom(k), "キーは atom であるべき: #{inspect(k)}"
        assert is_integer(v) and v >= 0, "値は非負整数であるべき: #{v}"
      end)
    end

    test "weapons の値は atom → non_neg_integer のマップ", %{registry: r} do
      Enum.each(r.weapons, fn {k, v} ->
        assert is_atom(k)
        assert is_integer(v) and v >= 0
      end)
    end

    test "bosses の値は atom → non_neg_integer のマップ", %{registry: r} do
      Enum.each(r.bosses, fn {k, v} ->
        assert is_atom(k)
        assert is_integer(v) and v >= 0
      end)
    end

    test "enemies の ID に重複がない", %{registry: r} do
      ids = Map.values(r.enemies)
      assert ids == Enum.uniq(ids), "enemy ID に重複がある: #{inspect(ids)}"
    end

    test "weapons の ID に重複がない", %{registry: r} do
      ids = Map.values(r.weapons)
      assert ids == Enum.uniq(ids), "weapon ID に重複がある: #{inspect(ids)}"
    end

    test "bosses の ID に重複がない", %{registry: r} do
      ids = Map.values(r.bosses)
      assert ids == Enum.uniq(ids), "boss ID に重複がある: #{inspect(ids)}"
    end

    test "期待する敵種別が全て登録されている", %{registry: r} do
      expected_enemies = [:slime, :bat, :golem, :skeleton, :ghost]
      Enum.each(expected_enemies, fn e ->
        assert Map.has_key?(r.enemies, e), "#{e} が enemies に登録されていない"
      end)
    end

    test "期待する武器種別が全て登録されている", %{registry: r} do
      expected_weapons = [:magic_wand, :axe, :cross, :whip, :fireball, :lightning, :garlic]
      Enum.each(expected_weapons, fn w ->
        assert Map.has_key?(r.weapons, w), "#{w} が weapons に登録されていない"
      end)
    end

    test "期待するボス種別が全て登録されている", %{registry: r} do
      expected_bosses = [:slime_king, :bat_lord, :stone_golem]
      Enum.each(expected_bosses, fn b ->
        assert Map.has_key?(r.bosses, b), "#{b} が bosses に登録されていない"
      end)
    end
  end
end
