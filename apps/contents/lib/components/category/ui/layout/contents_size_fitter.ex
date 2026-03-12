defmodule Contents.Components.Category.UI.Layout.ContentsSizeFitter do
  @moduledoc """
  コンテンツサイズフィッター。子要素の内容に合わせてレイアウトを調整する。
  """
  @behaviour Contents.Components.Core.Behaviour

  @impl Contents.Components.Core.Behaviour
  def on_ready(state), do: state

  @impl Contents.Components.Core.Behaviour
  def on_process(state, _delta), do: state
end
