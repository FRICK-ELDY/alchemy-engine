defmodule Contents.Components.Category.UI.Layout.HorizontalLayout do
  @moduledoc """
  水平レイアウト。子要素を横方向に並べる。
  """
  @behaviour Contents.Components.Core.Behaviour

  @impl Contents.Components.Core.Behaviour
  def on_ready(state), do: state

  @impl Contents.Components.Core.Behaviour
  def on_process(state, _delta), do: state
end
