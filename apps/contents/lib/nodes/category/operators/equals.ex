defmodule Contents.Nodes.Category.Operators.Equals do
  @moduledoc """
  比較ノード（equals, greater, less 等）。
  """
  @behaviour Contents.Nodes.Core.Behaviour

  @impl Contents.Nodes.Core.Behaviour
  def handle_sample(%{a: a, b: b, op: op}, _context) do
    case op do
      :eq -> a == b
      :ne -> a != b
      :gt -> a > b
      :ge -> a >= b
      :lt -> a < b
      :le -> a <= b
      _ -> a == b
    end
  end

  def handle_sample(%{a: a, b: b}, _context), do: a == b
  def handle_sample(_inputs, _context), do: false
end
