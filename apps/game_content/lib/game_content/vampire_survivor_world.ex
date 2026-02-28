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
    # {max_hp, speed, radius, exp_reward, damage_per_sec, render_kind, passes_obstacles}
    [
      {30.0,  80.0,  20.0, 5,  20.0, 1, false},  # 0: Slime
      {15.0,  160.0, 12.0, 3,  10.0, 2, false},  # 1: Bat
      {150.0, 40.0,  32.0, 20, 40.0, 3, false},  # 2: Golem
      {60.0,  60.0,  22.0, 10, 15.0, 5, false},  # 3: Skeleton
      {40.0,  100.0, 16.0, 8,  12.0, 4, true},   # 4: Ghost（壁すり抜け）
    ]
  end

  defp weapon_params do
    # {cooldown, damage, as_u8, name, bullet_table_or_nil}
    [
      {1.0, 10, 0, "magic_wand", [0, 1, 1, 2, 2, 3, 3, 4, 4]},  # 0
      {1.5, 25, 1, "axe",        nil},                            # 1
      {2.0, 15, 2, "cross",      [0, 4, 4, 4, 8, 8, 8, 8, 8]},   # 2
      {1.0, 30, 3, "whip",       nil},                            # 3
      {1.0, 20, 4, "fireball",   nil},                            # 4
      {1.0, 15, 5, "lightning",  nil},                            # 5
      {0.2, 1,  6, "garlic",     nil},                            # 6
    ]
  end

  defp boss_params do
    # {max_hp, speed, radius, exp_reward, damage_per_sec, render_kind, special_interval}
    [
      {1000.0, 60.0,  48.0, 200, 30.0, 11, 5.0},  # 0: Slime King
      {2000.0, 200.0, 48.0, 400, 50.0, 12, 4.0},  # 1: Bat Lord
      {5000.0, 30.0,  64.0, 800, 80.0, 13, 6.0},  # 2: Stone Golem
    ]
  end
end
