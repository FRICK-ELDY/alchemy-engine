defmodule Content.VampireSurvivor.WeaponFormulas do
  @moduledoc """
  武器の数式計算ロジック。Rust の weapon.rs と同値の SSoT。

  アーキテクチャ原則「Elixir = SSoT」に沿い、contents 側でゲームロジックを完結させる。
  レベルアップカード表示・将来的な damage 注入等で使用する。

  ## 数式（Rust weapon.rs と一致）
  - effective_damage: base + (level - 1) * max(base/4, 1)
  - effective_cooldown: base * (1 - (level-1)*0.07), min base*0.5
  - whip_range: range + (level - 1) * 20
  - aura_radius: range + (level - 1) * 15
  - chain_count_for_level: chain_count + level / 2
  - bullet_count: bullet_table[level] or 1（level は 1-based インデックス）

  ## fire_pattern
  SpawnComponent の weapon_params は fire_pattern: "aimed" 等の文字列を渡す。
  文字列比較で分岐するため、フォーマット変更時は本モジュールの修正が必要。
  """

  @max_weapon_level 8

  @doc """
  武器の実効ダメージを計算する。

  レベルは MAX_WEAPON_LEVEL (8) でキャップする。Rust の MAX_WEAPON_LEVEL と一致。

  ## 例
      effective_damage(10, 1)  # => 10
      effective_damage(10, 2)  # => 12  (base + 1 * max(2, 1))
  """
  @spec effective_damage(non_neg_integer(), pos_integer()) :: non_neg_integer()
  def effective_damage(base_damage, level) when level >= 1 do
    lv = min(level, @max_weapon_level)
    inc = max(div(base_damage, 4), 1)
    base_damage + (lv - 1) * inc
  end

  @doc """
  武器の実効クールダウン（秒）を計算する。
  """
  @spec effective_cooldown(float(), pos_integer()) :: float()
  def effective_cooldown(base_cooldown, level) when level >= 1 do
    lv = min(level, @max_weapon_level)
    factor = 1.0 - (lv - 1) * 0.07
    min_cooldown = base_cooldown * 0.5
    max(base_cooldown * factor, min_cooldown)
  end

  @doc """
  Whip の実効範囲（px）を計算する。

  Rust と同様 level はキャップしない。他関数との一貫性で cap が必要な場合は呼び出し側で min(level, 8) を渡す。
  """
  @spec whip_range(float(), pos_integer()) :: float()
  def whip_range(base_range, level) when level >= 1 do
    base_range + (level - 1) * 20.0
  end

  @doc """
  Aura の実効半径（px）を計算する。

  Rust と同様 level はキャップしない。
  """
  @spec aura_radius(float(), pos_integer()) :: float()
  def aura_radius(base_range, level) when level >= 1 do
    base_range + (level - 1) * 15.0
  end

  @doc """
  Chain 武器の実効連鎖数を計算する。
  """
  @spec chain_count_for_level(non_neg_integer(), pos_integer()) :: non_neg_integer()
  def chain_count_for_level(base_chain_count, level) when level >= 1 do
    base_chain_count + div(level, 2)
  end

  @doc """
  bullet_table から弾数を取得する。nil の場合は 1。

  ## Rust との整合性
  entity_params.rs と同様、index = level（1-based）を使用する。
  Enum.at/3 は 0-based なので level をそのままインデックスに渡す。
  bullet_table は [0, 1, 1, 2, ...] の形式で、index 0 は未使用、index 1 = level 1 の弾数。
  """
  @spec bullet_count(nil | [non_neg_integer()], pos_integer()) :: non_neg_integer()
  def bullet_count(nil, _level), do: 1

  def bullet_count(bullet_table, level) when is_list(bullet_table) do
    idx = min(level, @max_weapon_level)
    Enum.at(bullet_table, idx, 1)
  end

  @doc """
  レベルアップカード用のアップグレード説明文リストを返す。

  weapon_choices と weapon_levels から各武器の current -> next 説明を生成する。
  """
  @spec weapon_upgrade_descs([atom() | String.t()], map(), [map()]) :: [[String.t()]]
  def weapon_upgrade_descs(weapon_choices, weapon_levels, weapon_params)
      when is_list(weapon_choices) and is_map(weapon_levels) and is_list(weapon_params) do
    registry = Content.VampireSurvivor.SpawnComponent.entity_registry().weapons

    Enum.map(weapon_choices, fn choice ->
      case resolve_weapon_name(choice) do
        {:ok, name} ->
          kind_id = Map.get(registry, name)
          current_lv = Map.get(weapon_levels, name, 0) |> max(0)
          wp = kind_id != nil && Enum.at(weapon_params, kind_id)

          if wp do
            weapon_upgrade_desc(kind_id, current_lv, wp)
          else
            ["Upgrade weapon"]
          end

        :error ->
          ["Upgrade weapon"]
      end
    end)
  end

  defp resolve_weapon_name(choice) when is_atom(choice) do
    if is_registered_weapon?(choice), do: {:ok, choice}, else: :error
  end

  defp resolve_weapon_name(choice) when is_binary(choice) do
    try do
      atom = String.to_existing_atom(choice)
      if is_registered_weapon?(atom), do: {:ok, atom}, else: :error
    rescue
      ArgumentError -> :error
    end
  end

  defp resolve_weapon_name(_), do: :error

  defp is_registered_weapon?(atom) do
    registry = Content.VampireSurvivor.SpawnComponent.entity_registry().weapons
    Map.has_key?(registry, atom)
  end

  defp weapon_upgrade_desc(_kind_id, current_lv, wp) do
    # current_lv=0 は新規取得。表示は Lv.1 -> Lv.2 の比較になる
    lv_for_current = max(1, current_lv)
    next_lv = min(current_lv + 1, @max_weapon_level)

    dmg = fn lv -> effective_damage(wp.damage, max(1, lv)) end
    cd = fn lv -> effective_cooldown(wp.cooldown, max(1, lv)) end

    base =
      [
        "DMG: #{dmg.(lv_for_current)} -> #{dmg.(next_lv)}",
        "CD:  #{Float.round(cd.(lv_for_current), 1)}s -> #{Float.round(cd.(next_lv), 1)}s"
      ]

    fire_pattern = wp.fire_pattern |> to_string() |> String.downcase()

    case fire_pattern do
      "aimed" ->
        bullets = fn lv -> bullet_count(wp.bullet_table, max(1, lv)) end
        bullets_now = bullets.(lv_for_current)
        bullets_next = bullets.(next_lv)

        extra =
          if bullets_next > bullets_now,
            do: ["Shots: #{bullets_now} -> #{bullets_next} (+)"],
            else: ["Shots: #{bullets_now}"]

        base ++ extra

      "fixed_up" ->
        base ++ ["Throws upward"]

      "radial" ->
        dirs_now = if current_lv == 0 or current_lv <= 3, do: 4, else: 8
        dirs_next = if next_lv <= 3, do: 4, else: 8

        extra =
          if dirs_next > dirs_now,
            do: ["Dirs: #{dirs_now} -> #{dirs_next} (+)"],
            else: ["#{dirs_now}-way fire"]

        base ++ extra

      "whip" ->
        range_now = whip_range(wp.range, lv_for_current) |> trunc()
        range_next = whip_range(wp.range, next_lv) |> trunc()
        base ++ ["Range: #{range_now}px -> #{range_next}px", "Fan sweep (108°)"]

      "piercing" ->
        base ++ ["Piercing shot"]

      "chain" ->
        chain_now = chain_count_for_level(wp.chain_count, lv_for_current)
        chain_next = chain_count_for_level(wp.chain_count, next_lv)
        base ++ ["Chain: #{chain_now} -> #{chain_next} targets"]

      "aura" ->
        r_now = aura_radius(wp.range, lv_for_current) |> trunc()
        r_next = aura_radius(wp.range, next_lv) |> trunc()
        base ++ ["Radius: #{r_now}px -> #{r_next}px"]

      _ ->
        base
    end
  end
end
