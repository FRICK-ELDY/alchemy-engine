defmodule GameContent.VampireSurvivorRule do
  @moduledoc """
  ヴァンパイアサバイバーの RuleBehaviour 実装。

  シーン構成・ゲームロジック・スポーン/ボス/レベルアップの制御を定義する。
  `VampireSurvivorWorld` と組み合わせて使用する。
  """
  @behaviour GameEngine.RuleBehaviour

  @impl GameEngine.RuleBehaviour
  def render_type, do: :playing

  @impl GameEngine.RuleBehaviour
  def initial_scenes do
    [
      %{module: GameContent.VampireSurvivor.Scenes.Playing, init_arg: %{}}
    ]
  end

  @impl GameEngine.RuleBehaviour
  def physics_scenes do
    [GameContent.VampireSurvivor.Scenes.Playing]
  end

  @impl GameEngine.RuleBehaviour
  def title, do: "Vampire Survivor"

  @impl GameEngine.RuleBehaviour
  def version, do: "0.1.0"

  @impl GameEngine.RuleBehaviour
  def context_defaults, do: %{}

  @impl GameEngine.RuleBehaviour
  def playing_scene, do: GameContent.VampireSurvivor.Scenes.Playing

  @impl GameEngine.RuleBehaviour
  def generate_weapon_choices(weapon_levels) do
    GameContent.VampireSurvivor.LevelSystem.generate_weapon_choices(weapon_levels)
  end

  @impl GameEngine.RuleBehaviour
  def apply_level_up(scene_state, choices) do
    GameContent.VampireSurvivor.Scenes.Playing.apply_level_up(scene_state, choices)
  end

  @impl GameEngine.RuleBehaviour
  def apply_weapon_selected(scene_state, weapon) do
    GameContent.VampireSurvivor.Scenes.Playing.apply_weapon_selected(scene_state, weapon)
  end

  @impl GameEngine.RuleBehaviour
  def apply_level_up_skipped(scene_state) do
    GameContent.VampireSurvivor.Scenes.Playing.apply_level_up_skipped(scene_state)
  end

  @impl GameEngine.RuleBehaviour
  def game_over_scene, do: GameContent.VampireSurvivor.Scenes.GameOver

  @impl GameEngine.RuleBehaviour
  def level_up_scene, do: GameContent.VampireSurvivor.Scenes.LevelUp

  @impl GameEngine.RuleBehaviour
  def boss_alert_scene, do: GameContent.VampireSurvivor.Scenes.BossAlert

  @impl GameEngine.RuleBehaviour
  def wave_label(elapsed_sec) do
    GameContent.VampireSurvivor.SpawnSystem.wave_label(elapsed_sec)
  end
end
