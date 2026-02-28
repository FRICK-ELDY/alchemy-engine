defmodule GameEngine.RuleBehaviour do
  @moduledoc """
  ルール定義がエンジンに提供すべきインターフェース。

  Rule はゲームコンテンツ固有の「遊び方」の定義であり、
  シーン構成・ゲームロジック・コンテキストデフォルト値を提供する。
  同じ World に対して複数の Rule を適用できる。
  """

  @type scene_spec :: %{module: module(), init_arg: term()}

  @doc "デフォルトの render_type を返す（シーンスタックが空の場合に使用）"
  @callback render_type() :: atom()

  @doc "ゲーム開始時の初期シーンスタックを返す"
  @callback initial_scenes() :: [scene_spec()]

  @doc "物理演算を実行するシーンのモジュールリストを返す"
  @callback physics_scenes() :: [module()]

  @doc "ゲームタイトルを返す"
  @callback title() :: String.t()

  @doc "ゲームバージョンを返す"
  @callback version() :: String.t()

  @doc "context に追加するルール固有のデフォルト値を返す"
  @callback context_defaults() :: map()

  @doc "メインのプレイシーンモジュールを返す（Playing シーンの state 操作に使用）"
  @callback playing_scene() :: module()

  @doc "武器選択肢を生成する（weapon_levels を受け取り、選択肢リストを返す）"
  @callback generate_weapon_choices(weapon_levels :: map()) :: [atom()]

  @doc "レベルアップ時に Playing シーンの state を更新する"
  @callback apply_level_up(scene_state :: map(), choices :: [atom()]) :: map()

  @doc "武器選択時に Playing シーンの state を更新する"
  @callback apply_weapon_selected(scene_state :: map(), weapon :: atom()) :: map()

  @doc "レベルアップスキップ時に Playing シーンの state を更新する"
  @callback apply_level_up_skipped(scene_state :: map()) :: map()

  @doc "ゲームオーバーシーンのモジュールを返す"
  @callback game_over_scene() :: module()

  @doc "レベルアップ武器選択シーンのモジュールを返す"
  @callback level_up_scene() :: module()

  @doc "ボス出現警告シーンのモジュールを返す"
  @callback boss_alert_scene() :: module()

  @doc "経過秒数からウェーブラベル文字列を返す（ログ用）"
  @callback wave_label(elapsed_sec :: float()) :: String.t()
end
