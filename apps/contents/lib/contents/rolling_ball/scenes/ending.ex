defmodule Content.RollingBall.Scenes.Ending do
  @moduledoc """
  RollingBall のエンディングシーン。

  全ステージクリア後に表示される。
  「BACK TO TITLE」ボタン（`__back_to_title__` UI アクション）でタイトルに戻る。
  """
  @behaviour Core.SceneBehaviour

  @impl Core.SceneBehaviour
  def init(_init_arg), do: {:ok, %{back_to_title: false}}

  @impl Core.SceneBehaviour
  def render_type, do: :playing

  @impl Core.SceneBehaviour
  def update(_context, state) do
    if Map.get(state, :back_to_title, false) do
      {:transition, {:replace, Content.RollingBall.Scenes.Title, %{}}, state}
    else
      {:continue, state}
    end
  end
end
