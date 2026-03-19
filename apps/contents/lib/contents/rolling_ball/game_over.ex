defmodule Content.RollingBall.GameOver do
  @moduledoc """
  RollingBall のゲームオーバーシーン。

  「RETRY」ボタン（`__retry__` UI アクション）で遷移する。
  - リトライ残数 > 0 → 同ステージの Playing シーンに戻る
  - リトライ残数 = 0 → Title シーンに戻る

  init_arg に `stage` と `retries_left` を受け取る。
  """
  @behaviour Contents.SceneBehaviour

  @impl Contents.SceneBehaviour
  def init(init_arg) do
    {:ok, Map.merge(%{retry: false}, init_arg)}
  end

  @impl Contents.SceneBehaviour
  def render_type, do: :game_over

  @impl Contents.SceneBehaviour
  def update(_context, state) do
    if Map.get(state, :retry, false) do
      retries_left = Map.get(state, :retries_left, 0)

      if retries_left > 0 do
        {:transition,
         {:replace, Content.RollingBall.Playing,
          %{stage: state.stage, retries_left: retries_left}}, state}
      else
        {:transition, {:replace, Content.RollingBall.Title, %{}}, state}
      end
    else
      {:continue, state}
    end
  end
end
