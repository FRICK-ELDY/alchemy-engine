# credo:disable-for-this-file Credo.Check.Design.AliasUsage
defmodule Content.VampireSurvivor.EntityParams do
  @moduledoc """
  VampireSurvivor のワールド・エンティティパラメータ定義。
  Spawner および Content から参照する。
  """
  @map_width 4096.0
  @map_height 4096.0

  def world_size, do: {@map_width, @map_height}

  def world_params_for_nif do
    %{
      player_speed: 200.0,
      bullet_speed: 400.0,
      bullet_lifetime: 3.0,
      collect_radius: 60.0,
      magnet_collect_radius: 9999.0,
      magnet_duration: 10.0,
      magnet_speed: 300.0,
      spawn_min_dist: 800.0,
      spawn_max_dist: 1200.0,
      particle_gravity: 200.0,
      bullet_query_radius: 38.0,
      map_margin: 100.0,
      chain_boss_range: 600.0
    }
  end

  def entity_params_for_nif do
    {
      enemy_params(),
      weapon_params(),
      Content.EntityParams.boss_params()
    }
  end

  # Content.EntityParams の敵種別ID順序と一致させること（enemy_exp_reward 等で使用）
  # slime(0), bat(1), skeleton(2), ghost(3), golem(4)
  def entity_registry do
    %{
      enemies: %{slime: 0, bat: 1, skeleton: 2, ghost: 3, golem: 4},
      weapons: %{
        magic_wand: 0,
        axe: 1,
        cross: 2,
        whip: 3,
        fireball: 4,
        lightning: 5,
        garlic: 6
      },
      bosses: %{slime_king: 0, bat_lord: 1, stone_golem: 2}
    }
  end

  def assets_path, do: "vampire_survivor"
  def initial_weapons, do: [:magic_wand]
  def score_popup_lifetime, do: 0.8

  def weapon_params, do: weapon_params_impl()

  def enemy_damage_per_sec_list do
    enemy_params()
    |> Enum.with_index()
    |> Enum.map(fn {p, i} -> {i, p[:damage_per_sec] || 0} end)
  end

  # 順序は Content.EntityParams の kind_id と一致させる（index = kind_id）
  # 0: slime, 1: bat, 2: skeleton, 3: ghost, 4: golem
  defp enemy_params do
    [
      # 0: Slime
      %{
        max_hp: 30.0,
        speed: 80.0,
        radius: 20.0,
        damage_per_sec: 20.0,
        render_kind: 1,
        particle_color: [1.0, 0.5, 0.1, 1.0],
        passes_obstacles: false
      },
      # 1: Bat
      %{
        max_hp: 15.0,
        speed: 160.0,
        radius: 12.0,
        damage_per_sec: 10.0,
        render_kind: 2,
        particle_color: [0.7, 0.2, 0.9, 1.0],
        passes_obstacles: false
      },
      # 2: Skeleton
      %{
        max_hp: 60.0,
        speed: 60.0,
        radius: 22.0,
        damage_per_sec: 15.0,
        render_kind: 5,
        particle_color: [0.9, 0.85, 0.7, 1.0],
        passes_obstacles: false
      },
      # 3: Ghost（壁すり抜け）
      %{
        max_hp: 40.0,
        speed: 100.0,
        radius: 16.0,
        damage_per_sec: 12.0,
        render_kind: 4,
        particle_color: [0.5, 0.5, 1.0, 0.8],
        passes_obstacles: true
      },
      # 4: Golem
      %{
        max_hp: 150.0,
        speed: 40.0,
        radius: 32.0,
        damage_per_sec: 40.0,
        render_kind: 3,
        particle_color: [0.6, 0.6, 0.6, 1.0],
        passes_obstacles: false
      }
    ]
  end

  defp weapon_params_impl do
    [
      %{
        cooldown: 1.0,
        damage: 10,
        as_u8: 0,
        bullet_table: [0, 1, 1, 2, 2, 3, 3, 4, 4],
        fire_pattern: "aimed",
        range: 0.0,
        chain_count: 0,
        aimed_spread_rad: :math.pi() * 0.08,
        whip_half_angle_rad: 0.0,
        effect_lifetime_sec: 0.0,
        hit_particle_color: [1.0, 0.9, 0.3, 1.0]
      },
      %{
        cooldown: 1.5,
        damage: 25,
        as_u8: 1,
        bullet_table: nil,
        fire_pattern: "fixed_up",
        range: 0.0,
        chain_count: 0,
        aimed_spread_rad: 0.0,
        whip_half_angle_rad: 0.0,
        effect_lifetime_sec: 0.0,
        hit_particle_color: [1.0, 0.8, 0.2, 1.0]
      },
      %{
        cooldown: 2.0,
        damage: 15,
        as_u8: 2,
        bullet_table: [0, 4, 4, 4, 8, 8, 8, 8, 8],
        fire_pattern: "radial",
        range: 0.0,
        chain_count: 0,
        aimed_spread_rad: 0.0,
        whip_half_angle_rad: 0.0,
        effect_lifetime_sec: 0.0,
        hit_particle_color: [1.0, 0.9, 0.3, 1.0],
        radial_dir_count_per_level: [4, 4, 4, 8, 8, 8, 8, 8]
      },
      %{
        cooldown: 1.0,
        damage: 30,
        as_u8: 3,
        bullet_table: nil,
        fire_pattern: "whip",
        range: 120.0,
        chain_count: 0,
        whip_range_per_level:
          1..8
          |> Enum.map(&Content.VampireSurvivor.Playing.WeaponFormulas.whip_range(120.0, &1)),
        aimed_spread_rad: 0.0,
        whip_half_angle_rad: :math.pi() * 0.3,
        effect_lifetime_sec: 0.12,
        hit_particle_color: [1.0, 0.6, 0.1, 1.0]
      },
      %{
        cooldown: 1.0,
        damage: 20,
        as_u8: 4,
        bullet_table: nil,
        fire_pattern: "piercing",
        range: 0.0,
        chain_count: 0,
        aimed_spread_rad: 0.0,
        whip_half_angle_rad: 0.0,
        effect_lifetime_sec: 0.0,
        hit_particle_color: [1.0, 0.4, 0.0, 1.0]
      },
      %{
        cooldown: 1.0,
        damage: 15,
        as_u8: 5,
        bullet_table: nil,
        fire_pattern: "chain",
        range: 0.0,
        chain_count: 2,
        chain_count_per_level:
          1..8
          |> Enum.map(
            &Content.VampireSurvivor.Playing.WeaponFormulas.chain_count_for_level(2, &1)
          ),
        aimed_spread_rad: 0.0,
        whip_half_angle_rad: 0.0,
        effect_lifetime_sec: 0.10,
        hit_particle_color: [0.3, 0.8, 1.0, 1.0]
      },
      %{
        cooldown: 0.2,
        damage: 1,
        as_u8: 6,
        bullet_table: nil,
        fire_pattern: "aura",
        range: 80.0,
        chain_count: 0,
        aura_radius_per_level:
          1..8
          |> Enum.map(&Content.VampireSurvivor.Playing.WeaponFormulas.aura_radius(80.0, &1)),
        aimed_spread_rad: 0.0,
        whip_half_angle_rad: 0.0,
        effect_lifetime_sec: 0.0,
        hit_particle_color: [0.9, 0.9, 0.3, 0.6]
      }
    ]
  end
end
