defmodule GameContent.RollingBall.Scenes.Ending do
  @moduledoc """
  RollingBall のエンディングシーン。

  全ステージクリア後に表示される。
  「BACK TO TITLE」ボタン（`__back_to_title__` UI アクション）でタイトルに戻る。
  """
  @behaviour GameEngine.SceneBehaviour

  @impl GameEngine.SceneBehaviour
  def init(_init_arg), do: {:ok, %{back_to_title: false}}

  @impl GameEngine.SceneBehaviour
  def render_type, do: :playing

  @impl GameEngine.SceneBehaviour
  def update(_context, state) do
    if Map.get(state, :back_to_title, false) do
      {:transition, {:replace, GameContent.RollingBall.Scenes.Title, %{}}, state}
    else
      {:continue, state}
    end
  end
end
