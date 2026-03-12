defmodule Contents.Components.Category.UI.Layout.LayoutElement do
  @moduledoc """
  レイアウト要素。幅・高さ・マージン等のレイアウト制御を行う。
  """
  @behaviour Contents.Components.Core.Behaviour

  @impl Contents.Components.Core.Behaviour
  def on_ready(state), do: state

  @impl Contents.Components.Core.Behaviour
  def on_process(state, _delta), do: state
end
