defmodule GameContent.VampireSurvivor.LevelSystem do
  @moduledoc """
  レベルアップ・武器選択生成の純粋関数モジュール（ヴァンサバ固有）。
  """

  @all_weapons [:magic_wand, :garlic, :axe, :cross, :whip, :fireball, :lightning]
  @max_weapon_level 8
  @max_weapon_slots 6

  def generate_weapon_choices(weapon_levels) when is_map(weapon_levels) do
    slots_full? = map_size(weapon_levels) >= @max_weapon_slots

    @all_weapons
    |> Enum.reject(fn w ->
      lv = Map.get(weapon_levels, w, 0)
      lv >= @max_weapon_level or (slots_full? and lv == 0)
    end)
    |> Enum.sort_by(fn w ->
      lv = Map.get(weapon_levels, w, 0)
      if lv == 0, do: -1, else: lv
    end)
    |> Enum.take(3)
  end

  def weapon_label(weapon, level) when is_integer(level) and level > 1 do
    "#{weapon_label(weapon)} Lv.#{level}"
  end
  def weapon_label(weapon, _level), do: weapon_label(weapon)

  def weapon_label(:magic_wand), do: "Magic Wand (auto-aim)"
  def weapon_label(:garlic),     do: "Garlic (aura damage)"
  def weapon_label(:axe),        do: "Axe (upward throw)"
  def weapon_label(:cross),      do: "Cross (4-way fire)"
  def weapon_label(:whip),       do: "Whip (fan sweep)"
  def weapon_label(:fireball),   do: "Fireball (piercing)"
  def weapon_label(:lightning),  do: "Lightning (chain)"
  def weapon_label(other),       do: to_string(other)
end
