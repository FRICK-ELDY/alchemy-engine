defmodule GameContent.VampireSurvivor do
  @moduledoc """
  ヴァンパイアサバイバーの GameBehaviour 実装。
  初期シーン・物理演算対象シーン・エンティティ ID マッピングを提供する。
  """
  @behaviour GameEngine.GameBehaviour

  @impl GameEngine.GameBehaviour
  def render_type, do: :playing

  @impl GameEngine.GameBehaviour
  def initial_scenes do
    [
      %{module: GameContent.VampireSurvivor.Scenes.Playing, init_arg: %{}}
    ]
  end

  @impl GameEngine.GameBehaviour
  def entity_registry do
    %{
      enemies: %{slime: 0, bat: 1, golem: 2, skeleton: 3, ghost: 4},
      weapons: %{
        magic_wand: 0, axe: 1, cross: 2, whip: 3, fireball: 4, lightning: 5, garlic: 6
      },
      bosses: %{slime_king: 0, bat_lord: 1, stone_golem: 2},
    }
  end

  @impl GameEngine.GameBehaviour
  def physics_scenes do
    [GameContent.VampireSurvivor.Scenes.Playing]
  end

  @impl GameEngine.GameBehaviour
  def title, do: "Vampire Survivor"

  @impl GameEngine.GameBehaviour
  def version, do: "0.1.0"

  @impl GameEngine.GameBehaviour
  def context_defaults, do: %{}

  @impl GameEngine.GameBehaviour
  def assets_path, do: "vampire_survivor"

  @impl GameEngine.GameBehaviour
  def playing_scene, do: GameContent.VampireSurvivor.Scenes.Playing

  @impl GameEngine.GameBehaviour
  def generate_weapon_choices(weapon_levels) do
    GameContent.VampireSurvivor.LevelSystem.generate_weapon_choices(weapon_levels)
  end

  @impl GameEngine.GameBehaviour
  def apply_level_up(scene_state, choices) do
    GameContent.VampireSurvivor.Scenes.Playing.apply_level_up(scene_state, choices)
  end

  @impl GameEngine.GameBehaviour
  def apply_weapon_selected(scene_state, weapon) do
    GameContent.VampireSurvivor.Scenes.Playing.apply_weapon_selected(scene_state, weapon)
  end

  @impl GameEngine.GameBehaviour
  def apply_level_up_skipped(scene_state) do
    GameContent.VampireSurvivor.Scenes.Playing.apply_level_up_skipped(scene_state)
  end

  # ── Vampire Survivor 固有 ──────────────────────────────────────────

  def level_up_scene, do: GameContent.VampireSurvivor.Scenes.LevelUp
  def boss_alert_scene, do: GameContent.VampireSurvivor.Scenes.BossAlert
  def game_over_scene, do: GameContent.VampireSurvivor.Scenes.GameOver

  def wave_label(elapsed_sec) do
    GameContent.VampireSurvivor.SpawnSystem.wave_label(elapsed_sec)
  end

  def weapon_label(weapon, level) do
    GameContent.VampireSurvivor.LevelSystem.weapon_label(weapon, level)
  end
end
