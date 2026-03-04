defmodule Content.AsteroidArena.Scenes.GameOver do
  @moduledoc """
  AsteroidArena のゲームオーバーシーン。スコア表示・リトライ待機。
  """
  @behaviour Contents.SceneBehaviour

  @impl Contents.SceneBehaviour
  def init(_init_arg), do: {:ok, %{}}

  @impl Contents.SceneBehaviour
  def render_type, do: :game_over

  @impl Contents.SceneBehaviour
  def update(_context, state) do
    {:continue, state}
  end
end
