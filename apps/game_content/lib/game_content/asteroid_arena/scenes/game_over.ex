defmodule GameContent.AsteroidArena.Scenes.GameOver do
  @moduledoc """
  AsteroidArena のゲームオーバーシーン。スコア表示・リトライ待機。
  """
  @behaviour Core.SceneBehaviour

  @impl Core.SceneBehaviour
  def init(_init_arg), do: {:ok, %{}}

  @impl Core.SceneBehaviour
  def render_type, do: :game_over

  @impl Core.SceneBehaviour
  def update(_context, state) do
    {:continue, state}
  end
end
