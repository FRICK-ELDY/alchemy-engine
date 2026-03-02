defmodule GameContent.RollingBall.Scenes.Title do
  @moduledoc """
  RollingBall のタイトルシーン。

  「START」ボタン（`__start__` UI アクション）でステージ1のプレイ中シーンに遷移する。
  """
  @behaviour GameEngine.SceneBehaviour

  @impl GameEngine.SceneBehaviour
  def init(_init_arg), do: {:ok, %{start: false}}

  @impl GameEngine.SceneBehaviour
  def render_type, do: :playing

  @impl GameEngine.SceneBehaviour
  def update(_context, state) do
    if Map.get(state, :start, false) do
      {:transition,
       {:replace, GameContent.RollingBall.Scenes.Playing, %{stage: 1, retries_left: 3}}, state}
    else
      {:continue, state}
    end
  end
end
