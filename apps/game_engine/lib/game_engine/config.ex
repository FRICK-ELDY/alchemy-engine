defmodule GameEngine.Config do
  @moduledoc """
  ゲームエンジンの設定解決ヘルパー。

  `:current_rule` / `:current_world` の新設定キーを優先し、
  旧設定キー `:current_game` にフォールバックする。
  """

  @default GameContent.VampireSurvivor

  @doc "RuleBehaviour を実装したモジュールを返す"
  def current_rule do
    Application.get_env(:game_server, :current_rule) ||
      Application.get_env(:game_server, :current_game, @default)
  end

  @doc "WorldBehaviour を実装したモジュールを返す"
  def current_world do
    Application.get_env(:game_server, :current_world) ||
      Application.get_env(:game_server, :current_game, @default)
  end
end
