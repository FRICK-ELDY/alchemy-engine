defmodule Contents.Components.Category.UI.Layout.VerticalLayout do
  @moduledoc """
  垂直レイアウト。子要素を縦方向に並べる。
  """
  @behaviour Contents.Behaviour.Components

  @impl Contents.Behaviour.Components
  def on_ready(state), do: state

  @impl Contents.Behaviour.Components
  def on_process(state, _delta), do: state
end
