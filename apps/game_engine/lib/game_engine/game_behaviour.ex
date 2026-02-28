defmodule GameEngine.GameBehaviour do
  @moduledoc """
  ゲームがエンジンに提供すべきインターフェース。

  エンジンは config で指定されたこの behaviour を実装したモジュールを
  起動時に取得し、初期シーン構築・物理演算対象の判定等に利用する。
  """

  @type scene_spec :: %{module: module(), init_arg: term()}

  @callback render_type() :: atom()
  @callback initial_scenes() :: [scene_spec()]
  @callback entity_registry() :: map()
  @callback physics_scenes() :: [module()]
  @callback title() :: String.t()
  @callback version() :: String.t()
  @callback context_defaults() :: map()
  @callback assets_path() :: String.t()

  @doc "メインのプレイシーンモジュールを返す（Playing シーンの state 操作に使用）"
  @callback playing_scene() :: module()

  @doc "武器選択肢を生成する（Playing シーンの state を受け取り、選択肢リストを返す）"
  @callback generate_weapon_choices(weapon_levels :: map()) :: [atom()]

  @doc "レベルアップ時に Playing シーンの state を更新する"
  @callback apply_level_up(scene_state :: map(), choices :: [atom()]) :: map()

  @doc "武器選択時に Playing シーンの state を更新する"
  @callback apply_weapon_selected(scene_state :: map(), weapon :: atom()) :: map()

  @doc "レベルアップスキップ時に Playing シーンの state を更新する"
  @callback apply_level_up_skipped(scene_state :: map()) :: map()

end
