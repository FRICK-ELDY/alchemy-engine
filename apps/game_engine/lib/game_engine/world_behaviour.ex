defmodule GameEngine.WorldBehaviour do
  @moduledoc """
  ワールド定義がエンジンに提供すべきインターフェース。

  World はゲームコンテンツに依存しない「舞台」の定義であり、
  マップ・エンティティ種別・アセットパスを提供する。
  同じ World に対して複数の Rule を適用できる。
  """

  @doc "アセットファイルのベースパスを返す"
  @callback assets_path() :: String.t()

  @doc """
  エンティティ種別の ID マッピングを返す。

  エンジンは atom → u8 の変換にこのマッピングを使用する。
  例: %{enemies: %{slime: 0, bat: 1}, bosses: %{slime_king: 0}, weapons: %{magic_wand: 0}}
  """
  @callback entity_registry() :: map()
end
