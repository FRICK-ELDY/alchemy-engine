defmodule Content.RollingBall.Ending do
  @moduledoc """
  RollingBall のエンディングシーン。

  全ステージクリア後に表示される。
  「BACK TO TITLE」ボタン（`__back_to_title__` UI アクション）でタイトルに戻る。
  """
  @behaviour Contents.SceneBehaviour

  @impl Contents.SceneBehaviour
  def init(_init_arg), do: {:ok, %{back_to_title: false}}

  @impl Contents.SceneBehaviour
  def render_type, do: :playing

  @impl Contents.SceneBehaviour
  def update(_context, state) do
    if Map.get(state, :back_to_title, false) do
      {:transition, {:replace, Content.RollingBall.Title, %{}}, state}
    else
      {:continue, state}
    end
  end
end
