defmodule Contents.Nodes.Category.Operators.Div do
  @moduledoc """
  除算ノード。
  """
  @behaviour Contents.Nodes.Core.Behaviour

  @impl Contents.Nodes.Core.Behaviour
  def handle_sample(%{a: a, b: b}, _context) when b != 0, do: a / b
  def handle_sample(_inputs, _context), do: 0
end
