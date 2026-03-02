defmodule GameContent.RollingBall.Scenes.GameOver do
  @moduledoc """
  RollingBall のゲームオーバーシーン。

  「RETRY」ボタン（`__retry__` UI アクション）で遷移する。
  - リトライ残数 > 0 → 同ステージの Playing シーンに戻る
  - リトライ残数 = 0 → Title シーンに戻る

  init_arg に `stage` と `retries_left` を受け取る。
  """
  @behaviour GameEngine.SceneBehaviour

  @impl GameEngine.SceneBehaviour
  def init(init_arg) do
    {:ok, Map.merge(%{retry: false}, init_arg)}
  end

  @impl GameEngine.SceneBehaviour
  def render_type, do: :game_over

  @impl GameEngine.SceneBehaviour
  def update(_context, state) do
    if Map.get(state, :retry, false) do
      retries_left = Map.get(state, :retries_left, 0)

      if retries_left > 0 do
        {:transition,
         {:replace, GameContent.RollingBall.Scenes.Playing,
          %{stage: state.stage, retries_left: retries_left}}, state}
      else
        {:transition, {:replace, GameContent.RollingBall.Scenes.Title, %{}}, state}
      end
    else
      {:continue, state}
    end
  end
end
