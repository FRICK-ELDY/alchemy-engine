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

  @doc """
  Phase 3-A: ワールド生成後に一度だけ呼び出し、Rust 側にパラメータを注入する。
  `world_ref` は `GameEngine.NifBridge.create_world/0` の戻り値。
  デフォルト実装は何もしない（後方互換）。
  """
  @callback setup_world_params(world_ref :: reference()) :: :ok

  @optional_callbacks setup_world_params: 1
end
