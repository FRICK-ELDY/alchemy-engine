defmodule Contents.Nodes.Category.Operators.Boolean.Xnor do
  @moduledoc """
  排他的論理和の否定。
  """
  @behaviour Contents.Nodes.Core.Behaviour

  @impl Contents.Nodes.Core.Behaviour
  def handle_sample(%{a: a, b: b}, _context), do: (a == b)
  def handle_sample(_inputs, _context), do: true
end
