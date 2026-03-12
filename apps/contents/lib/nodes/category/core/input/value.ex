defmodule Contents.Nodes.Category.Core.Input.Value do
  @moduledoc """
  定数値の入力ノード。`context[:value]` から値を取得して返す。
  """
  @behaviour Contents.Nodes.Core.Behaviour

  @impl Contents.Nodes.Core.Behaviour
  def handle_sample(_inputs, context), do: Map.get(context || %{}, :value)
end
