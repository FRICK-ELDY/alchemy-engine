defmodule Content.BulletHell3D.GameOver do
  @moduledoc """
  BulletHell3D のゲームオーバーシーン。

  HP が 0 になった後の終了状態。
  RETRY ボタン（`__retry__` UI アクション）でプレイ中シーンに戻る。
  """
  @behaviour Contents.SceneBehaviour

  @impl Contents.SceneBehaviour
  def init(init_arg) do
    state = (init_arg || %{}) |> Map.take([:elapsed_sec])
    {:ok, state}
  end

  @impl Contents.SceneBehaviour
  def render_type, do: :game_over

  @impl Contents.SceneBehaviour
  def update(_context, state) do
    if Map.get(state, :retry, false) do
      {:transition, {:replace, Content.BulletHell3D.Playing, %{}}, state}
    else
      {:continue, state}
    end
  end
end
