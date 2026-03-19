defmodule Content.VampireSurvivor.WeaponFormulasTest do
  use ExUnit.Case, async: true

  alias Content.VampireSurvivor.EntityParams
  alias Content.VampireSurvivor.Playing.WeaponFormulas

  describe "effective_damage/2" do
    test "Rust weapon.rs と同値: base=10, level=1 => 10" do
      assert WeaponFormulas.effective_damage(10, 1) == 10
    end

    test "Rust weapon.rs と同値: base=10, level=2 => 12" do
      assert WeaponFormulas.effective_damage(10, 2) == 12
    end

    test "base=30, level=3 => 30 + 2*7 = 44" do
      assert WeaponFormulas.effective_damage(30, 3) == 44
    end
  end

  describe "effective_cooldown/2" do
    test "level=1 では base そのまま" do
      assert WeaponFormulas.effective_cooldown(1.0, 1) == 1.0
    end

    test "level=2 で 0.93 倍（1 - 0.07）" do
      assert abs(WeaponFormulas.effective_cooldown(1.0, 2) - 0.93) < 1.0e-6
    end
  end

  describe "weapon_upgrade_descs/3" do
    test "magic_wand 新規取得で Aimed パターン説明を返す" do
      weapon_params = EntityParams.weapon_params()
      descs = WeaponFormulas.weapon_upgrade_descs([:magic_wand], %{}, weapon_params)

      assert length(descs) == 1
      [lines] = descs
      joined = Enum.join(List.wrap(lines), " ")
      assert String.contains?(joined, "DMG:")
      assert String.contains?(joined, "CD:")
      assert Enum.any?(List.wrap(lines), &String.contains?(&1, "Shots"))
    end

    test "whip で Range 説明を返す" do
      weapon_params = EntityParams.weapon_params()
      descs = WeaponFormulas.weapon_upgrade_descs([:whip], %{whip: 1}, weapon_params)

      assert length(descs) == 1
      [lines] = descs
      assert Enum.any?(List.wrap(lines), &String.contains?(&1, "Range"))
    end

    test "未登録 weapon 名では Upgrade weapon にフォールバック" do
      weapon_params = EntityParams.weapon_params()
      # 存在しない atom は registry にないので :error
      descs = WeaponFormulas.weapon_upgrade_descs([:__unknown_weapon__], %{}, weapon_params)

      assert descs == [["Upgrade weapon"]]
    end

    test "不正な文字列では to_existing_atom 失敗時に Upgrade weapon にフォールバック" do
      weapon_params = EntityParams.weapon_params()
      # 未作成の atom 文字列は ArgumentError を起こす
      descs =
        WeaponFormulas.weapon_upgrade_descs(["nonexistent_weapon_xyz_123"], %{}, weapon_params)

      assert descs == [["Upgrade weapon"]]
    end
  end
end
