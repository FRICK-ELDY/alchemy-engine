defmodule GameContent.AsteroidArena.Scenes.GameOver do
  @moduledoc """
  AsteroidArena のゲームオーバーシーン。スコア表示・リトライ待機。
  """
  @behaviour GameEngine.SceneBehaviour

  @impl GameEngine.SceneBehaviour
  def init(_init_arg), do: {:ok, %{}}

  @impl GameEngine.SceneBehaviour
  def render_type, do: :game_over

  @impl GameEngine.SceneBehaviour
  def update(_context, state) do
    {:continue, state}
  end
end
