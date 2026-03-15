defmodule Contents.Components.Category.UI.Layout.HorizontalLayout do
  @moduledoc """
  水平レイアウト。子要素を横方向に並べる。
  """
  @behaviour Contents.Behaviour.Components

  @impl Contents.Behaviour.Components
  def on_ready(state), do: state

  @impl Contents.Behaviour.Components
  def on_process(state, _delta), do: state
end
