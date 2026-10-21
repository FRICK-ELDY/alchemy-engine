defmodule Contents.Components.Category.Uncategorized.Comment do
  @moduledoc """
  VR 空間内のドキュメント化（付箋）用コンポーネント。

  ノートやコメントを空間に配置し、開発・設計時の参照を可能にする。
  """
  @behaviour Contents.Behaviour.Components

  @impl Contents.Behaviour.Components
  def on_ready(state), do: state

  @impl Contents.Behaviour.Components
  def on_process(state, _delta), do: state
end
