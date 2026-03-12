defmodule Contents.Nodes.Category.Operators.Boolean.And do
  @moduledoc """
  論理積。
  """
  @behaviour Contents.Nodes.Core.Behaviour

  @impl Contents.Nodes.Core.Behaviour
  def handle_sample(%{a: a, b: b}, _context), do: a and b
  def handle_sample(_inputs, _context), do: false
end
