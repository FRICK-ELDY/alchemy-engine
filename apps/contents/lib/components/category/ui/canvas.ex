defmodule Contents.Components.Category.UI.Canvas do
  @moduledoc """
  キャンバスコンポーネント。UI 要素の描画領域を提供する。
  """
  @behaviour Contents.Components.Core.Behaviour

  @impl Contents.Components.Core.Behaviour
  def on_ready(state), do: state

  @impl Contents.Components.Core.Behaviour
  def on_process(state, _delta), do: state
end
