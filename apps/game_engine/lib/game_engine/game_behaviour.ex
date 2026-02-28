defmodule GameEngine.GameBehaviour do
  @moduledoc """
  **廃止予定**: `GameEngine.WorldBehaviour` と `GameEngine.RuleBehaviour` に分割されました。

  このモジュールは Phase 2 で廃止されます。
  新しいコンテンツは `WorldBehaviour` と `RuleBehaviour` を直接実装してください。
  """

  @deprecated "GameEngine.WorldBehaviour と GameEngine.RuleBehaviour を使用してください"

  @type scene_spec :: %{module: module(), init_arg: term()}

  # WorldBehaviour 由来
  @callback assets_path() :: String.t()
  @callback entity_registry() :: map()

  # RuleBehaviour 由来
  @callback render_type() :: atom()
  @callback initial_scenes() :: [scene_spec()]
  @callback physics_scenes() :: [module()]
  @callback title() :: String.t()
  @callback version() :: String.t()
  @callback context_defaults() :: map()
  @callback playing_scene() :: module()
  @callback generate_weapon_choices(weapon_levels :: map()) :: [atom()]
  @callback apply_level_up(scene_state :: map(), choices :: [atom()]) :: map()
  @callback apply_weapon_selected(scene_state :: map(), weapon :: atom()) :: map()
  @callback apply_level_up_skipped(scene_state :: map()) :: map()
  @callback game_over_scene() :: module()
  @callback level_up_scene() :: module()
  @callback boss_alert_scene() :: module()
  @callback wave_label(elapsed_sec :: float()) :: String.t()
end
