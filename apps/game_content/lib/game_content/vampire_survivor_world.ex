defmodule GameContent.VampireSurvivorWorld do
  @moduledoc """
  ヴァンパイアサバイバーの WorldBehaviour 実装。

  マップ・エンティティ種別・アセットパスを定義する。
  同じ World に対して複数の Rule を適用できる。
  """
  @behaviour GameEngine.WorldBehaviour

  @map_width  4096.0
  @map_height 4096.0

  @impl GameEngine.WorldBehaviour
  def assets_path, do: "vampire_survivor"

  @impl GameEngine.WorldBehaviour
  def entity_registry do
    %{
      enemies: %{slime: 0, bat: 1, golem: 2, skeleton: 3, ghost: 4},
      weapons: %{
        magic_wand: 0, axe: 1, cross: 2, whip: 3, fireball: 4, lightning: 5, garlic: 6
      },
      bosses: %{slime_king: 0, bat_lord: 1, stone_golem: 2},
    }
  end

  @doc """
  Phase 3-A: ワールド生成後に一度だけ呼び出し、Rust 側にパラメータを注入する。
  `world_ref` は `GameEngine.NifBridge.create_world/0` の戻り値。
  """
  def setup_world_params(world_ref) do
    GameEngine.NifBridge.set_world_size(world_ref, @map_width, @map_height)
    GameEngine.NifBridge.set_entity_params(
      world_ref,
      enemy_params(),
      weapon_params(),
      boss_params()
    )
  end

  # ── エンティティパラメータ定義 ────────────────────────────────────
  # 各タプルの要素は Rust 側 decode_enemy_params / decode_weapon_params /
  # decode_boss_params の順序と一致させること。

  defp enemy_params do
    [
      %{max_hp: 30.0,  speed: 80.0,  radius: 20.0, exp_reward: 5,  damage_per_sec: 20.0, render_kind: 1, passes_obstacles: false},  # 0: Slime
      %{max_hp: 15.0,  speed: 160.0, radius: 12.0, exp_reward: 3,  damage_per_sec: 10.0, render_kind: 2, passes_obstacles: false},  # 1: Bat
      %{max_hp: 150.0, speed: 40.0,  radius: 32.0, exp_reward: 20, damage_per_sec: 40.0, render_kind: 3, passes_obstacles: false},  # 2: Golem
      %{max_hp: 60.0,  speed: 60.0,  radius: 22.0, exp_reward: 10, damage_per_sec: 15.0, render_kind: 5, passes_obstacles: false},  # 3: Skeleton
      %{max_hp: 40.0,  speed: 100.0, radius: 16.0, exp_reward: 8,  damage_per_sec: 12.0, render_kind: 4, passes_obstacles: true},   # 4: Ghost（壁すり抜け）
    ]
  end

  defp weapon_params do
    [
      %{cooldown: 1.0, damage: 10, as_u8: 0, name: "magic_wand", bullet_table: [0, 1, 1, 2, 2, 3, 3, 4, 4]},  # 0
      %{cooldown: 1.5, damage: 25, as_u8: 1, name: "axe",        bullet_table: nil},                           # 1
      %{cooldown: 2.0, damage: 15, as_u8: 2, name: "cross",      bullet_table: [0, 4, 4, 4, 8, 8, 8, 8, 8]},  # 2
      %{cooldown: 1.0, damage: 30, as_u8: 3, name: "whip",       bullet_table: nil},                           # 3
      %{cooldown: 1.0, damage: 20, as_u8: 4, name: "fireball",   bullet_table: nil},                           # 4
      %{cooldown: 1.0, damage: 15, as_u8: 5, name: "lightning",  bullet_table: nil},                           # 5
      %{cooldown: 0.2, damage: 1,  as_u8: 6, name: "garlic",     bullet_table: nil},                           # 6
    ]
  end

  defp boss_params do
    [
      %{max_hp: 1000.0, speed: 60.0,  radius: 48.0, exp_reward: 200, damage_per_sec: 30.0, render_kind: 11, special_interval: 5.0},  # 0: Slime King
      %{max_hp: 2000.0, speed: 200.0, radius: 48.0, exp_reward: 400, damage_per_sec: 50.0, render_kind: 12, special_interval: 4.0},  # 1: Bat Lord
      %{max_hp: 5000.0, speed: 30.0,  radius: 64.0, exp_reward: 800, damage_per_sec: 80.0, render_kind: 13, special_interval: 6.0},  # 2: Stone Golem
    ]
  end
end
