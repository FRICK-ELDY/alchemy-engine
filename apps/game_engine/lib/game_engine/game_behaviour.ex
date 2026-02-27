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
end
