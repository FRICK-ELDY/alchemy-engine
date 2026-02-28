defmodule GameEngine.Config do
  @moduledoc """
  ゲームエンジンの設定解決ヘルパー。

  `:current_rule` / `:current_world` の設定キーを使用する。
  """

  @default_rule  GameContent.VampireSurvivorRule
  @default_world GameContent.VampireSurvivorWorld

  @doc "RuleBehaviour を実装したモジュールを返す"
  def current_rule do
    Application.get_env(:game_server, :current_rule, @default_rule)
  end

  @doc "WorldBehaviour を実装したモジュールを返す"
  def current_world do
    Application.get_env(:game_server, :current_world, @default_world)
  end
end
