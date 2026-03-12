defmodule Contents.Nodes.Category.Operators.Mul do
  @moduledoc """
  乗算ノード。
  """
  @behaviour Contents.Nodes.Core.Behaviour

  @impl Contents.Nodes.Core.Behaviour
  def handle_sample(%{a: a, b: b}, _context), do: a * b
  def handle_sample(_inputs, _context), do: 0
end
