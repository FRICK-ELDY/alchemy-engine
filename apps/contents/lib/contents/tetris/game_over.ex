defmodule Content.Tetris.Scenes.GameOver do
  @moduledoc """
  Tetris サンプルのゲームオーバーシーン。
  """
  @behaviour Contents.SceneBehaviour

  @impl Contents.SceneBehaviour
  def init(init_arg), do: {:ok, init_arg}

  @impl Contents.SceneBehaviour
  def render_type, do: :game_over

  @impl Contents.SceneBehaviour
  def update(_context, state) do
    if Map.get(state, :retry, false) do
      {:transition, {:replace, Content.Tetris.Scenes.Playing, %{}}, state}
    else
      {:continue, state}
    end
  end
end
