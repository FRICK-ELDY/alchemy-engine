defmodule GameContent.VampireSurvivor do
  @moduledoc """
  **廃止予定**: `GameContent.VampireSurvivorWorld` と `GameContent.VampireSurvivorRule` に分割されました。

  このモジュールは後方互換のために残されています。
  設定ファイルでは以下のように移行してください:

      # 旧
      config :game_server, current_game: GameContent.VampireSurvivor

      # 新
      config :game_server,
        current_world: GameContent.VampireSurvivorWorld,
        current_rule:  GameContent.VampireSurvivorRule
  """

  @behaviour GameEngine.GameBehaviour

  # ── WorldBehaviour 由来 ────────────────────────────────────────────

  @impl GameEngine.GameBehaviour
  def assets_path, do: GameContent.VampireSurvivorWorld.assets_path()

  @impl GameEngine.GameBehaviour
  def entity_registry, do: GameContent.VampireSurvivorWorld.entity_registry()

  # ── RuleBehaviour 由来 ────────────────────────────────────────────

  @impl GameEngine.GameBehaviour
  def render_type, do: GameContent.VampireSurvivorRule.render_type()

  @impl GameEngine.GameBehaviour
  def initial_scenes, do: GameContent.VampireSurvivorRule.initial_scenes()

  @impl GameEngine.GameBehaviour
  def physics_scenes, do: GameContent.VampireSurvivorRule.physics_scenes()

  @impl GameEngine.GameBehaviour
  def title, do: GameContent.VampireSurvivorRule.title()

  @impl GameEngine.GameBehaviour
  def version, do: GameContent.VampireSurvivorRule.version()

  @impl GameEngine.GameBehaviour
  def context_defaults, do: GameContent.VampireSurvivorRule.context_defaults()

  @impl GameEngine.GameBehaviour
  def playing_scene, do: GameContent.VampireSurvivorRule.playing_scene()

  @impl GameEngine.GameBehaviour
  def generate_weapon_choices(weapon_levels),
    do: GameContent.VampireSurvivorRule.generate_weapon_choices(weapon_levels)

  @impl GameEngine.GameBehaviour
  def apply_level_up(scene_state, choices),
    do: GameContent.VampireSurvivorRule.apply_level_up(scene_state, choices)

  @impl GameEngine.GameBehaviour
  def apply_weapon_selected(scene_state, weapon),
    do: GameContent.VampireSurvivorRule.apply_weapon_selected(scene_state, weapon)

  @impl GameEngine.GameBehaviour
  def apply_level_up_skipped(scene_state),
    do: GameContent.VampireSurvivorRule.apply_level_up_skipped(scene_state)

  @impl GameEngine.GameBehaviour
  def game_over_scene, do: GameContent.VampireSurvivorRule.game_over_scene()

  @impl GameEngine.GameBehaviour
  def level_up_scene, do: GameContent.VampireSurvivorRule.level_up_scene()

  @impl GameEngine.GameBehaviour
  def boss_alert_scene, do: GameContent.VampireSurvivorRule.boss_alert_scene()

  @impl GameEngine.GameBehaviour
  def wave_label(elapsed_sec),
    do: GameContent.VampireSurvivorRule.wave_label(elapsed_sec)

  # ── 後方互換（weapon_label は RuleBehaviour 外の固有メソッド）────────

  def weapon_label(weapon, level) do
    GameContent.VampireSurvivor.LevelSystem.weapon_label(weapon, level)
  end
end
