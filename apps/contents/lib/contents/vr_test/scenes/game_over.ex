defmodule Content.VRTest.Scenes.GameOver do
  @moduledoc """
  VRTest のゲームオーバーシーン。

  敵に捕まった後の終了状態。
  RETRY ボタンでプレイ中シーンに戻る。
  """
  @behaviour Core.SceneBehaviour

  @impl Core.SceneBehaviour
  def init(init_arg), do: {:ok, init_arg}

  @impl Core.SceneBehaviour
  def render_type, do: :game_over

  @impl Core.SceneBehaviour
  def update(_context, state) do
    if Map.get(state, :retry, false) do
      {:transition, {:replace, Content.VRTest.Scenes.Playing, %{}}, state}
    else
      {:continue, state}
    end
  end
end
