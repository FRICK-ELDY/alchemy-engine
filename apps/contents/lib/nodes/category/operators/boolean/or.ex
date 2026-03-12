defmodule Contents.Nodes.Category.Operators.Boolean.Or do
  @moduledoc """
  論理和。
  """
  @behaviour Contents.Nodes.Core.Behaviour

  @impl Contents.Nodes.Core.Behaviour
  def handle_sample(%{a: a, b: b}, _context), do: a or b
  def handle_sample(_inputs, _context), do: false
end
