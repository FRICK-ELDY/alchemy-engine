defmodule Contents.Components.Category.UI.Layout.ContentsSizeFitter do
  @moduledoc """
  コンテンツサイズフィッター。子要素の内容に合わせてレイアウトを調整する。
  """
  @behaviour Contents.Behaviour.Components

  @impl Contents.Behaviour.Components
  def on_ready(state), do: state

  @impl Contents.Behaviour.Components
  def on_process(state, _delta), do: state
end
