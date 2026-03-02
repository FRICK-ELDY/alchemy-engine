defmodule GameContent.SimpleBox3D.Scenes.GameOver do
  @moduledoc """
  SimpleBox3D のゲームオーバーシーン。

  敵に捕まった後の終了状態。
  RETRY ボタン（`__retry__` UI アクション）でプレイ中シーンに戻る。
  """
  @behaviour GameEngine.SceneBehaviour

  @impl GameEngine.SceneBehaviour
  def init(init_arg), do: {:ok, init_arg || %{}}

  @impl GameEngine.SceneBehaviour
  def render_type, do: :game_over

  @impl GameEngine.SceneBehaviour
  def update(_context, state) do
    if Map.get(state, :retry, false) do
      {:transition, {:replace, GameContent.SimpleBox3D.Scenes.Playing, %{}}, state}
    else
      {:continue, state}
    end
  end
end
