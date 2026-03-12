defmodule Contents.Nodes.Category.Operators.Boolean.Xor do
  @moduledoc """
  排他的論理和。
  """
  @behaviour Contents.Nodes.Core.Behaviour

  @impl Contents.Nodes.Core.Behaviour
  def handle_sample(%{a: a, b: b}, _context), do: (a or b) and (a != b)
  def handle_sample(_inputs, _context), do: false
end
