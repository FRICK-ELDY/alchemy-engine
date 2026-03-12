defmodule Contents.Components.Category.UI.RectTransform do
  @moduledoc """
  矩形変換コンポーネント。2D/UI 空間における位置・回転・スケール・アンカーを管理する。
  """
  @behaviour Contents.Components.Core.Behaviour

  @impl Contents.Components.Core.Behaviour
  def on_ready(state), do: state

  @impl Contents.Components.Core.Behaviour
  def on_process(state, _delta), do: state
end
