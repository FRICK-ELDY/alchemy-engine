defmodule Contents.Nodes.Category.Operators.Boolean.Nand do
  @moduledoc """
  論理積の否定。`a` と `b` は boolean を期待。非 boolean は truthy/falsy として扱う。
  """
  @behaviour Contents.Behaviour.Nodes

  @impl Contents.Behaviour.Nodes
  def handle_sample(%{a: a, b: b}, _context), do: not (to_bool(a) and to_bool(b))
  def handle_sample(_inputs, _context), do: true

  defp to_bool(nil), do: false
  defp to_bool(false), do: false
  defp to_bool(_), do: true
end
