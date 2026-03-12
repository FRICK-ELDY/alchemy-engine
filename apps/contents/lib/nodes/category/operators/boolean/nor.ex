defmodule Contents.Nodes.Category.Operators.Boolean.Nor do
  @moduledoc """
  論理和の否定。
  """
  @behaviour Contents.Nodes.Core.Behaviour

  @impl Contents.Nodes.Core.Behaviour
  def handle_sample(%{a: a, b: b}, _context), do: not (a or b)
  def handle_sample(_inputs, _context), do: true
end
