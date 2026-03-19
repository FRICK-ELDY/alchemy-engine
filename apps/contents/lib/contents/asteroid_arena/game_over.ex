defmodule Content.AsteroidArena.GameOver do
  @moduledoc """
  AsteroidArena のゲームオーバーシーン。

  意図的なスタブ: スコア表示・リトライボタンは NIF 側の HUD で描画されるため、
  本シーンは終了状態を保持するのみ。update/2 は常に {:continue, state} を返す。
  """
  @behaviour Contents.SceneBehaviour

  @impl Contents.SceneBehaviour
  def init(_init_arg), do: {:ok, %{}}

  @impl Contents.SceneBehaviour
  def render_type, do: :game_over

  @impl Contents.SceneBehaviour
  def update(_context, state) do
    {:continue, state}
  end
end
