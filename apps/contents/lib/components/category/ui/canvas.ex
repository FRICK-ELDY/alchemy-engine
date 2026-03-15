defmodule Contents.Components.Category.UI.Canvas do
  @moduledoc """
  キャンバスコンポーネント。UI 要素の描画領域を提供する。
  """
  @behaviour Contents.Behaviour.Components

  @impl Contents.Behaviour.Components
  def on_ready(state), do: state

  @impl Contents.Behaviour.Components
  def on_process(state, _delta), do: state
end
