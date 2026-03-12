defmodule Contents.Components.Category.UI.Layout.GridLayout do
  @moduledoc """
  グリッドレイアウト。子要素を格子状に配置する。
  """
  @behaviour Contents.Components.Core.Behaviour

  @impl Contents.Components.Core.Behaviour
  def on_ready(state), do: state

  @impl Contents.Components.Core.Behaviour
  def on_process(state, _delta), do: state
end
