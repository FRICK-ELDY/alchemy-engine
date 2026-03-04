defmodule Content.RollingBall.Scenes.StageClear do
  @moduledoc """
  RollingBall のステージクリアシーン。

  「NEXT STAGE」ボタン（`__next_stage__` UI アクション）で次ステージに遷移する。
  init_arg に `next_stage` と `retries_left` を受け取る。
  """
  @behaviour Core.SceneBehaviour

  @impl Core.SceneBehaviour
  def init(init_arg) do
    {:ok, Map.merge(%{next: false}, init_arg)}
  end

  @impl Core.SceneBehaviour
  def render_type, do: :playing

  @impl Core.SceneBehaviour
  def update(_context, state) do
    if Map.get(state, :next, false) do
      {:transition,
       {:replace, Content.RollingBall.Scenes.Playing,
        %{stage: state.next_stage, retries_left: state.retries_left}}, state}
    else
      {:continue, state}
    end
  end
end
