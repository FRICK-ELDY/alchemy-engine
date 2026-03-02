defmodule GameContent.RollingBall.Scenes.StageClear do
  @moduledoc """
  RollingBall のステージクリアシーン。

  「NEXT STAGE」ボタン（`__next_stage__` UI アクション）で次ステージに遷移する。
  init_arg に `next_stage` と `retries_left` を受け取る。
  """
  @behaviour GameEngine.SceneBehaviour

  @impl GameEngine.SceneBehaviour
  def init(init_arg) do
    {:ok, Map.merge(%{next: false}, init_arg)}
  end

  @impl GameEngine.SceneBehaviour
  def render_type, do: :playing

  @impl GameEngine.SceneBehaviour
  def update(_context, state) do
    if Map.get(state, :next, false) do
      {:transition,
       {:replace, GameContent.RollingBall.Scenes.Playing,
        %{stage: state.next_stage, retries_left: state.retries_left}}, state}
    else
      {:continue, state}
    end
  end
end
